variable "name" {
  description = "Private DNS Resolver name."
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

variable "virtual_network_id" {
  description = "VNet hosting the resolver."
  type        = string
}

variable "inbound_subnet_id" {
  description = "Dedicated delegated inbound endpoint subnet."
  type        = string
}

variable "outbound_subnet_id" {
  description = "Dedicated delegated outbound endpoint subnet."
  type        = string
}

variable "forwarding_rule_domain" {
  description = "Optional conditional-forwarding suffix, including trailing dot."
  type        = string
  default     = null
  nullable    = true
}

variable "forwarding_target_ips" {
  description = "Optional custom/on-premises DNS server targets."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

