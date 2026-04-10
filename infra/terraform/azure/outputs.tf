output "container_app_fqdn" {
  description = "Public FQDN for the PSConnMon reporting service, when deployed."
  value       = var.deploy_container_app ? azurerm_container_app.psconnmon[0].latest_revision_fqdn : null
}

output "managed_identity_id" {
  description = "User-assigned managed identity resource ID."
  value       = azurerm_user_assigned_identity.psconnmon.id
}

output "storage_account_name" {
  description = "Storage account used for telemetry and config when storage is configured."
  value       = local.storage_account_name
}

output "storage_account_id" {
  description = "Storage account resource ID when available."
  value       = local.storage_account_id
}
