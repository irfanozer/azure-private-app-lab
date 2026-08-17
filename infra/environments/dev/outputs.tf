output "resource_group_name" {
  description = "Resource group containing the lab."
  value       = data.azurerm_resource_group.lab.name
}

output "virtual_network_id" {
  description = "ID of the lab VNet."
  value       = module.network.virtual_network_id
}

output "storage_account_name" {
  description = "Private Storage account authorized for the VM workload identity."
  value       = module.storage.name
}

output "web_vm" {
  description = "Browser-accessible Linux VM and its workload identity."
  value = {
    name         = module.web_vm.name
    public_ip    = module.web_vm.public_ip_address
    private_ip   = module.web_vm.private_ip_address
    browser_url  = module.web_vm.http_url
    principal_id = module.web_vm.principal_id
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
