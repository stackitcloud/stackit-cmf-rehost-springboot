#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SSH_USER=${SSH_USER:-ubuntu}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/id_rsa}
terraform_outputs=$(terraform -chdir="$ROOT_DIR" output -json)
VM_IP=$(jq -r '.vm_public_ip.value' <<<"$terraform_outputs")
APPLICATION_URL=$(jq -r '.application_url.value' <<<"$terraform_outputs")
APPLICATION_PORT=${APPLICATION_URL##*:}
POSTGRESQL_ENABLED=$(jq -r '.local_postgresql_enabled.value' <<<"$terraform_outputs")
POSTGRESQL_DATABASE=$(jq -r '.postgresql_database_name.value' <<<"$terraform_outputs")
NODE_EXPORTER_ENABLED=$(jq -r '.node_exporter_enabled.value' <<<"$terraform_outputs")
NODE_EXPORTER_PORT=$(jq -r '.node_exporter_port.value' <<<"$terraform_outputs")

curl --fail --silent --show-error \
  --output /dev/null \
  --retry 12 \
  --retry-delay 5 \
  --retry-all-errors \
  --max-time 15 \
  "${APPLICATION_URL}/"

ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  -i "$SSH_KEY" \
  "${SSH_USER}@${VM_IP}" \
  bash -s -- "$APPLICATION_PORT" "$POSTGRESQL_ENABLED" "$POSTGRESQL_DATABASE" "$NODE_EXPORTER_ENABLED" "$NODE_EXPORTER_PORT" <<'EOF'
set -euo pipefail
cd /tmp

application_port=$1
postgresql_enabled=$2
postgresql_database=$3
node_exporter_enabled=$4
node_exporter_port=$5
services=(springboot)

if [[ "$postgresql_enabled" == true ]]; then
  services+=(postgresql)
fi
if [[ "$node_exporter_enabled" == true ]]; then
  services+=(prometheus-node-exporter)
fi

systemctl is-active "${services[@]}" >/dev/null
systemctl is-enabled "${services[@]}" >/dev/null
curl --fail --silent --show-error --output /dev/null --retry 12 --retry-delay 5 --retry-all-errors "http://127.0.0.1:${application_port}/"

if [[ "$postgresql_enabled" == true ]]; then
  sudo -u postgres psql -d "$postgresql_database" -tAc "SELECT 1" | grep -qx 1
  test "$(sudo stat -c %a /etc/springboot.env)" = 600
fi
if [[ "$node_exporter_enabled" == true ]]; then
  metric_ready=false
  for _ in {1..12}; do
    metrics=$(curl --fail --silent --show-error "http://127.0.0.1:${node_exporter_port}/metrics")
    if grep -q "^springboot_up 1$" <<<"$metrics"; then
      metric_ready=true
      break
    fi
    sleep 5
  done
  [[ "$metric_ready" == true ]]
fi
EOF

echo "Deployment validation passed for ${VM_IP}."