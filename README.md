# stackit-cmf-rehost-springboot

Runnable Rehost automation example for STACKIT using Terraform and Ansible.

## What this repo does

- Provisions network/security and a VM in STACKIT via Terraform.
- Assigns a public IP and SSH key.
- Bridges to Ansible to install Java, copy a Spring Boot JAR, and run it as a `systemd` service.
- Optionally provisions STACKIT Observability, registers scrape jobs, and imports a starter Grafana dashboard.

The repository includes a ready-to-deploy sample Spring Boot artifact at `ansible/files/springboot-app.jar`.
By default, Terraform/Ansible deploy this artifact via `jar_local_path = "ansible/files/springboot-app.jar"`.

The example can also install a VM-local PostgreSQL and wire Spring Boot to that database when
`enable_local_postgresql = true`.

## Prerequisites

- Terraform `>= 1.5`
- Ansible
- SSH key pair available on your machine (default: `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)
- A STACKIT service account email (used as project owner in `target_project_owner_email`)
- Downloaded JSON key file for this service account (referenced via `service_account_key_path`)
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

To enable observability rollout in the same apply, set these values in `env.tfvars`:

- `enable_observability = true`
- `enable_node_exporter = true`
- `create_grafana_dashboard = true`

Optional (only if your app exposes Prometheus metrics):

- `enable_springboot_metrics_scrape = true`
- `springboot_metrics_path = "/actuator/prometheus"`

Optional (to generate local demo traffic directly from the VM):

- `enable_local_load_generator = true`

Optional (to enable VM-local PostgreSQL for the app):

- `enable_local_postgresql = true`
- `postgresql_db_name = "springmusic"`
- `postgresql_app_username = "springmusic"`

Pass the database password outside the variable file:

```bash
export TF_VAR_postgresql_app_password='<at-least-16-characters>'
```

Optional (to import source data during provisioning):

- `postgresql_source_dump_local_path = "/absolute/path/to/source.dump"`
- `postgresql_restore_after_copy = true`

## Common flag wrapper

To use the common CMF flags, copy and adjust:

```bash
cp flags.env.example flags.env
```

Then run:

```bash
./scripts/apply_with_common_flags.sh flags.env env.tfvars
```

Common flags:

- `setup_project`
- `setup_observability`
- `setup_database`
- `setup_workload`
- `setup_loadgen`
- `setup_dns`

4. After apply:

```bash
terraform output vm_public_ip
terraform output application_url
terraform output observability_grafana_url
```

## Observability behavior

- When `enable_observability = true`, Terraform creates a STACKIT Observability instance.
- Ansible installs `prometheus-node-exporter` on the VM and writes custom app health metrics (`springboot_up`, `springboot_http_status_code`) via the textfile collector.
- If `enable_local_load_generator = true`, Ansible also writes request counter metrics (`springboot_http_requests_total`) via the same textfile collector.
- Terraform creates a scrape job for node exporter (`:9100/metrics`).
- Optionally, Terraform also creates a scrape job for `springboot_metrics_path`.
- If `create_grafana_dashboard = true`, Terraform imports `dashboards/rehost-observability-dashboard.json` into Grafana.
- If `enable_local_load_generator = true`, Ansible installs a local load generator (`springboot-loadgen.service` + `springboot-loadgen.timer`) that calls the app endpoint with an irregular burst profile.

### Grafana dashboard snapshot

![Grafana dashboard snapshot for rehost spring boot observability](assets/images/scf_rehost_spring_boot_grafana.png)

### Local irregular load profile

You can tune the generated load in `env.tfvars`:

- `springboot_loadgen_target_path` (default: `/`)
- `springboot_loadgen_base_interval_seconds` (default: `8`)
- `springboot_loadgen_randomized_delay_seconds` (default: `8`)
- `springboot_loadgen_burst_min_requests` (default: `40`)
- `springboot_loadgen_burst_max_requests` (default: `160`)
- `springboot_loadgen_enable_stress` (default: `true`)
- `springboot_loadgen_stress_cpu_workers` (default: `2`)
- `springboot_loadgen_stress_vm_workers` (default: `1`)
- `springboot_loadgen_stress_vm_bytes` (default: `40%`)
- `springboot_loadgen_stress_timeout_seconds` (default: `15`)

The timer uses `OnUnitActiveSec` + `RandomizedDelaySec`, and each run sends a random number of requests with short random pauses between requests.
If `springboot_loadgen_enable_stress = true`, each run additionally executes `stress-ng` to generate CPU and RAM pressure.

Request-related exported metrics from the load generator:

- `springboot_http_requests_total`
- `springboot_http_requests_last_burst`
- `springboot_http_requests_last_burst_success`
- `springboot_http_requests_last_burst_failed`
- `springboot_loadgen_stress_enabled`
- `springboot_loadgen_stress_applied`
- `springboot_loadgen_stress_cpu_workers`
- `springboot_loadgen_stress_vm_workers`
- `springboot_loadgen_stress_timeout_seconds`

The default dashboard includes `Spring Boot HTTP Requests (5m)` based on:

`sum by (instance) (increase(springboot_http_requests_total[5m]))`

Security note: with `expose_node_exporter_port = true`, port `9100` is exposed via the security group. Restrict this according to your network policy.

## Spring Boot artifact used for deployment

- Default artifact path: `ansible/files/springboot-app.jar`
- To deploy a different app, replace this file or set `jar_local_path` in `env.tfvars`.

## Rehost data migration path (source PostgreSQL -> target VM PostgreSQL)

Use this flow when `enable_local_postgresql = true`.

### Reproducible sample source

Install PostgreSQL server and client tools, then create and validate the included sample source:

```bash
./scripts/create_source_dump.sh
./scripts/validate_source_dump.sh
```

The first command starts an isolated temporary PostgreSQL cluster, loads
`migration/source/springmusic.sql`, and writes these ignored runtime artifacts:

- `artifacts/source-postgresql.dump`
- `artifacts/source-postgresql.dump.sha256`
- `artifacts/source-postgresql.manifest`

The second command restores the dump into another empty temporary cluster and compares its row count and canonical album fingerprint with the manifest.

### Existing PostgreSQL source

On the source system, export data:

```bash
pg_dump --format=custom --no-owner --no-privileges --dbname=<source-db> --file=/tmp/source.dump
```

Copy the dump file to your Terraform execution host and record a checksum, expected row count, and a workload-specific data fingerprint.

### Restore to STACKIT

Set in `env.tfvars`:

```hcl
enable_local_postgresql           = true
postgresql_source_dump_local_path = "artifacts/source-postgresql.dump"
postgresql_restore_after_copy     = true
postgresql_expected_album_count   = 8
postgresql_expected_album_fingerprint = "<value-from-source-postgresql.manifest>"
```

Run a reviewed plan and apply it:

```bash
terraform plan -var-file=env.tfvars -out=tfplan
terraform apply tfplan
./scripts/validate_migration.sh
./scripts/validate_deployment.sh
```

The restore stops Spring Boot, creates `/var/backups/springmusic/pre-restore.dump`, and records its source-dump hash, row count, and fingerprint. Retrying the same source-dump generation preserves this rollback point; a different dump archives it and creates a new one. The source is restored in one transaction with ownership assigned to the application role. Spring Boot starts only after source evidence passes; a restore or validation failure leaves it stopped. Rollback files are owned by `postgres` with mode `0600`.

Verify the rollback artifact without changing the target database by restoring it into a separate temporary database before cutover. Retain the source and rollback dump until the rollback window closes.

### Rehearsal, cutover, and rollback

Run the migration rehearsal first. It restores the source dump into a temporary database on the target VM, validates the row count and fingerprint, and removes the temporary database without changing the application database:

```bash
./scripts/run_migration_rehearsal.sh
```

Execute the cutover only after reviewing the source evidence and Terraform plan:

```bash
./scripts/run_cutover.sh --confirm
```

The cutover script forces replacement of the Ansible orchestration resource because Terraform cannot detect database data drift. It requires a fully available VM backup no older than 24 hours when Server Backup is enabled, rejects every plan change except replacement of that exact resource, applies the saved plan, validates the migrated data and application, and requires a final no-op plan. Override the age gate only through the reviewed `SERVER_BACKUP_MAX_AGE_HOURS` environment variable.

Verify the pre-restore rollback dump in an isolated temporary database:

```bash
./scripts/verify_rollback.sh
```

To perform a database rollback during the agreed rollback window, run:

```bash
./scripts/rollback_postgresql.sh --confirm
```

The rollback workflow preserves the current target database before restoring the original pre-restore dump. Each workflow writes machine-readable evidence to `artifacts/evidence/<timestamp>-<mode>/evidence.env`.

## Server backup

Set `enable_server_backup = true` to enable STACKIT Server Backup and a daily schedule for the VM boot volume. The default schedule runs at 02:00 Europe/Berlin and retains backups for 14 days; both values are configurable in `env.tfvars`.

The schedule protects the complete boot volume in addition to the database-specific rollback dump. Creating and listing backups has been validated against a real STACKIT server. A restore is an in-place, disruptive operation and must be rehearsed in a separate disaster-recovery environment before relying on it for production recovery.

## Ingress restrictions

Set `ssh_allowed_cidr` and `app_allowed_cidr` to source addresses observed on the target path. Corporate proxies or target-dependent NAT can make public IP lookup services report a different address. In the validated environment, SSH and HTTP used different `/32` addresses.

Node exporter ingress is generated from the official STACKIT public service ranges when Observability and the exporter are enabled.

## Destroy

```bash
terraform destroy -var-file=env.tfvars
```

## Local validation

Run the Terraform, shell, and Ansible checks before creating a plan:

```bash
./scripts/check.sh
```

Validate a deployed VM after apply:

```bash
./scripts/validate_deployment.sh
```

## Notes

- `env.tfvars.example` contains placeholders by design. Fill them in `env.tfvars` before running.
- If your region uses a different image/flavor, adjust `image_id` and `machine_type`.
- `ansible` is triggered automatically by Terraform via `terraform_data`.
