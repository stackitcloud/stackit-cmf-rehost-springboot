terraform {
  required_version = ">= 1.5.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "= 4.46.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "= 0.14.2"
    }

    stackit = {
      source  = "stackitcloud/stackit"
      version = "= 0.116.0"
    }
  }
}

provider "stackit" {
  service_account_key_path = pathexpand(var.service_account_key_path)
  default_region           = var.region
  enable_beta_resources    = true
}

provider "grafana" {
  url                = var.enable_observability ? stackit_observability_instance.rehost_obs[0].grafana_url : null
  auth               = var.enable_observability ? "${stackit_observability_instance.rehost_obs[0].grafana_initial_admin_user}:${stackit_observability_instance.rehost_obs[0].grafana_initial_admin_password}" : null
  retries            = 12
  retry_wait         = 15
  retry_status_codes = ["403", "429", "5xx"]
}
