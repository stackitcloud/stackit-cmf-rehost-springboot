#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR="$ROOT_DIR/artifacts"
SERVER_BACKUP_MAX_AGE_HOURS=${SERVER_BACKUP_MAX_AGE_HOURS:-24}
CONFIRMED=false

while (($# > 0)); do
  case "$1" in
    --confirm)
      CONFIRMED=true
      ;;
    --artifact-dir)
      shift
      ARTIFACT_DIR=${1:?Missing value for --artifact-dir}
      ;;
    *)
      echo "Usage: $0 --confirm [--artifact-dir PATH]" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$CONFIRMED" != true ]]; then
  echo "Cutover changes the target database. Re-run with --confirm after approval." >&2
  exit 1
fi

MANIFEST_PATH="$ARTIFACT_DIR/source-postgresql.manifest"
DUMP_PATH="$ARTIFACT_DIR/source-postgresql.dump"
if [[ "$DUMP_PATH" == "$ROOT_DIR/"* ]]; then
  TERRAFORM_DUMP_PATH=${DUMP_PATH#"$ROOT_DIR/"}
else
  TERRAFORM_DUMP_PATH=$DUMP_PATH
fi
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
SSH_USER=${SSH_USER:-ubuntu}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE_DIR="$ROOT_DIR/artifacts/evidence/${RUN_ID}-cutover"
PLAN_PATH="$EVIDENCE_DIR/tfplan"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS=failed

mkdir -p "$EVIDENCE_DIR"
chmod 0700 "$EVIDENCE_DIR"

write_evidence() {
  rm -f "$PLAN_PATH"
  cat >"$EVIDENCE_DIR/evidence.env" <<EOF
mode=cutover
run_id=$RUN_ID
started_at=$STARTED_AT
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=$STATUS
source_dump_sha256=${dump_checksum:-unknown}
expected_row_count=${expected_row_count:-unknown}
expected_album_fingerprint=${expected_fingerprint:-unknown}
target_vm_ip=${vm_ip:-unknown}
before_row_count=${before_row_count:-unknown}
before_album_fingerprint=${before_fingerprint:-unknown}
after_row_count=${after_row_count:-unknown}
after_album_fingerprint=${after_fingerprint:-unknown}
terraform_noop=${terraform_noop:-false}
server_backup_id=${server_backup_id:-not-required}
server_backup_created_at=${server_backup_created_at:-not-required}
EOF
}
trap write_evidence EXIT

for command in terraform ssh sed sha256sum jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

"$ROOT_DIR/scripts/validate_source_dump.sh" "$ARTIFACT_DIR"

expected_row_count=$(sed -n 's/^row_count=//p' "$MANIFEST_PATH")
expected_fingerprint=$(sed -n 's/^album_fingerprint=//p' "$MANIFEST_PATH")
dump_checksum=$(sha256sum "$DUMP_PATH")
dump_checksum=${dump_checksum%% *}
vm_ip=$(terraform -chdir="$ROOT_DIR" output -raw vm_public_ip)
server_backup_enabled=$(terraform -chdir="$ROOT_DIR" output -raw server_backup_enabled)

if [[ "$server_backup_enabled" == true ]]; then
  if ! command -v stackit >/dev/null 2>&1; then
    echo "STACKIT CLI is required to verify the pre-cutover Server Backup." >&2
    exit 1
  fi
  server_state=$(terraform -chdir="$ROOT_DIR" show -json | jq -c \
    '.values.root_module.resources[] | select(.address == "stackit_server.rehost_vm") | .values')
  project_id=$(jq -r '.project_id' <<<"$server_state")
  server_id=$(jq -r '.server_id' <<<"$server_state")
  region=$(jq -r '.region' <<<"$server_state")
  if [[ ! "$SERVER_BACKUP_MAX_AGE_HOURS" =~ ^[1-9][0-9]*$ ]]; then
    echo "SERVER_BACKUP_MAX_AGE_HOURS must be a positive integer." >&2
    exit 1
  fi
  server_backup=$(stackit server backup list \
    --server-id "$server_id" \
    --project-id "$project_id" \
    --region "$region" \
    --output-format json | jq -c --argjson max_age_hours "$SERVER_BACKUP_MAX_AGE_HOURS" '
      [.[] | select(
        .status == "available" and
        (.volumeBackups | length > 0) and
        all(.volumeBackups[]; .status == "available") and
        ((.createdAt | fromdateiso8601) >= (now - ($max_age_hours * 3600)))
      )] | sort_by(.createdAt) | last // empty
    ')
  server_backup_id=$(jq -r '.id // empty' <<<"$server_backup")
  server_backup_created_at=$(jq -r '.createdAt // empty' <<<"$server_backup")
  if [[ -z "$server_backup_id" ]]; then
    echo "No available Server Backup newer than ${SERVER_BACKUP_MAX_AGE_HOURS} hours found for the target VM." >&2
    exit 1
  fi
fi

ssh_options=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -i "$SSH_KEY"
)

read -r before_row_count before_fingerprint < <(
  ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
    "cd /tmp && sudo -u postgres psql --tuples-only --no-align --field-separator=' ' --dbname=springmusic --command=\"SELECT count(*), md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\\\n' ORDER BY id)) FROM public.album;\""
)

export TF_VAR_postgresql_app_password
TF_VAR_postgresql_app_password=$(ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
  "sudo sed -n 's/^SPRING_DATASOURCE_PASSWORD=//p' /etc/springboot.env")
if ((${#TF_VAR_postgresql_app_password} < 16)); then
  echo "Could not recover the existing target PostgreSQL password." >&2
  exit 1
fi

terraform -chdir="$ROOT_DIR" plan \
  -input=false \
  -replace='terraform_data.run_ansible[0]' \
  -var-file=env.tfvars \
  -var="postgresql_source_dump_local_path=$TERRAFORM_DUMP_PATH" \
  -var=postgresql_restore_after_copy=true \
  -var="postgresql_expected_album_count=$expected_row_count" \
  -var="postgresql_expected_album_fingerprint=$expected_fingerprint" \
  -out="$PLAN_PATH"
chmod 0600 "$PLAN_PATH"

terraform -chdir="$ROOT_DIR" show -json "$PLAN_PATH" | jq \
  '{changes: [.resource_changes[] | select(.change.actions != ["no-op"]) | {address, type, actions: .change.actions}]}' \
  >"$EVIDENCE_DIR/plan-summary.json"

if ! jq -e '
  .changes | length == 1 and
  .[0].address == "terraform_data.run_ansible[0]" and
  (.[0].actions | sort) == ["create", "delete"]
' "$EVIDENCE_DIR/plan-summary.json" >/dev/null; then
  echo "Cutover plan must replace only terraform_data.run_ansible[0]." >&2
  exit 1
fi

terraform -chdir="$ROOT_DIR" apply -input=false "$PLAN_PATH"
rm -f "$PLAN_PATH"

"$ROOT_DIR/scripts/validate_migration.sh" "$ARTIFACT_DIR"
"$ROOT_DIR/scripts/validate_deployment.sh"

read -r after_row_count after_fingerprint < <(
  ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
    "cd /tmp && sudo -u postgres psql --tuples-only --no-align --field-separator=' ' --dbname=springmusic --command=\"SELECT count(*), md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\\\n' ORDER BY id)) FROM public.album;\""
)

terraform -chdir="$ROOT_DIR" plan \
  -input=false \
  -detailed-exitcode \
  -var-file=env.tfvars \
  -var="postgresql_source_dump_local_path=$TERRAFORM_DUMP_PATH" \
  -var=postgresql_restore_after_copy=true \
  -var="postgresql_expected_album_count=$expected_row_count" \
  -var="postgresql_expected_album_fingerprint=$expected_fingerprint" \
  -out="$PLAN_PATH"
terraform_noop=true

unset TF_VAR_postgresql_app_password
STATUS=passed
echo "Cutover passed. Evidence: $EVIDENCE_DIR"