location                     = "centralus"
resource_group_name          = "rg-psconnmon-demo"
log_analytics_workspace_name = "log-psconnmon-demo"
user_assigned_identity_name  = "id-psconnmon-demo"

deploy_storage         = true
storage_account_name   = "psconnmondemo01"
storage_container_name = "telemetry"

deploy_container_app                  = true
environment_name                      = "cae-psconnmon-demo"
container_app_name                    = "ca-psconnmon-reporting-demo"
container_image                       = "ghcr.io/example/psconnmon-service:latest"
container_app_import_mode             = "azure"
container_app_import_interval_seconds = 30
container_app_blob_prefix             = "events"
container_app_azure_auth_mode         = "managedIdentity"

tags = {
  application = "psconnmon"
  environment = "demo"
}
