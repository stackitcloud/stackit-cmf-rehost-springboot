#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR=${1:-"$ROOT_DIR/artifacts"}
MANIFEST_PATH="$ARTIFACT_DIR/source-postgresql.manifest"
DUMP_PATH="$ARTIFACT_DIR/source-postgresql.dump"
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
SSH_USER=${SSH_USER:-ubuntu}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE_DIR="$ROOT_DIR/artifacts/evidence/${RUN_ID}-rehearsal"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS=failed

mkdir -p "$EVIDENCE_DIR"
chmod 0700 "$EVIDENCE_DIR"

write_evidence() {
  cat >"$EVIDENCE_DIR/evidence.env" <<EOF
mode=rehearsal
run_id=$RUN_ID
started_at=$STARTED_AT
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=$STATUS
source_dump_sha256=${dump_checksum:-unknown}
expected_row_count=${expected_row_count:-unknown}
expected_album_fingerprint=${expected_fingerprint:-unknown}
target_vm_ip=${vm_ip:-unknown}
rehearsal_database=${rehearsal_database:-unknown}
EOF
}
trap write_evidence EXIT

for command in terraform ssh scp sed sha256sum; do
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
rehearsal_database="springmusic_rehearsal_${RUN_ID//[^0-9]/}"
remote_dump="/tmp/${rehearsal_database}.dump"

ssh_options=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -i "$SSH_KEY"
)

scp "${ssh_options[@]}" "$DUMP_PATH" "$SSH_USER@$vm_ip:$remote_dump"

ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" bash -s -- \
  "$remote_dump" "$rehearsal_database" "$expected_row_count" "$expected_fingerprint" <<'EOF'
set -euo pipefail

remote_dump=$1
rehearsal_database=$2
expected_row_count=$3
expected_fingerprint=$4

cleanup() {
  sudo -u postgres dropdb --if-exists "$rehearsal_database" >/dev/null
  sudo rm -f "$remote_dump"
}
trap cleanup EXIT

sudo chown postgres:postgres "$remote_dump"
sudo chmod 0600 "$remote_dump"
sudo -u postgres createdb --owner=springmusic "$rehearsal_database"
sudo -u postgres pg_restore \
  --no-owner \
  --no-privileges \
  --role=springmusic \
  --exit-on-error \
  --dbname="$rehearsal_database" \
  "$remote_dump"

actual=$(sudo -u postgres psql \
  --tuples-only \
  --no-align \
  --field-separator=' ' \
  --dbname="$rehearsal_database" \
  --command="SELECT count(*), md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\n' ORDER BY id)) FROM public.album;")
read -r actual_row_count actual_fingerprint <<<"$actual"

if [[ "$actual_row_count" != "$expected_row_count" ]]; then
  echo "Rehearsal row count mismatch: expected $expected_row_count, got $actual_row_count" >&2
  exit 1
fi

if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Rehearsal fingerprint mismatch: expected $expected_fingerprint, got $actual_fingerprint" >&2
  exit 1
fi
EOF

STATUS=passed
echo "Migration rehearsal passed. Evidence: $EVIDENCE_DIR/evidence.env"