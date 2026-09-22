#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR=${1:-"$ROOT_DIR/artifacts"}
DUMP_PATH="$ARTIFACT_DIR/source-postgresql.dump"
MANIFEST_PATH="$ARTIFACT_DIR/source-postgresql.manifest"
CHECKSUM_PATH="$ARTIFACT_DIR/source-postgresql.dump.sha256"
DATABASE_NAME=springmusic_restore_test

for command in pg_config runuser sha256sum sed; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

for path in "$DUMP_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing source artifact: $path" >&2
    exit 1
  fi
done

POSTGRES_BINDIR=$(pg_config --bindir)
for binary in initdb pg_ctl createdb psql pg_restore; do
  if [[ ! -x "$POSTGRES_BINDIR/$binary" ]]; then
    echo "Missing required PostgreSQL binary: $POSTGRES_BINDIR/$binary" >&2
    exit 1
  fi
done

expected_row_count=$(sed -n 's/^row_count=//p' "$MANIFEST_PATH")
expected_fingerprint=$(sed -n 's/^album_fingerprint=//p' "$MANIFEST_PATH")
if [[ ! "$expected_row_count" =~ ^[0-9]+$ || ! "$expected_fingerprint" =~ ^[0-9a-f]{32}$ ]]; then
  echo "Manifest contains invalid row_count or album_fingerprint values." >&2
  exit 1
fi

(
  cd "$ARTIFACT_DIR"
  sha256sum --check "$(basename "$CHECKSUM_PATH")"
)

WORK_DIR=$(mktemp -d)
DATA_DIR="$WORK_DIR/data"
SOCKET_DIR="$WORK_DIR/socket"

cleanup() {
  if [[ -f "$DATA_DIR/postmaster.pid" ]]; then
    runuser -u postgres -- "$POSTGRES_BINDIR/pg_ctl" \
      --pgdata "$DATA_DIR" --mode fast --wait stop >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$DATA_DIR" "$SOCKET_DIR"
chown -R postgres:postgres "$WORK_DIR"

runuser -u postgres -- "$POSTGRES_BINDIR/initdb" \
  --pgdata "$DATA_DIR" \
  --auth=trust \
  --encoding=UTF8 \
  --no-locale >/dev/null

runuser -u postgres -- "$POSTGRES_BINDIR/pg_ctl" \
  --pgdata "$DATA_DIR" \
  --options="-k $SOCKET_DIR -h ''" \
  --wait start >/dev/null

runuser -u postgres -- "$POSTGRES_BINDIR/createdb" \
  --host "$SOCKET_DIR" \
  "$DATABASE_NAME"

runuser -u postgres -- "$POSTGRES_BINDIR/pg_restore" \
  --host "$SOCKET_DIR" \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  --dbname "$DATABASE_NAME" \
  "$DUMP_PATH"

actual_row_count=$(runuser -u postgres -- "$POSTGRES_BINDIR/psql" \
  --host "$SOCKET_DIR" \
  --dbname "$DATABASE_NAME" \
  --tuples-only \
  --no-align \
  --command='SELECT count(*) FROM public.album;')

actual_fingerprint=$(runuser -u postgres -- "$POSTGRES_BINDIR/psql" \
  --host "$SOCKET_DIR" \
  --dbname "$DATABASE_NAME" \
  --tuples-only \
  --no-align \
  --command="SELECT md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\n' ORDER BY id)) FROM public.album;")

if [[ "$actual_row_count" != "$expected_row_count" ]]; then
  echo "Row count mismatch: expected $expected_row_count, got $actual_row_count" >&2
  exit 1
fi

if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Album fingerprint mismatch: expected $expected_fingerprint, got $actual_fingerprint" >&2
  exit 1
fi

echo "Source dump validation passed: $actual_row_count rows, fingerprint $actual_fingerprint."