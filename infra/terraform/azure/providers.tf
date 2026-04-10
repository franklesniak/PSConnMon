terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.68.0"
    }
  }
}

# Authenticate with Azure CLI, workload identity, or managed identity based on
# the execution environment.
provider "azurerm" {
  features {}
}
