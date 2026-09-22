#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
SSH_USER=${SSH_USER:-ubuntu}
EXPECTED_ROW_COUNT=${EXPECTED_ROW_COUNT:-}
EXPECTED_FINGERPRINT=${EXPECTED_FINGERPRINT:-}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
TEST_DATABASE="springmusic_rollback_verify_${RUN_ID//[^0-9]/}"
VM_IP=$(terraform -chdir="$ROOT_DIR" output -raw vm_public_ip)

ssh_options=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -i "$SSH_KEY"
)

read -r actual_row_count actual_fingerprint < <(ssh "${ssh_options[@]}" "$SSH_USER@$VM_IP" bash -s -- \
  "$TEST_DATABASE" "${EXPECTED_ROW_COUNT:--}" "${EXPECTED_FINGERPRINT:--}" <<'EOF'
set -euo pipefail

test_database=$1
expected_row_count_override=$2
expected_fingerprint_override=$3
[[ "$expected_row_count_override" == - ]] && expected_row_count_override=
[[ "$expected_fingerprint_override" == - ]] && expected_fingerprint_override=
rollback_dump=/var/backups/springmusic/pre-restore.dump
rollback_evidence=${rollback_dump}.env

cleanup() {
  sudo -u postgres dropdb --if-exists "$test_database" >/dev/null
}
trap cleanup EXIT

test "$(sudo stat -c %a "$rollback_dump")" = 600
test "$(sudo stat -c %a "$rollback_evidence")" = 600
expected_row_count=${expected_row_count_override:-$(sudo sed -n 's/^row_count=//p' "$rollback_evidence")}
expected_fingerprint=${expected_fingerprint_override:-$(sudo sed -n 's/^album_fingerprint=//p' "$rollback_evidence")}
test -n "$expected_row_count"
test -n "$expected_fingerprint"
sudo -u postgres createdb "$test_database"
sudo -u postgres pg_restore \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  --dbname="$test_database" \
  "$rollback_dump"
actual_row_count=$(sudo -u postgres psql \
  --tuples-only \
  --no-align \
  --dbname="$test_database" \
  --command='SELECT count(*) FROM public.album;')
if [[ "$actual_row_count" != "$expected_row_count" ]]; then
  echo "Rollback row count mismatch: expected $expected_row_count, got $actual_row_count" >&2
  exit 1
fi
actual_fingerprint=$(sudo -u postgres psql \
  --tuples-only \
  --no-align \
  --dbname="$test_database" \
  --command="SELECT md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\n' ORDER BY id)) FROM public.album;")
if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Rollback fingerprint mismatch." >&2
  exit 1
fi
printf '%s %s\n' "$actual_row_count" "$actual_fingerprint"
EOF
)

echo "Rollback verification passed: $actual_row_count rows and fingerprint $actual_fingerprint restored in an isolated database."