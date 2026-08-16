resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = var.service_plan_id

  https_only                                     = true
  public_network_access_enabled                  = false
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  # Private Endpoint is inbound-only. This separate VNet integration is what
  # lets the web app reach the Storage Private Endpoint outbound.
  virtual_network_subnet_id = var.vnet_integration_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = false
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    vnet_route_all_enabled = false

    application_stack {
      # A public image makes the infrastructure lab display a real page without
      # first introducing a registry and private build/deployment path.
      docker_image_name   = "library/nginx:1.27-alpine"
      docker_registry_url = "https://index.docker.io"
    }
  }

  app_settings = {
    WEBSITES_PORT        = "80"
    DEMO_ACCESS_LEVEL    = var.access_level
    STORAGE_ACCOUNT_NAME = var.storage_account_name
  }

  tags = merge(var.tags, { access-level = var.access_level })
}

