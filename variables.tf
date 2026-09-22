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

variable "boot_volume_size" {
  type        = number
  description = "Boot volume size in GB"
  default     = 60
}

variable "boot_volume_performance_class" {
  type        = string
  description = "STACKIT performance class for the server boot volume"
  default     = "storage_premium_perf6"
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

variable "image_name" {
  type        = string
  description = "Exact STACKIT image name used when image auto-discovery is enabled"
  default     = "Ubuntu 22.04"
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

variable "key_pair_name" {
  type        = string
  description = "Optional global STACKIT key pair name; defaults to a project-specific name"
  default     = ""
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH on the VM. Use the operator's current public IP as a /32; leave empty only for short-lived diagnostics."

  validation {
    condition     = var.ssh_allowed_cidr == "" || can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "ssh_allowed_cidr must be empty or a valid IPv4 CIDR."
  }
}

variable "app_allowed_cidr" {
  type        = string
  description = "CIDR allowed to connect directly to the Spring Boot port"

  validation {
    condition     = can(cidrnetmask(var.app_allowed_cidr))
    error_message = "app_allowed_cidr must be a valid IPv4 CIDR."
  }
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

variable "enable_server_backup" {
  type        = bool
  description = "Enable STACKIT Server Backup and a recurring backup schedule for the VM boot volume"
  default     = false
}

variable "server_backup_schedule_name" {
  type        = string
  description = "Name of the STACKIT Server Backup schedule"
  default     = "rehost-springboot-daily"
}

variable "server_backup_name" {
  type        = string
  description = "Name assigned to backups created by the recurring schedule"
  default     = "rehost-springboot"
}

variable "server_backup_retention_days" {
  type        = number
  description = "Retention period in days for scheduled server backups"
  default     = 14

  validation {
    condition     = var.server_backup_retention_days >= 1 && floor(var.server_backup_retention_days) == var.server_backup_retention_days
    error_message = "server_backup_retention_days must be a positive integer."
  }
}

variable "server_backup_schedule_rrule" {
  type        = string
  description = "RFC 5545 recurrence rule for the STACKIT Server Backup schedule"
  default     = "DTSTART;TZID=Europe/Berlin:20200101T020000 RRULE:FREQ=DAILY;INTERVAL=1"
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
  default     = "2m"
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

variable "enable_local_postgresql" {
  type        = bool
  description = "Install and configure PostgreSQL on the target VM for the Spring Boot app"
  default     = false
}

variable "postgresql_vm_listen_port" {
  type        = number
  description = "PostgreSQL port used by the Spring Boot datasource configuration"
  default     = 5432
}

variable "postgresql_db_name" {
  type        = string
  description = "PostgreSQL database name used by the application"
  default     = "springmusic"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.postgresql_db_name))
    error_message = "postgresql_db_name must be a valid unquoted PostgreSQL identifier."
  }
}

variable "postgresql_app_username" {
  type        = string
  description = "PostgreSQL application username created on the VM"
  default     = "springmusic"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.postgresql_app_username))
    error_message = "postgresql_app_username must be a valid unquoted PostgreSQL identifier."
  }
}

variable "postgresql_app_password" {
  type        = string
  description = "PostgreSQL application password created on the VM"
  sensitive   = true
  default     = ""

  validation {
    condition     = var.postgresql_app_password == "" || can(regex("^[A-Za-z0-9_@%+=:,./-]{16,}$", var.postgresql_app_password))
    error_message = "postgresql_app_password must be empty or contain at least 16 supported characters."
  }
}

variable "postgresql_source_dump_local_path" {
  type        = string
  description = "Optional local path to a PostgreSQL dump file that should be copied to the VM"
  default     = ""
}

variable "postgresql_vm_dump_path" {
  type        = string
  description = "Target dump file path on the VM"
  default     = "/tmp/source-postgresql.dump"
}

variable "postgresql_vm_rollback_dump_path" {
  type        = string
  description = "Target path for the pre-restore rollback dump on the VM"
  default     = "/var/backups/springmusic/pre-restore.dump"
}

variable "postgresql_expected_album_count" {
  type        = number
  description = "Expected number of rows in public.album after restore"
  default     = 0

  validation {
    condition     = var.postgresql_expected_album_count >= 0 && floor(var.postgresql_expected_album_count) == var.postgresql_expected_album_count
    error_message = "postgresql_expected_album_count must be a non-negative integer."
  }
}

variable "postgresql_expected_album_fingerprint" {
  type        = string
  description = "Expected MD5 fingerprint of canonicalized public.album rows after restore"
  default     = ""

  validation {
    condition     = var.postgresql_expected_album_fingerprint == "" || can(regex("^[0-9a-f]{32}$", var.postgresql_expected_album_fingerprint))
    error_message = "postgresql_expected_album_fingerprint must be empty or a lowercase MD5 value."
  }
}

variable "postgresql_restore_after_copy" {
  type        = bool
  description = "When true and a dump file is provided, restore the dump into the target database"
  default     = false
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
  default     = 8
}

variable "springboot_loadgen_randomized_delay_seconds" {
  type        = number
  description = "Additional randomized delay in seconds for the local load generator timer"
  default     = 8
}

variable "springboot_loadgen_burst_min_requests" {
  type        = number
  description = "Minimum number of HTTP requests per generated load burst"
  default     = 40
}

variable "springboot_loadgen_burst_max_requests" {
  type        = number
  description = "Maximum number of HTTP requests per generated load burst"
  default     = 160
}

variable "springboot_loadgen_enable_stress" {
  type        = bool
  description = "Enable CPU and memory stress during each generated load burst"
  default     = true
}

variable "springboot_loadgen_stress_cpu_workers" {
  type        = number
  description = "Number of stress-ng CPU workers executed per load burst"
  default     = 2
}

variable "springboot_loadgen_stress_vm_workers" {
  type        = number
  description = "Number of stress-ng VM workers executed per load burst"
  default     = 1
}

variable "springboot_loadgen_stress_vm_bytes" {
  type        = string
  description = "Memory size per VM worker for stress-ng, for example 256M or 40%"
  default     = "40%"
}

variable "springboot_loadgen_stress_timeout_seconds" {
  type        = number
  description = "Duration in seconds of CPU and memory stress per generated load burst"
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
