locals {
  sa_key = jsondecode(file(pathexpand(var.service_account_key_path)))

  bootstrap_project_id = var.bootstrap_project_id != "" ? var.bootstrap_project_id : local.sa_key.projectId
  project_owner_email  = var.target_project_owner_email != "" ? var.target_project_owner_email : local.sa_key.credentials.iss
  use_bootstrap_lookup = var.create_project && var.parent_container_id == ""
}

data "stackit_resourcemanager_project" "bootstrap" {
  count = local.use_bootstrap_lookup ? 1 : 0

  project_id = local.bootstrap_project_id
}

resource "stackit_resourcemanager_project" "cmf_project" {
  count = var.create_project ? 1 : 0

  name                = var.target_project_name
  owner_email         = local.project_owner_email
  parent_container_id = var.parent_container_id != "" ? var.parent_container_id : data.stackit_resourcemanager_project.bootstrap[0].parent_container_id
}

locals {
  effective_project_id = var.create_project ? stackit_resourcemanager_project.cmf_project[0].project_id : (var.project_id != "" ? var.project_id : local.bootstrap_project_id)
}

data "stackit_image_v2" "ubuntu" {
  count = var.auto_discover_compute_defaults && var.image_id == "" ? 1 : 0

  project_id = local.effective_project_id
  region     = var.region
  name_regex = "(?i)ubuntu.*22\\.04"
}

data "stackit_machine_type" "default" {
  count = var.auto_discover_compute_defaults && var.machine_type == "" ? 1 : 0

  project_id     = local.effective_project_id
  region         = var.region
  filter         = "vcpus == 2 && ram >= 4096"
  sort_ascending = true
}

locals {
  selected_image_id     = var.image_id != "" ? var.image_id : (var.auto_discover_compute_defaults ? data.stackit_image_v2.ubuntu[0].image_id : "")
  selected_machine_type = var.machine_type != "" ? var.machine_type : (var.auto_discover_compute_defaults ? data.stackit_machine_type.default[0].name : "")
}

resource "stackit_security_group" "rehost_sg" {
  project_id = local.effective_project_id
  name       = "rehost-springboot-sg"
}

resource "stackit_security_group_rule" "ssh" {
  project_id        = local.effective_project_id
  security_group_id = stackit_security_group.rehost_sg.security_group_id
  direction         = "ingress"
  protocol = {
    name = "tcp"
  }
  port_range = {
    min = 22
    max = 22
  }
}

resource "stackit_security_group_rule" "http" {
  project_id        = local.effective_project_id
  security_group_id = stackit_security_group.rehost_sg.security_group_id
  direction         = "ingress"
  protocol = {
    name = "tcp"
  }
  port_range = {
    min = 80
    max = 80
  }
}

resource "stackit_security_group_rule" "node_exporter" {
  count = var.enable_observability && var.enable_node_exporter && var.expose_node_exporter_port ? 1 : 0

  project_id        = local.effective_project_id
  security_group_id = stackit_security_group.rehost_sg.security_group_id
  direction         = "ingress"
  protocol = {
    name = "tcp"
  }
  port_range = {
    min = var.node_exporter_port
    max = var.node_exporter_port
  }
}

resource "stackit_network" "rehost_net" {
  project_id         = local.effective_project_id
  name               = "rehost-net"
  ipv4_prefix_length = 24
}

resource "stackit_network_interface" "rehost_nic" {
  project_id         = local.effective_project_id
  network_id         = stackit_network.rehost_net.network_id
  security_group_ids = [stackit_security_group.rehost_sg.security_group_id]
}

resource "stackit_public_ip" "rehost_public_ip" {
  project_id           = local.effective_project_id
  network_interface_id = stackit_network_interface.rehost_nic.network_interface_id
}

resource "stackit_key_pair" "rehost_key" {
  name       = "rehost-key"
  public_key = chomp(file(var.public_ssh_key_path))
}

resource "stackit_volume" "rehost_boot" {
  project_id        = local.effective_project_id
  name              = "rehost-boot"
  availability_zone = var.availability_zone
  size              = 60
  performance_class = "storage_premium_perf6"

  source = {
    id   = local.selected_image_id
    type = "image"
  }
}

resource "stackit_server" "rehost_vm" {
  project_id = local.effective_project_id
  name       = var.server_name

  network_interfaces = [stackit_network_interface.rehost_nic.network_interface_id]

  boot_volume = {
    source_type = "volume"
    source_id   = stackit_volume.rehost_boot.volume_id
  }

  availability_zone = var.availability_zone
  machine_type      = local.selected_machine_type
  keypair_name      = stackit_key_pair.rehost_key.name
}

