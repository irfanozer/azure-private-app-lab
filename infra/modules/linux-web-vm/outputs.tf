output "id" {
  description = "Linux VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "Linux VM name."
  value       = azurerm_linux_virtual_machine.this.name
}

output "principal_id" {
  description = "Object/principal ID of the VM system-assigned managed identity."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "public_ip_address" {
  description = "Static public IPv4 address used to browse the Nginx page."
  value       = azurerm_public_ip.this.ip_address
}

output "http_url" {
  description = "Public browser URL for the Nginx demonstration page."
  value       = "http://${azurerm_public_ip.this.ip_address}"
}

output "private_ip_address" {
  description = "Private IPv4 address assigned to the VM NIC."
  value       = azurerm_network_interface.this.private_ip_address
}

output "network_security_group_id" {
  description = "NSG allowing HTTP while leaving SSH closed."
  value       = azurerm_network_security_group.this.id
}
