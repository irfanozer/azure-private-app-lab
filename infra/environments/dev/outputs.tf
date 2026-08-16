output "resource_group_name" {
  description = "Resource group containing the lab."
  value       = data.azurerm_resource_group.lab.name
}

output "virtual_network_id" {
  description = "ID of the lab VNet."
  value       = module.network.virtual_network_id
}

output "storage_account_name" {
  description = "Private Storage account used by the example workloads."
  value       = module.storage.name
}

output "reader_app" {
  description = "Reader web app details. The hostname resolves privately from the linked VNet."
  value = {
    name         = module.reader_app.name
    hostname     = module.reader_app.default_hostname
    principal_id = module.reader_app.principal_id
    access_role  = "Storage Blob Data Reader"
  }
}

output "writer_app" {
  description = "Writer web app details. Storage Blob Data Contributor includes read, write, and delete."
  value = {
    name         = module.writer_app.name
    hostname     = module.writer_app.default_hostname
    principal_id = module.writer_app.principal_id
    access_role  = "Storage Blob Data Contributor"
  }
}

output "private_dns_zone_ids" {
  description = "Private DNS zones linked to the VNet."
  value       = module.private_dns.zone_ids
}

output "private_endpoint_ip_addresses" {
  description = "Private IP assigned to each Private Endpoint."
  value       = module.private_endpoints.private_ip_addresses
}

output "dns_resolver_inbound_ip" {
  description = "Inbound resolver IP when the optional hybrid-DNS lab is enabled."
  value       = try(module.private_dns_resolver[0].inbound_ip_address, null)
}

