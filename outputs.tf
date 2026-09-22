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

output "vm_server_id" {
  value = stackit_server.rehost_vm.server_id
}

output "region" {
  value = var.region
}

output "application_url" {
  value = "http://${stackit_public_ip.rehost_public_ip.ip}:${var.springboot_app_port}"
}

output "server_backup_enabled" {
  value = var.enable_server_backup ? stackit_server_backup_enable.rehost[0].enabled : false
}

output "server_backup_schedule_id" {
  value = var.enable_server_backup ? stackit_server_backup_schedule.rehost[0].backup_schedule_id : null
}

output "postgresql_jdbc_url" {
  value = var.enable_local_postgresql ? "jdbc:postgresql://127.0.0.1:${var.postgresql_vm_listen_port}/${var.postgresql_db_name}" : null
}

output "local_postgresql_enabled" {
  value = var.enable_local_postgresql
}

output "postgresql_database_name" {
  value = var.postgresql_db_name
}

output "node_exporter_enabled" {
  value = var.enable_observability && var.enable_node_exporter
}

output "node_exporter_port" {
  value = var.node_exporter_port
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
