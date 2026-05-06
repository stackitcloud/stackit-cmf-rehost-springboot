terraform {
  required_version = ">= 1.5.0"

  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = ">= 0.35.0"
    }
  }
}

provider "stackit" {
  service_account_key_path = pathexpand(var.service_account_key_path)
  default_region           = var.region
  enable_beta_resources    = true
}
