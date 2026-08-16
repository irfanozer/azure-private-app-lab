variable "name" {
  description = "Globally unique Linux Web App name."
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

variable "service_plan_id" {
  description = "Shared App Service Plan resource ID."
  type        = string
}

variable "vnet_integration_subnet_id" {
  description = "Dedicated Microsoft.Web/serverFarms delegated subnet for outbound traffic."
  type        = string
}

variable "storage_account_name" {
  description = "Storage account the sample workload is authorized to use."
  type        = string
}

variable "access_level" {
  description = "Educational label for the workload's RBAC level."
  type        = string

  validation {
    condition     = contains(["read", "read-write"], var.access_level)
    error_message = "access_level must be read or read-write."
  }
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}

