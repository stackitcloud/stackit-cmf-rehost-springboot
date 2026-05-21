#!/usr/bin/env bash
set -euo pipefail

FLAGS_FILE="${1:-flags.env}"
TFVARS_FILE="${2:-env.tfvars}"

if [[ ! -f "$FLAGS_FILE" ]]; then
  echo "Missing flags file: $FLAGS_FILE"
  echo "Copy flags.env.example to flags.env and adjust values."
  exit 1
fi

# shellcheck disable=SC1090
source "$FLAGS_FILE"

terraform init
terraform apply -var-file="$TFVARS_FILE" \
  -var "create_project=${setup_project:-false}" \
  -var "enable_observability=${setup_observability:-false}" \
  -var "enable_local_postgresql=${setup_database:-false}" \
  -var "springboot_loadgen_enable_stress=${setup_loadgen:-false}"