resource "stackit_observability_instance" "rehost_obs" {
  count = var.enable_observability ? 1 : 0

  project_id = local.effective_project_id
  name       = var.observability_instance_name
  plan_name  = var.observability_plan_name
}

resource "stackit_observability_scrapeconfig" "node_exporter" {
  count = var.enable_observability && var.enable_node_exporter ? 1 : 0

  project_id   = local.effective_project_id
  instance_id  = stackit_observability_instance.rehost_obs[0].instance_id
  name         = "${var.server_name}-node-exporter"
  metrics_path = "/metrics"
  targets = [{
    urls = ["${stackit_public_ip.rehost_public_ip.ip}:${var.node_exporter_port}"]
  }]
  scheme          = "http"
  scrape_interval = var.observability_scrape_interval
  scrape_timeout  = var.observability_scrape_timeout
}

resource "stackit_observability_scrapeconfig" "springboot_app" {
  count = var.enable_observability && var.enable_springboot_metrics_scrape ? 1 : 0

  project_id   = local.effective_project_id
  instance_id  = stackit_observability_instance.rehost_obs[0].instance_id
  name         = "${var.server_name}-springboot"
  metrics_path = var.springboot_metrics_path
  targets = [{
    urls = ["${stackit_public_ip.rehost_public_ip.ip}:${var.springboot_metrics_port}"]
  }]
  scheme          = "http"
  scrape_interval = var.observability_scrape_interval
  scrape_timeout  = var.observability_scrape_timeout
}

resource "terraform_data" "ansible_inventory" {
  depends_on = [stackit_server.rehost_vm]

  triggers_replace = [
    stackit_public_ip.rehost_public_ip.ip,
    var.ssh_user,
    pathexpand(var.private_ssh_key_path),
    abspath(var.jar_local_path),
    tostring(var.enable_observability),
    tostring(var.enable_node_exporter),
    tostring(var.node_exporter_port),
    tostring(var.springboot_app_port),
    tostring(var.enable_local_load_generator),
    var.springboot_loadgen_target_path,
    tostring(var.springboot_loadgen_base_interval_seconds),
    tostring(var.springboot_loadgen_randomized_delay_seconds),
    tostring(var.springboot_loadgen_burst_min_requests),
    tostring(var.springboot_loadgen_burst_max_requests),
    tostring(var.springboot_loadgen_enable_stress),
    tostring(var.springboot_loadgen_stress_cpu_workers),
    tostring(var.springboot_loadgen_stress_vm_workers),
    var.springboot_loadgen_stress_vm_bytes,
    tostring(var.springboot_loadgen_stress_timeout_seconds),
    tostring(var.enable_local_postgresql),
    tostring(var.postgresql_vm_listen_port),
    var.postgresql_db_name,
    var.postgresql_app_username,
    var.postgresql_app_password,
    var.postgresql_source_dump_local_path,
    var.postgresql_vm_dump_path,
    tostring(var.postgresql_restore_after_copy),
    can(filesha256(var.postgresql_source_dump_local_path)) ? filesha256(var.postgresql_source_dump_local_path) : ""
  ]

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/ansible/inventory.ini <<'EOF'
      [rehost]
      ${stackit_public_ip.rehost_public_ip.ip} ansible_user=${var.ssh_user} ansible_ssh_private_key_file=${pathexpand(var.private_ssh_key_path)} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' jar_local_path=${abspath(var.jar_local_path)} enable_node_exporter=${var.enable_observability && var.enable_node_exporter} node_exporter_port=${var.node_exporter_port} springboot_app_port=${var.springboot_app_port} enable_local_load_generator=${var.enable_local_load_generator} springboot_loadgen_target_path=${var.springboot_loadgen_target_path} springboot_loadgen_base_interval_seconds=${var.springboot_loadgen_base_interval_seconds} springboot_loadgen_randomized_delay_seconds=${var.springboot_loadgen_randomized_delay_seconds} springboot_loadgen_burst_min_requests=${var.springboot_loadgen_burst_min_requests} springboot_loadgen_burst_max_requests=${var.springboot_loadgen_burst_max_requests} springboot_loadgen_enable_stress=${var.springboot_loadgen_enable_stress} springboot_loadgen_stress_cpu_workers=${var.springboot_loadgen_stress_cpu_workers} springboot_loadgen_stress_vm_workers=${var.springboot_loadgen_stress_vm_workers} springboot_loadgen_stress_vm_bytes=${var.springboot_loadgen_stress_vm_bytes} springboot_loadgen_stress_timeout_seconds=${var.springboot_loadgen_stress_timeout_seconds} enable_local_postgresql=${var.enable_local_postgresql} postgresql_vm_listen_port=${var.postgresql_vm_listen_port} postgresql_db_name=${var.postgresql_db_name} postgresql_app_username=${var.postgresql_app_username} postgresql_app_password='${var.postgresql_app_password}' postgresql_source_dump_local_path=${var.postgresql_source_dump_local_path != "" && var.postgresql_source_dump_local_path != "." ? abspath(var.postgresql_source_dump_local_path) : ""} postgresql_vm_dump_path=${var.postgresql_vm_dump_path} postgresql_restore_after_copy=${var.postgresql_restore_after_copy}
      EOF
    EOT
  }
}

