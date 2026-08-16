data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  base_name = "${var.name_prefix}-${var.environment}-${random_string.suffix.result}"

  # Storage accounts are globally unique, lowercase, alphanumeric, and limited
  # to 24 characters.
  storage_account_name = substr(
    replace("st${var.name_prefix}${var.environment}${random_string.suffix.result}", "-", ""),
    0,
    24,
  )

  common_tags = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      purpose     = "azure-github-actions-learning-lab"
    },
    var.tags,
  )
}

module "network" {
  source = "../../modules/network"

  name                        = "vnet-${local.base_name}"
  resource_group_name         = data.azurerm_resource_group.lab.name
  location                    = data.azurerm_resource_group.lab.location
  address_space               = ["10.42.0.0/16"]
  enable_private_dns_resolver = var.enable_private_dns_resolver
  tags                        = local.common_tags
}

module "private_dns" {
  source = "../../modules/private-dns"

  resource_group_name = data.azurerm_resource_group.lab.name
  virtual_network_id  = module.network.virtual_network_id

  zones = {
    app_service = "privatelink.azurewebsites.net"
    blob        = "privatelink.blob.core.windows.net"
  }

  tags = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  name                = local.storage_account_name
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location
  tags                = local.common_tags
}

module "app_service_plan" {
  source = "../../modules/app-service-plan"

  name                = "asp-${local.base_name}"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location
  sku_name            = var.app_service_sku_name
  tags                = local.common_tags
}

# Calling the same child module twice with different parameters is the
# Terraform equivalent of instantiating the same reusable component twice.
module "reader_app" {
  source = "../../modules/web-app"

  name                       = "app-reader-${local.base_name}"
  resource_group_name        = data.azurerm_resource_group.lab.name
  location                   = data.azurerm_resource_group.lab.location
  service_plan_id            = module.app_service_plan.id
  vnet_integration_subnet_id = module.network.app_integration_subnet_id
  storage_account_name       = module.storage.name
  access_level               = "read"
  tags                       = local.common_tags
}

module "writer_app" {
  source = "../../modules/web-app"

  name                       = "app-writer-${local.base_name}"
  resource_group_name        = data.azurerm_resource_group.lab.name
  location                   = data.azurerm_resource_group.lab.location
  service_plan_id            = module.app_service_plan.id
  vnet_integration_subnet_id = module.network.app_integration_subnet_id
  storage_account_name       = module.storage.name
  access_level               = "read-write"
  tags                       = local.common_tags
}

# ARM Reader/Contributor roles do not grant Blob data access. These are data-
# plane roles scoped to one storage account and to one workload identity each.
resource "azurerm_role_assignment" "reader_blob_data" {
  scope                            = module.storage.id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = module.reader_app.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "writer_blob_data" {
  scope                            = module.storage.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = module.writer_app.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

module "private_endpoints" {
  source = "../../modules/private-endpoints"

  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location
  subnet_id           = module.network.private_endpoint_subnet_id

  endpoints = {
    blob = {
      name                           = "pe-blob-${local.base_name}"
      private_connection_resource_id = module.storage.id
      subresource_names              = ["blob"]
      private_dns_zone_ids           = [module.private_dns.zone_ids["blob"]]
    }

    reader_app = {
      name                           = "pe-reader-${local.base_name}"
      private_connection_resource_id = module.reader_app.id
      subresource_names              = ["sites"]
      private_dns_zone_ids           = [module.private_dns.zone_ids["app_service"]]
    }

    writer_app = {
      name                           = "pe-writer-${local.base_name}"
      private_connection_resource_id = module.writer_app.id
      subresource_names              = ["sites"]
      private_dns_zone_ids           = [module.private_dns.zone_ids["app_service"]]
    }
  }

  tags = local.common_tags
}

module "private_dns_resolver" {
  count  = var.enable_private_dns_resolver ? 1 : 0
  source = "../../modules/private-dns-resolver"

  name                   = "dnspr-${local.base_name}"
  resource_group_name    = data.azurerm_resource_group.lab.name
  location               = data.azurerm_resource_group.lab.location
  virtual_network_id     = module.network.virtual_network_id
  inbound_subnet_id      = module.network.dns_resolver_inbound_subnet_id
  outbound_subnet_id     = module.network.dns_resolver_outbound_subnet_id
  forwarding_rule_domain = var.forwarding_rule_domain
  forwarding_target_ips  = var.forwarding_target_ips
  tags                   = local.common_tags
}

