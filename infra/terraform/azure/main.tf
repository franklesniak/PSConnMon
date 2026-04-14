locals {
  # Use created storage resources when requested, otherwise allow callers to
  # inject existing storage details for the reporting app configuration.
  storage_account_name = var.deploy_storage ? azurerm_storage_account.psconnmon[0].name : var.existing_storage_account_name
  storage_account_id   = var.deploy_storage ? azurerm_storage_account.psconnmon[0].id : var.existing_storage_account_id
  storage_container    = var.deploy_storage ? azurerm_storage_container.psconnmon[0].name : var.existing_storage_container_name
  import_mode          = var.container_app_import_mode != "" ? var.container_app_import_mode : (local.storage_account_name != "" && local.storage_container != "" ? "azure" : "local")
}

# Resource group for all PSConnMon resources created by this stack.
resource "azurerm_resource_group" "psconnmon" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Log Analytics is created up front so Container Apps can plug into a
# first-party logging destination when the app tier is enabled.
resource "azurerm_log_analytics_workspace" "psconnmon" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.psconnmon.location
  resource_group_name = azurerm_resource_group.psconnmon.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# User-assigned managed identity used by the reporting service and any future
# monitor-side Azure interactions.
resource "azurerm_user_assigned_identity" "psconnmon" {
  name                = var.user_assigned_identity_name
  location            = azurerm_resource_group.psconnmon.location
  resource_group_name = azurerm_resource_group.psconnmon.name
  tags                = var.tags
}

# Optional storage account for raw telemetry batches and remote config blobs.
resource "azurerm_storage_account" "psconnmon" {
  count                    = var.deploy_storage ? 1 : 0
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.psconnmon.name
  location                 = azurerm_resource_group.psconnmon.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

# Private blob container used by PSConnMon for config and batch storage.
resource "azurerm_storage_container" "psconnmon" {
  count                 = var.deploy_storage ? 1 : 0
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.psconnmon[0].id
  container_access_type = "private"
}

# Allow the managed identity to read and write blobs when this stack creates
# the backing storage account.
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  count                = var.deploy_storage ? 1 : 0
  scope                = azurerm_storage_account.psconnmon[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.psconnmon.principal_id
}

# Optional Container Apps environment for the reporting service.
resource "azurerm_container_app_environment" "psconnmon" {
  count                      = var.deploy_container_app ? 1 : 0
  name                       = var.environment_name
  location                   = azurerm_resource_group.psconnmon.location
  resource_group_name        = azurerm_resource_group.psconnmon.name
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.psconnmon.id
  tags                       = var.tags
}

# Optional reporting service deployment. The service can run with local-only
# storage or with storage metadata injected for Azure-backed workflows.
resource "azurerm_container_app" "psconnmon" {
  count                        = var.deploy_container_app ? 1 : 0
  name                         = var.container_app_name
  container_app_environment_id = azurerm_container_app_environment.psconnmon[0].id
  resource_group_name          = azurerm_resource_group.psconnmon.name
  revision_mode                = "Single"
  tags                         = var.tags

  lifecycle {
    # When deploy_storage is false, the reporting app still needs account and
    # container names injected via the existing_storage_* inputs so it can
    # pick azure/hybrid import modes at runtime.  Catch that at plan time
    # instead of deploying a Container App that crashes on startup.
    precondition {
      condition = (
        var.deploy_storage ||
        var.container_app_import_mode == "disabled" ||
        var.container_app_import_mode == "local" ||
        (var.existing_storage_account_name != "" && var.existing_storage_container_name != "")
      )
      error_message = "When deploy_storage = false and container_app_import_mode is '', 'azure', or 'hybrid', existing_storage_account_name and existing_storage_container_name must both be set."
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.psconnmon.id]
  }

  template {
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas

    container {
      name   = "reporting"
      image  = var.container_image
      cpu    = var.container_app_cpu
      memory = var.container_app_memory

      env {
        name  = "PSCONNMON_DB_PATH"
        value = var.container_app_db_path
      }

      env {
        name  = "PSCONNMON_IMPORT_MODE"
        value = local.import_mode
      }

      env {
        name  = "PSCONNMON_IMPORT_INTERVAL_SECONDS"
        value = tostring(var.container_app_import_interval_seconds)
      }

      env {
        name  = "PSCONNMON_IMPORT_LOCAL_PATH"
        value = var.container_app_import_local_path
      }

      env {
        name  = "PSCONNMON_AZURE_BLOB_PREFIX"
        value = var.container_app_blob_prefix
      }

      env {
        name  = "PSCONNMON_AZURE_AUTH_MODE"
        value = var.container_app_azure_auth_mode
      }

      dynamic "env" {
        for_each = local.storage_account_name == "" ? [] : [local.storage_account_name]
        content {
          name  = "PSCONNMON_AZURE_STORAGE_ACCOUNT"
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.storage_container == "" ? [] : [local.storage_container]
        content {
          name  = "PSCONNMON_AZURE_STORAGE_CONTAINER"
          value = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = var.container_app_port
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = var.container_app_port
        path      = "/healthz"
      }
    }
  }

  ingress {
    external_enabled           = true
    target_port                = var.container_app_port
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
