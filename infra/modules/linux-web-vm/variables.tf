variable "name" {
  description = "Linux VM name."
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

variable "subnet_id" {
  description = "Compute subnet containing the VM NIC."
  type        = string
}

variable "size" {
  description = "Azure VM size."
  type        = string
}

variable "storage_account_name" {
  description = "Private Storage account authorized for the VM identity."
  type        = string
}

variable "tags" {
  description = "Azure tags."
  type        = map(string)
  default     = {}
}
