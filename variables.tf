variable "service_account_key_path" {
  type        = string
  description = "Path to STACKIT service account key JSON"
  default     = "~/.ssh/cmf-sa.json"
}

variable "bootstrap_project_id" {
  type        = string
  description = "Existing project ID used to discover parent container for creating a new project"
  default     = ""
}

variable "create_project" {
  type        = bool
  description = "Whether to create a dedicated project for this example"
  default     = true
}

variable "target_project_name" {
  type        = string
  description = "Name of the terraform-created project"
  default     = "cmf-rehost-springboot"
}

variable "target_project_owner_email" {
  type        = string
  description = "Owner email for terraform-created project (defaults to service account email when empty)"
  default     = ""
}

variable "parent_container_id" {
  type        = string
  description = "Optional explicit parent container ID/UUID for project creation; skips bootstrap project lookup when set"
  default     = ""
}

variable "project_id" {
  type        = string
  description = "Existing STACKIT project id (used only when create_project=false)"
  default     = ""
}

variable "region" {
  type        = string
  description = "STACKIT region"
  default     = "eu01"
}

variable "availability_zone" {
  type        = string
  description = "STACKIT availability zone"
  default     = "eu01-1"
}

variable "server_name" {
  type    = string
  default = "rehost-springboot-vm"
}

variable "machine_type" {
  type        = string
  description = "STACKIT flavor id"
  default     = ""
}

variable "image_id" {
  type        = string
  description = "Boot image id"
  default     = ""
}

variable "auto_discover_compute_defaults" {
  type        = bool
  description = "Try to auto-discover image and machine type via beta data sources"
  default     = false
}

variable "public_ssh_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "private_ssh_key_path" {
  type    = string
  default = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "jar_local_path" {
  type        = string
  description = "Path to Spring Boot JAR on local machine"
  default     = "ansible/files/springboot-app.jar"
}

variable "run_ansible" {
  type        = bool
  description = "Whether terraform should execute ansible-playbook after provisioning"
  default     = true
}

variable "enable_observability" {
  type        = bool
  description = "Enable provisioning of a STACKIT Observability instance and scrape jobs"
  default     = false
}

variable "observability_instance_name" {
  type        = string
  description = "Name of the STACKIT Observability instance"
  default     = "rehost-observability"
}

variable "observability_plan_name" {
  type        = string
  description = "Plan name for STACKIT Observability instance"
  default     = "Observability-Starter-EU01"
}

variable "observability_scrape_interval" {
  type        = string
  description = "Scrape interval used for Observability scrape jobs"
  default     = "30s"
}

variable "observability_scrape_timeout" {
  type        = string
  description = "Scrape timeout used for Observability scrape jobs (must be smaller than scrape interval)"
  default     = "10s"
}

variable "enable_node_exporter" {
  type        = bool
  description = "Install node exporter on the VM and create scrape config"
  default     = true
}

variable "node_exporter_port" {
  type        = number
  description = "Node exporter listen port"
  default     = 9100
}

variable "expose_node_exporter_port" {
  type        = bool
  description = "Open node exporter port on the security group"
  default     = true
}

variable "springboot_app_port" {
  type        = number
  description = "Spring Boot application port used by local health probe"
  default     = 8080
}

variable "enable_local_load_generator" {
  type        = bool
  description = "Enable local irregular request generation against the Spring Boot app from within the VM"
  default     = false
}

variable "springboot_loadgen_target_path" {
  type        = string
  description = "HTTP path used by the local load generator"
  default     = "/"
}

variable "springboot_loadgen_base_interval_seconds" {
  type        = number
  description = "Base interval in seconds for the systemd timer of the local load generator"
  default     = 20
}

variable "springboot_loadgen_randomized_delay_seconds" {
  type        = number
  description = "Additional randomized delay in seconds for the local load generator timer"
  default     = 40
}

variable "springboot_loadgen_burst_min_requests" {
  type        = number
  description = "Minimum number of HTTP requests per generated load burst"
  default     = 2
}

variable "springboot_loadgen_burst_max_requests" {
  type        = number
  description = "Maximum number of HTTP requests per generated load burst"
  default     = 15
}

variable "enable_springboot_metrics_scrape" {
  type        = bool
  description = "Create scrape config for Spring Boot metrics endpoint"
  default     = false
}

variable "springboot_metrics_port" {
  type        = number
  description = "Port of Spring Boot metrics endpoint"
  default     = 8080
}

variable "springboot_metrics_path" {
  type        = string
  description = "Path of Spring Boot Prometheus metrics endpoint"
  default     = "/actuator/prometheus"
}

variable "create_grafana_dashboard" {
  type        = bool
  description = "Create default Grafana dashboard for VM and app metrics"
  default     = true
}
