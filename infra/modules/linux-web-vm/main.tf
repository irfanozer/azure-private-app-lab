resource "random_password" "admin" {
  length           = 32
  special          = true
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "_%@!"
}

resource "azurerm_public_ip" "this" {
  name                = "pip-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  ip_version          = "IPv4"
  tags                = var.tags
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # This is a deliberately public demo page. SSH is not exposed; the default
  # NSG deny rule blocks all other unsolicited Internet traffic.
  security_rule {
    name                       = "allow-http-from-internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                 = var.name
  computer_name        = "webvm"
  resource_group_name  = var.resource_group_name
  location             = var.location
  size                 = var.size
  disk_controller_type = "NVMe"

  admin_username                  = "azureadmin"
  admin_password                  = random_password.admin.result
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.this.id]

  # Password authentication satisfies the Azure provisioning requirement, but
  # no NSG rule exposes SSH. Use Azure Run Command for this disposable lab.
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    vm_name              = var.name
    storage_account_name = var.storage_account_name
  }))

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  secure_boot_enabled = true
  vtpm_enabled        = true

  boot_diagnostics {}

  tags = merge(var.tags, { access-level = "read-write" })

  depends_on = [azurerm_network_interface_security_group_association.this]
}
