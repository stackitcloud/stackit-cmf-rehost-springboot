#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
SSH_USER=${SSH_USER:-ubuntu}
EXPECTED_ROW_COUNT=${EXPECTED_ROW_COUNT:-}
EXPECTED_FINGERPRINT=${EXPECTED_FINGERPRINT:-}
CONFIRMED=false

if [[ ${1:-} == "--confirm" ]]; then
  CONFIRMED=true
fi

if [[ "$CONFIRMED" != true ]]; then
  echo "Rollback replaces the target database. Re-run with --confirm after approval." >&2
  exit 1
fi

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE_DIR="$ROOT_DIR/artifacts/evidence/${RUN_ID}-rollback"
VM_IP=$(terraform -chdir="$ROOT_DIR" output -raw vm_public_ip)
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS=failed

mkdir -p "$EVIDENCE_DIR"
chmod 0700 "$EVIDENCE_DIR"

write_evidence() {
  cat >"$EVIDENCE_DIR/evidence.env" <<EOF
mode=rollback
run_id=$RUN_ID
started_at=$STARTED_AT
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=$STATUS
target_vm_ip=$VM_IP
expected_row_count=${expected_row_count:-unknown}
expected_album_fingerprint=${expected_fingerprint:-unknown}
actual_row_count=${actual_row_count:-unknown}
actual_album_fingerprint=${actual_fingerprint:-unknown}
pre_rollback_dump=${pre_rollback_dump:-unknown}
EOF
}
trap write_evidence EXIT

ssh_options=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -i "$SSH_KEY"
)

read -r actual_row_count actual_fingerprint pre_rollback_dump expected_row_count expected_fingerprint < <(
  ssh "${ssh_options[@]}" "$SSH_USER@$VM_IP" bash -s -- \
    "$RUN_ID" "${EXPECTED_ROW_COUNT:--}" "${EXPECTED_FINGERPRINT:--}" <<'EOF'
set -euo pipefail

run_id=$1
expected_row_count_override=$2
expected_fingerprint_override=$3
[[ "$expected_row_count_override" == - ]] && expected_row_count_override=
[[ "$expected_fingerprint_override" == - ]] && expected_fingerprint_override=
rollback_dump=/var/backups/springmusic/pre-restore.dump
rollback_evidence=${rollback_dump}.env
pre_rollback_dump="/var/backups/springmusic/pre-rollback-${run_id}.dump"

test "$(sudo stat -c %a "$rollback_dump")" = 600
test "$(sudo stat -c %a "$rollback_evidence")" = 600
expected_row_count=${expected_row_count_override:-$(sudo sed -n 's/^row_count=//p' "$rollback_evidence")}
expected_fingerprint=${expected_fingerprint_override:-$(sudo sed -n 's/^album_fingerprint=//p' "$rollback_evidence")}
test -n "$expected_row_count"
test -n "$expected_fingerprint"
sudo systemctl stop springboot
sudo -u postgres pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --dbname=springmusic \
  --file="$pre_rollback_dump"
sudo chmod 0600 "$pre_rollback_dump"
sudo -u postgres pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --role=springmusic \
  --single-transaction \
  --dbname=springmusic \
  "$rollback_dump"

actual_row_count=$(sudo -u postgres psql \
  --tuples-only \
  --no-align \
  --dbname=springmusic \
  --command='SELECT count(*) FROM public.album;')
if [[ "$actual_row_count" != "$expected_row_count" ]]; then
  echo "Rollback row count mismatch: expected $expected_row_count, got $actual_row_count" >&2
  exit 1
fi
actual_fingerprint=$(sudo -u postgres psql \
  --tuples-only \
  --no-align \
  --dbname=springmusic \
  --command="SELECT md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\n' ORDER BY id)) FROM public.album;")
if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Rollback fingerprint mismatch." >&2
  exit 1
fi

sudo systemctl start springboot
printf '%s %s %s %s %s\n' "$actual_row_count" "$actual_fingerprint" "$pre_rollback_dump" "$expected_row_count" "$expected_fingerprint"
EOF
)

"$ROOT_DIR/scripts/validate_deployment.sh"
STATUS=passed
echo "Rollback passed. Evidence: $EVIDENCE_DIR/evidence.env"