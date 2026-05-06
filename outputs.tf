output "effective_project_id" {
  value = local.effective_project_id
}

output "created_project_id" {
  value = var.create_project ? stackit_resourcemanager_project.cmf_project[0].project_id : null
}

output "selected_image_id" {
  value = local.selected_image_id
}

output "selected_machine_type" {
  value = local.selected_machine_type
}

output "vm_public_ip" {
  value = stackit_public_ip.rehost_public_ip.ip
}

output "application_url" {
  value = "http://${stackit_public_ip.rehost_public_ip.ip}"
}
