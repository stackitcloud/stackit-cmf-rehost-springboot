# stackit-cmf-rehost-springboot

Runnable Rehost automation example for STACKIT using Terraform and Ansible.

## What this repo does

- Provisions network/security and a VM in STACKIT via Terraform.
- Assigns a public IP and SSH key.
- Bridges to Ansible to install Java, copy a Spring Boot JAR, and run it as a `systemd` service.

The repository includes a ready-to-deploy sample Spring Boot artifact at `ansible/files/springboot-app.jar`.
By default, Terraform/Ansible deploy this artifact via `jar_local_path = "ansible/files/springboot-app.jar"`.

## Prerequisites

- Terraform `>= 1.5`
- Ansible
- SSH key pair available on your machine (default: `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)
- A STACKIT service account with:
	- service account email (used as project owner in `target_project_owner_email`)
	- downloaded JSON key file (referenced via `service_account_key_path`)
- Permissions for the service account on folder or organization scope so project/network/compute resources can be created
- Parent container ID where the project should be created (`parent_container_id`)

Authentication for this example is based on the service account JSON key file.
`STACKIT_SERVICE_ACCOUNT_TOKEN` is not required.

## Quick start

1. Copy the example variables file:

```bash
cp env.tfvars.example env.tfvars
```

2. Edit `env.tfvars` and set at least:

- `service_account_key_path`
- `target_project_owner_email`
- `parent_container_id`

`bootstrap_project_id` can stay as placeholder when `parent_container_id` is set.

3. Initialize and run Terraform:

```bash
terraform init
terraform plan -var-file=env.tfvars
terraform apply -var-file=env.tfvars
```

4. After apply:

```bash
terraform output vm_public_ip
terraform output application_url
```

## Spring Boot artifact used for deployment

- Default artifact path: `ansible/files/springboot-app.jar`
- To deploy a different app, replace this file or set `jar_local_path` in `env.tfvars`.

## Destroy

```bash
terraform destroy -var-file=env.tfvars
```

## Notes

- `env.tfvars.example` contains placeholders by design. Fill them in `env.tfvars` before running.
- If your region uses a different image/flavor, adjust `image_id` and `machine_type`.
- `ansible` is triggered automatically by Terraform via `terraform_data`.
