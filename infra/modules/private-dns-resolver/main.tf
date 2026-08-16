resource "azurerm_private_dns_resolver" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.virtual_network_id
  tags                = var.tags
}

# Hybrid/on-premises DNS servers forward Azure-private names to this private IP.
resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location

  ip_configurations {
    subnet_id                    = var.inbound_subnet_id
    private_ip_allocation_method = "Dynamic"
  }

  tags = var.tags
}

# Azure uses this endpoint as the egress path for conditional DNS forwarding.
resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  name                    = "outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  subnet_id               = var.outbound_subnet_id
  tags                    = var.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  name                                       = "rules-${var.name}"
  resource_group_name                        = var.resource_group_name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this.id]
  tags                                       = var.tags
}

resource "azurerm_private_dns_resolver_virtual_network_link" "this" {
  name                      = "link-${var.name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = var.virtual_network_id
}

resource "azurerm_private_dns_resolver_forwarding_rule" "this" {
  count = var.forwarding_rule_domain != null && length(var.forwarding_target_ips) > 0 ? 1 : 0

  name                      = "conditional-forward"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = var.forwarding_rule_domain
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = toset(var.forwarding_target_ips)

    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

