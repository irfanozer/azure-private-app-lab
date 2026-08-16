variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet to link with every Private DNS zone."
  type        = string
}

variable "zones" {
  description = "Map of logical zone key to Azure Private Link DNS zone name."
  type        = map(string)
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

