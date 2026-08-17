resource "azurerm_private_endpoint" "this" {
  for_each = var.endpoints

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.private_connection_resource_id
    subresource_names              = each.value.subresource_names
    is_manual_connection           = false
  }

  # Azure manages the matching private DNS A records for the endpoint.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = each.value.private_dns_zone_ids
  }

  tags = var.tags
}
