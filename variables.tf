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
