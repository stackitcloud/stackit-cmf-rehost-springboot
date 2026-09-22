#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_SQL="$ROOT_DIR/migration/source/springmusic.sql"
OUTPUT_DIR=${1:-"$ROOT_DIR/artifacts"}
DATABASE_NAME=springmusic

for command in pg_config runuser sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

POSTGRES_BINDIR=$(pg_config --bindir)
for binary in initdb pg_ctl createdb psql pg_dump pg_restore; do
  if [[ ! -x "$POSTGRES_BINDIR/$binary" ]]; then
    echo "Missing required PostgreSQL binary: $POSTGRES_BINDIR/$binary" >&2
    exit 1
  fi
done

if [[ ! -f "$SOURCE_SQL" ]]; then
  echo "Source SQL does not exist: $SOURCE_SQL" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
DATA_DIR="$WORK_DIR/data"
SOCKET_DIR="$WORK_DIR/socket"
DUMP_TMP="$WORK_DIR/source-postgresql.dump"

cleanup() {
  if [[ -f "$DATA_DIR/postmaster.pid" ]]; then
    runuser -u postgres -- "$POSTGRES_BINDIR/pg_ctl" \
      --pgdata "$DATA_DIR" --mode fast --wait stop >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$DATA_DIR" "$SOCKET_DIR" "$OUTPUT_DIR"
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

runuser -u postgres -- "$POSTGRES_BINDIR/psql" \
  --host "$SOCKET_DIR" \
  --dbname "$DATABASE_NAME" \
  --set ON_ERROR_STOP=1 \
  --file "$SOURCE_SQL" >/dev/null

row_count=$(runuser -u postgres -- "$POSTGRES_BINDIR/psql" \
  --host "$SOCKET_DIR" \
  --dbname "$DATABASE_NAME" \
  --tuples-only \
  --no-align \
  --command='SELECT count(*) FROM public.album;')

album_fingerprint=$(runuser -u postgres -- "$POSTGRES_BINDIR/psql" \
  --host "$SOCKET_DIR" \
  --dbname "$DATABASE_NAME" \
  --tuples-only \
  --no-align \
  --command="SELECT md5(string_agg(concat_ws('|', id, album_id, artist, genre, release_year, title, track_count), E'\\n' ORDER BY id)) FROM public.album;")

runuser -u postgres -- "$POSTGRES_BINDIR/pg_dump" \
  --host "$SOCKET_DIR" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --dbname "$DATABASE_NAME" \
  --file "$DUMP_TMP"

"$POSTGRES_BINDIR/pg_restore" --list "$DUMP_TMP" >/dev/null

DUMP_PATH="$OUTPUT_DIR/source-postgresql.dump"
MANIFEST_PATH="$OUTPUT_DIR/source-postgresql.manifest"
CHECKSUM_PATH="$OUTPUT_DIR/source-postgresql.dump.sha256"

install -m 0600 "$DUMP_TMP" "$DUMP_PATH"
dump_checksum=$(sha256sum "$DUMP_PATH")
dump_checksum=${dump_checksum%% *}
source_checksum=$(sha256sum "$SOURCE_SQL")
source_checksum=${source_checksum%% *}

printf '%s  %s\n' "$dump_checksum" "$(basename "$DUMP_PATH")" >"$CHECKSUM_PATH"
cat >"$MANIFEST_PATH" <<EOF
format_version=1
database=$DATABASE_NAME
table=public.album
row_count=$row_count
album_fingerprint=$album_fingerprint
dump_sha256=$dump_checksum
source_sql_sha256=$source_checksum
postgres_version=$("$POSTGRES_BINDIR/postgres" --version)
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Created $DUMP_PATH"
echo "Created $MANIFEST_PATH"
echo "Created $CHECKSUM_PATH"