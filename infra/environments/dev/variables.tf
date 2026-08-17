variable "subscription_id" {
  description = "Azure subscription that contains the lab resource group."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must look like an Azure UUID."
  }
}

variable "resource_group_name" {
  description = "Pre-created resource group for the lab. The bootstrap script creates it."
  type        = string
}

variable "name_prefix" {
  description = "Short lowercase prefix used in Azure resource names."
  type        = string
  default     = "ghazdemo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.name_prefix))
    error_message = "name_prefix must be 3-12 lowercase alphanumeric characters and start with a letter."
  }
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.environment)
    error_message = "environment must be dev, test, stage, or prod."
  }
}

variable "vm_size" {
  description = "NVMe-capable Gen2 Linux VM size. It must be available in the lab resource group's region and within the subscription's Compute quota."
  type        = string
  default     = "Standard_F1als_v7"
}

variable "enable_private_dns_resolver" {
  description = "Create Azure DNS Private Resolver inbound/outbound endpoints. Disabled by default because both endpoints are continuously billed."
  type        = bool
  default     = false
}

variable "forwarding_rule_domain" {
  description = "Optional DNS suffix to forward through the resolver, including a trailing dot, for example corp.example.com."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.forwarding_rule_domain == null || endswith(var.forwarding_rule_domain, ".")
    error_message = "forwarding_rule_domain must end in a dot."
  }
}

variable "forwarding_target_ips" {
  description = "Optional on-premises/custom DNS server IP addresses for the forwarding rule."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for address in var.forwarding_target_ips : can(cidrhost("${address}/32", 0))])
    error_message = "Every forwarding_target_ips item must be an IPv4 address."
  }
}

variable "tags" {
  description = "Additional Azure tags."
  type        = map(string)
  default     = {}
}