resource "terraform_data" "run_ansible" {
  count = var.run_ansible ? 1 : 0

  depends_on = [
    stackit_server.rehost_vm,
    terraform_data.ansible_inventory
  ]

  triggers_replace = [
    stackit_server.rehost_vm.server_id,
    stackit_public_ip.rehost_public_ip.ip,
    filesha256(var.jar_local_path),
    tostring(var.enable_observability),
    tostring(var.enable_node_exporter),
    tostring(var.node_exporter_port),
    tostring(var.springboot_app_port),
    tostring(var.enable_local_load_generator),
    var.springboot_loadgen_target_path,
    tostring(var.springboot_loadgen_base_interval_seconds),
    tostring(var.springboot_loadgen_randomized_delay_seconds),
    tostring(var.springboot_loadgen_burst_min_requests),
    tostring(var.springboot_loadgen_burst_max_requests),
    tostring(var.springboot_loadgen_enable_stress),
    tostring(var.springboot_loadgen_stress_cpu_workers),
    tostring(var.springboot_loadgen_stress_vm_workers),
    var.springboot_loadgen_stress_vm_bytes,
    tostring(var.springboot_loadgen_stress_timeout_seconds),
    tostring(var.enable_local_postgresql),
    tostring(var.postgresql_vm_listen_port),
    var.postgresql_db_name,
    var.postgresql_app_username,
    var.postgresql_app_password,
    var.postgresql_source_dump_local_path,
    var.postgresql_vm_dump_path,
    tostring(var.postgresql_restore_after_copy),
    can(filesha256(var.postgresql_source_dump_local_path)) ? filesha256(var.postgresql_source_dump_local_path) : ""
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "LANG=C.UTF-8 LC_ALL=C.UTF-8 ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml"
  }
}

resource "terraform_data" "grafana_dashboard" {
  count = var.enable_observability && var.create_grafana_dashboard ? 1 : 0

  depends_on = [
    stackit_observability_instance.rehost_obs,
    stackit_observability_scrapeconfig.node_exporter,
    stackit_observability_scrapeconfig.springboot_app
  ]

  triggers_replace = [
    stackit_observability_instance.rehost_obs[0].instance_id,
    stackit_observability_instance.rehost_obs[0].grafana_url,
    stackit_observability_instance.rehost_obs[0].grafana_initial_admin_user,
    stackit_observability_instance.rehost_obs[0].grafana_initial_admin_password,
    filesha256("${path.module}/dashboards/rehost-observability-dashboard.json")
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      GRAFANA_URL    = stackit_observability_instance.rehost_obs[0].grafana_url
      GRAFANA_USER   = stackit_observability_instance.rehost_obs[0].grafana_initial_admin_user
      GRAFANA_PASS   = stackit_observability_instance.rehost_obs[0].grafana_initial_admin_password
      DASHBOARD_FILE = "${path.module}/dashboards/rehost-observability-dashboard.json"
    }
    command = <<-EOT
      set -euo pipefail

        # Avoid SIGPIPE from jq|head under pipefail when multiple datasources exist.
        PROM_UID=$(curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources" | jq -r 'map(select(.type == "prometheus"))[0].uid // empty')

      if [ -z "$PROM_UID" ]; then
        echo "No Prometheus datasource uid found in Grafana; skipping dashboard import."
        exit 0
      fi

      DASHBOARD_JSON=$(sed "s/__PROM_UID__/$PROM_UID/g" "$DASHBOARD_FILE")
      PAYLOAD_FILE=$(mktemp)
      trap 'rm -f "$PAYLOAD_FILE"' EXIT
      printf '{"dashboard":%s,"overwrite":true}' "$DASHBOARD_JSON" > "$PAYLOAD_FILE"

      curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" \
        -H "Content-Type: application/json" \
        -X POST \
        "$GRAFANA_URL/api/dashboards/db" \
        --data-binary @"$PAYLOAD_FILE" >/dev/null

      echo "Grafana dashboard imported successfully."
    EOT
  }
}
