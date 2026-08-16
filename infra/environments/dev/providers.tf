provider "azurerm" {
  features {}

  # AzureRM 4.x requires the subscription ID. In GitHub Actions the OIDC
  # settings themselves arrive through ARM_USE_OIDC/ARM_CLIENT_ID/etc.
  subscription_id = var.subscription_id
}

