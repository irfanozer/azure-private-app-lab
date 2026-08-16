variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Dedicated subnet for all lab Private Endpoint NICs."
  type        = string
}

variable "endpoints" {
  description = "Map of Private Endpoints and matching Private DNS zones."
  type = map(object({
    name                           = string
    private_connection_resource_id = string
    subresource_names              = list(string)
    private_dns_zone_ids           = list(string)
  }))
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

