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

resource "terraform_data" "ansible_inventory" {
  depends_on = [stackit_server.rehost_vm]

  triggers_replace = [
    stackit_public_ip.rehost_public_ip.ip,
    var.ssh_user,
    pathexpand(var.private_ssh_key_path),
    abspath(var.jar_local_path)
  ]

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/ansible/inventory.ini <<'EOF'
      [rehost]
      ${stackit_public_ip.rehost_public_ip.ip} ansible_user=${var.ssh_user} ansible_ssh_private_key_file=${pathexpand(var.private_ssh_key_path)} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' jar_local_path=${abspath(var.jar_local_path)}
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
    filesha256(var.jar_local_path)
  ]

  provisioner "local-exec" {
    command = "LANG=C.UTF-8 LC_ALL=C.UTF-8 ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml"
  }
}
