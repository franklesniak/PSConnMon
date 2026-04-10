variable "location" {
  description = "Azure location for all PSConnMon resources."
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group that will host PSConnMon resources."
  type        = string
  default     = "rg-psconnmon-demo"
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace."
  type        = string
  default     = "log-psconnmon"
}

variable "user_assigned_identity_name" {
  description = "Name of the user-assigned managed identity."
  type        = string
  default     = "id-psconnmon"
}

variable "deploy_storage" {
  description = "When true, create a storage account and blob container for PSConnMon."
  type        = bool
  default     = true
}

variable "storage_account_name" {
  description = "Storage account name for config and telemetry when deploy_storage is true."
  type        = string
  default     = "psconnmonstorage01"
}

variable "storage_container_name" {
  description = "Storage container for PSConnMon blobs when deploy_storage is true."
  type        = string
  default     = "telemetry"
}

variable "existing_storage_account_name" {
  description = "Existing storage account name to inject into the app when deploy_storage is false."
  type        = string
  default     = ""
}

variable "existing_storage_account_id" {
  description = "Existing storage account resource ID when deploy_storage is false."
  type        = string
  default     = null
}

variable "existing_storage_container_name" {
  description = "Existing storage container name to inject into the app when deploy_storage is false."
  type        = string
  default     = ""
}

variable "deploy_container_app" {
  description = "When true, create the Container Apps environment and reporting app."
  type        = bool
  default     = true
}

variable "environment_name" {
  description = "Name of the Container Apps environment."
  type        = string
  default     = "cae-psconnmon"
}

variable "container_app_name" {
  description = "Name of the PSConnMon reporting Container App."
  type        = string
  default     = "ca-psconnmon-reporting"
}

variable "container_image" {
  description = "Container image for the reporting service."
  type        = string
  default     = "ghcr.io/example/psconnmon-service:latest"
}

variable "container_app_port" {
  description = "Container port exposed by the reporting service."
  type        = number
  default     = 8080
}

variable "container_app_db_path" {
  description = "Container-local database path for DuckDB."
  type        = string
  default     = "/data/psconnmon.duckdb"
}

variable "container_app_import_mode" {
  description = "Optional explicit import mode for the reporting service. Leave empty to auto-select azure when storage is configured, otherwise local."
  type        = string
  default     = ""
}

variable "container_app_import_interval_seconds" {
  description = "Import polling interval in seconds for the reporting service."
  type        = number
  default     = 30
}

variable "container_app_import_local_path" {
  description = "Local path scanned by the reporting service when local import mode is enabled."
  type        = string
  default     = "/data/import"
}

variable "container_app_blob_prefix" {
  description = "Blob prefix scanned by the reporting service for imported JSONL batches."
  type        = string
  default     = "events"
}

variable "container_app_azure_auth_mode" {
  description = "Azure auth mode used by the reporting service for blob imports."
  type        = string
  default     = "managedIdentity"
}

variable "container_app_cpu" {
  description = "CPU allocation for the reporting container."
  type        = number
  default     = 0.5
}

variable "container_app_memory" {
  description = "Memory allocation for the reporting container."
  type        = string
  default     = "1Gi"
}

variable "container_app_min_replicas" {
  description = "Minimum number of reporting container replicas."
  type        = number
  default     = 1
}

variable "container_app_max_replicas" {
  description = "Maximum number of reporting container replicas."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to all supported Azure resources."
  type        = map(string)
  default = {
    application = "psconnmon"
    environment = "demo"
  }
}
