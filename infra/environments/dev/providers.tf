provider "azurerm" {
  features {}

  # Bootstrap registers only the namespaces this lab uses. Prevent AzureRM 4.x
  # from trying to register its much larger legacy provider set at subscription
  # scope, which the read-oriented plan identity intentionally cannot modify.
  resource_provider_registrations = "none"

  # AzureRM 4.x requires the subscription ID. In GitHub Actions the OIDC
  # settings themselves arrive through ARM_USE_OIDC/ARM_CLIENT_ID/etc.
  subscription_id = var.subscription_id
}
