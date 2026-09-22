#!/usr/bin/env bash
set -euo pipefail

FLAGS_FILE="${1:-flags.env}"
TFVARS_FILE="${2:-env.tfvars}"

if [[ ! -f "$FLAGS_FILE" ]]; then
  echo "Missing flags file: $FLAGS_FILE"
  echo "Copy flags.env.example to flags.env and adjust values."
  exit 1
fi

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Missing Terraform variables file: $TFVARS_FILE"
  echo "Copy env.tfvars.example to env.tfvars and adjust values."
  exit 1
fi

# shellcheck disable=SC1090
source "$FLAGS_FILE"

if [[ "${setup_dns:-false}" == "true" ]]; then
  echo "setup_dns=true is not supported by this example yet."
  exit 1
fi

if [[ "${setup_loadgen:-false}" == "true" && "${setup_workload:-false}" != "true" ]]; then
  echo "setup_loadgen=true requires setup_workload=true."
  exit 1
fi

terraform init
terraform apply -var-file="$TFVARS_FILE" \
  -var "create_project=${setup_project:-false}" \
  -var "enable_observability=${setup_observability:-false}" \
  -var "enable_local_postgresql=${setup_database:-false}" \
  -var "run_ansible=${setup_workload:-false}" \
  -var "enable_local_load_generator=${setup_loadgen:-false}"
