# stackit-cmf-rehost-springboot

Runnable Rehost automation example for STACKIT using Terraform and Ansible.

## What this repo does

- Provisions network/security and a VM in STACKIT via Terraform.
- Assigns a public IP and SSH key.
- Bridges to Ansible to install Java, copy a Spring Boot JAR, and run it as a `systemd` service.

## Prerequisites

- Terraform `>= 1.5`
- Ansible
- A valid STACKIT API token as environment variable:

```bash
export STACKIT_SERVICE_ACCOUNT_TOKEN="<token>"
```

## Quick start

```bash
cp env.tfvars.example env.tfvars
# adjust values where required
terraform init
terraform plan -var-file=env.tfvars
terraform apply -var-file=env.tfvars
```

After apply:

```bash
terraform output vm_public_ip
terraform output application_url
```

## Destroy

```bash
terraform destroy -var-file=env.tfvars
```

## Notes

- `project_id` is prefilled with the test value from the current setup.
- If your region uses a different image/flavor, adjust `image_id` and `machine_type`.
- `ansible` is triggered automatically by Terraform via `terraform_data`.
