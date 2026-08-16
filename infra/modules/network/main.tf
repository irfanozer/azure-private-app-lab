resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

# App Service regional VNet integration is outbound connectivity. Azure
# requires a dedicated subnet delegated to Microsoft.Web/serverFarms.
resource "azurerm_subnet" "app_integration" {
  name                 = "snet-app-integration"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.0.0/26"]

  delegation {
    name = "app-service-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private Endpoint NICs are inbound paths to PaaS services. They cannot share
# the App Service integration subnet.
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.1.0/27"]

  private_endpoint_network_policies = "Disabled"
}

# Resolver endpoints each require their own empty delegated /28-/24 subnet.
resource "azurerm_subnet" "dns_resolver_inbound" {
  count = var.enable_private_dns_resolver ? 1 : 0

  name                 = "snet-dns-resolver-inbound"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.3.0/28"]

  delegation {
    name = "dns-resolver-inbound-delegation"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "dns_resolver_outbound" {
  count = var.enable_private_dns_resolver ? 1 : 0

  name                 = "snet-dns-resolver-outbound"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.3.16/28"]

  delegation {
    name = "dns-resolver-outbound-delegation"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

