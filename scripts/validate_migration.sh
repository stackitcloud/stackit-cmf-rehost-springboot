#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR=${1:-"$ROOT_DIR/artifacts"}
MANIFEST_PATH="$ARTIFACT_DIR/source-postgresql.manifest"
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa"}
SSH_USER=${SSH_USER:-ubuntu}

for command in terraform ssh sed; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "Missing source manifest: $MANIFEST_PATH" >&2
  exit 1
fi

expected_row_count=$(sed -n 's/^row_count=//p' "$MANIFEST_PATH")
expected_fingerprint=$(sed -n 's/^album_fingerprint=//p' "$MANIFEST_PATH")
if [[ ! "$expected_row_count" =~ ^[0-9]+$ || ! "$expected_fingerprint" =~ ^[0-9a-f]{32}$ ]]; then
  echo "Manifest contains invalid row_count or album_fingerprint values." >&2
  exit 1
fi

vm_ip=$(terraform -chdir="$ROOT_DIR" output -raw vm_public_ip)
ssh_options=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -i "$SSH_KEY"
)

read -r actual_row_count actual_fingerprint table_owner < <(
  ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
    "cd /tmp && sudo -u postgres psql --tuples-only --no-align --field-separator=' ' --dbname=springmusic --command=\"SELECT count(*), md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\\\n' ORDER BY id)), pg_get_userbyid(c.relowner) FROM public.album CROSS JOIN pg_class c WHERE c.oid='public.album'::regclass GROUP BY c.relowner;\""
)

if [[ "$actual_row_count" != "$expected_row_count" ]]; then
  echo "Target row count mismatch: expected $expected_row_count, got $actual_row_count" >&2
  exit 1
fi

if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Target fingerprint mismatch: expected $expected_fingerprint, got $actual_fingerprint" >&2
  exit 1
fi

if [[ "$table_owner" != "springmusic" ]]; then
  echo "Unexpected public.album owner: $table_owner" >&2
  exit 1
fi

ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
  "cd /tmp && sudo -u postgres psql --dbname=springmusic --set ON_ERROR_STOP=1 --command=\"BEGIN; SET ROLE springmusic; INSERT INTO public.album (id, track_count, title) VALUES ('write-check', 1, 'transactional validation'); ROLLBACK;\"" >/dev/null

rollback_details=$(ssh "${ssh_options[@]}" "$SSH_USER@$vm_ip" \
  "sudo stat -c '%a %U:%G %s' -- /var/backups/springmusic/pre-restore.dump")
read -r rollback_mode rollback_owner rollback_size <<<"$rollback_details"

if [[ "$rollback_mode" != "600" || "$rollback_owner" != "postgres:postgres" || "$rollback_size" -le 0 ]]; then
  echo "Rollback dump is not protected or is empty: $rollback_details" >&2
  exit 1
fi

echo "Migration validation passed: $actual_row_count rows, fingerprint $actual_fingerprint, owner $table_owner."
echo "Rollback dump is present with mode $rollback_mode and size $rollback_size bytes."