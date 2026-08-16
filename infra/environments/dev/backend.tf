terraform {
  # Values are deliberately supplied by `terraform init -backend-config=...`.
  # Keeping account names out of source lets the same root module serve several
  # repositories and subscriptions.
  backend "azurerm" {}
}

