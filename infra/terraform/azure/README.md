# Azure Deployment

- **Status:** Active
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Defines the Azure Terraform assets for the PSConnMon reporting
  service and storage-backed control plane. Does not cover CI/CD automation.
- **Related:** [Architecture](../../../docs/spec/architecture.md), [Roadmap](../../../PSConnMon_Roadmap.md)

## Summary

This Terraform stack provisions:

- A resource group
- A Log Analytics workspace
- A user-assigned managed identity
- An optional storage account and private blob container
- An optional Container Apps environment
- An optional public Container App for the reporting service

When the reporting Container App is enabled, the stack also injects the
runtime import settings used by the service:

- `PSCONNMON_DB_PATH`
- `PSCONNMON_IMPORT_MODE`
- `PSCONNMON_IMPORT_INTERVAL_SECONDS`
- `PSCONNMON_IMPORT_LOCAL_PATH`
- `PSCONNMON_AZURE_STORAGE_ACCOUNT`
- `PSCONNMON_AZURE_STORAGE_CONTAINER`
- `PSCONNMON_AZURE_BLOB_PREFIX`
- `PSCONNMON_AZURE_AUTH_MODE`

## Workflow

Run the standard Terraform workflow:

```bash
terraform init
terraform validate
terraform plan -var-file=demo.tfvars
terraform apply -var-file=demo.tfvars
```

## Files

- `providers.tf`: Terraform and provider configuration
- `variables.tf`: Input variables, including deployment toggles
- `main.tf`: Resource definitions with inline commentary
- `outputs.tf`: Conditional outputs for deployed resources
- `demo.tfvars`: Example values for a demo or lab deployment

## Main Inputs

| Variable | Description |
| --- | --- |
| `location` | Azure region for all created resources |
| `resource_group_name` | Resource group name |
| `log_analytics_workspace_name` | Log Analytics workspace name |
| `user_assigned_identity_name` | User-assigned managed identity name |
| `deploy_storage` | Toggle for storage account and blob container creation |
| `storage_account_name` | Storage account name when `deploy_storage = true` |
| `storage_container_name` | Blob container name when `deploy_storage = true` |
| `existing_storage_account_name` | Existing storage account name when reusing storage |
| `existing_storage_account_id` | Existing storage account resource ID when reusing storage |
| `existing_storage_container_name` | Existing storage container name when reusing storage |
| `deploy_container_app` | Toggle for Container Apps environment and app creation |
| `environment_name` | Container Apps environment name |
| `container_app_name` | Reporting service container app name |
| `container_image` | Reporting service container image |
| `container_app_port` | Reporting service port |
| `container_app_db_path` | DuckDB path inside the container |
| `container_app_import_mode` | Explicit import mode, or auto-select when empty |
| `container_app_import_interval_seconds` | Import polling interval |
| `container_app_import_local_path` | Local import path inside the container |
| `container_app_blob_prefix` | Blob prefix scanned for JSONL batches |
| `container_app_azure_auth_mode` | Azure auth mode for blob imports |
| `container_app_cpu` | CPU allocation for the reporting container |
| `container_app_memory` | Memory allocation for the reporting container |
| `container_app_min_replicas` | Minimum reporting replicas |
| `container_app_max_replicas` | Maximum reporting replicas |
| `tags` | Tags applied to supported Azure resources |

## Roadmap Mapping

- `Command and Control Model`: Storage account and managed identity
- `Logging and Telemetry`: Blob container for event batches
- `Visualization & Reporting`: Container App hosting the FastAPI dashboard

## Managed Identity Roles

When this stack creates the storage account, it assigns the reporting managed
identity to that storage account. If you reuse an existing storage account, you
must assign blob data access separately before the reporting service can import
batches.

## Blob Layout

The expected blob layout is:

- `events/<site-id>/<batch-name>.jsonl` for uploaded event batches
- `configs/<agent-id>.yaml` or `.json` for remotely managed monitor config

The service scans the configured blob prefix for `.jsonl` files only.

## Local Emulator Notes

For local Azurite testing, point the service at a local blob endpoint by
setting `PSCONNMON_AZURE_BLOB_SERVICE_URL` alongside the normal Azure import
variables. This override is intended for local testing only.
