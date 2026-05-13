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

output "postgresql_jdbc_url" {
  value = var.enable_local_postgresql ? "jdbc:postgresql://${stackit_public_ip.rehost_public_ip.ip}:${var.postgresql_vm_listen_port}/${var.postgresql_db_name}" : null
}

output "postgresql_dump_source_path" {
  value = var.enable_local_postgresql && var.postgresql_source_dump_local_path != "" ? var.postgresql_source_dump_local_path : null
}

output "observability_instance_id" {
  value = var.enable_observability ? stackit_observability_instance.rehost_obs[0].instance_id : null
}

output "observability_grafana_url" {
  value = var.enable_observability ? stackit_observability_instance.rehost_obs[0].grafana_url : null
}

output "observability_dashboard_url" {
  value = var.enable_observability ? stackit_observability_instance.rehost_obs[0].dashboard_url : null
}

output "observability_metrics_push_url" {
  value = var.enable_observability ? stackit_observability_instance.rehost_obs[0].metrics_push_url : null
}
