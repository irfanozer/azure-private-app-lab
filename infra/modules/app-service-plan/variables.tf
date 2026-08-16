variable "name" {
  description = "App Service Plan name."
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

variable "sku_name" {
  description = "App Service SKU."
  type        = string
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

