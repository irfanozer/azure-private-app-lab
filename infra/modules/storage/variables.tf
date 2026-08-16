variable "name" {
  description = "Globally unique Storage account name."
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

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

