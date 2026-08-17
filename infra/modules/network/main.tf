resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

# The VM lives directly in this subnet. Unlike App Service VNet integration,
# an Azure VM has its own NIC in the VNet and needs no subnet delegation.
resource "azurerm_subnet" "compute" {
  name                            = "snet-compute"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = ["10.42.0.0/26"]
  default_outbound_access_enabled = false
}

moved {
  from = azurerm_subnet.app_integration
  to   = azurerm_subnet.compute
}

# Private Endpoint NICs are private entry points to PaaS services. Keeping
# them separate from compute makes routing and security policy easier to see.
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
