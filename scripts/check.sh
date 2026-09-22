#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for command in terraform ansible-playbook shellcheck; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

terraform -chdir="$ROOT_DIR" fmt -check -diff
terraform -chdir="$ROOT_DIR" init -backend=false -lockfile=readonly
terraform -chdir="$ROOT_DIR" validate
shellcheck "$ROOT_DIR"/scripts/*.sh
LANG=C.UTF-8 LC_ALL=C.UTF-8 ansible-playbook \
  --inventory 'rehost,' \
  --syntax-check \
  "$ROOT_DIR/ansible/playbook.yml"