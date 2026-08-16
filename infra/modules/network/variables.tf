variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
}

variable "enable_private_dns_resolver" {
  description = "Create dedicated delegated resolver subnets."
  type        = bool
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

