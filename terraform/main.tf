# ============================================================
# main.tf
# Lab 1 — Active Directory Complete Deployment
# Deploys: Domain Controller + client01 on same VNet
# Region: East US
# ============================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "azurerm" {
  features {}
}

variable "admin_username" {
  type    = string
  default = "vm-ADDS-lab"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "location" {
  type    = string
  default = "East US"
}

variable "dc_resource_group" {
  type    = string
  default = "vm-ADDS-lab_group"
}

variable "client_resource_group" {
  type    = string
  default = "client01_group"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "domain_name" {
  type    = string
  default = "lab.local"
}

variable "domain_admin_password" {
  type      = string
  sensitive = true
}

resource "azurerm_resource_group" "dc_rg" {
  name     = var.dc_resource_group
  location = var.location
  tags     = { environment = "lab", role = "domain-controller" }
}

resource "azurerm_resource_group" "client_rg" {
  name     = var.client_resource_group
  location = var.location
  tags     = { environment = "lab", role = "client" }
}

resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vm-ADDS-lab-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.dc_rg.location
  resource_group_name = azurerm_resource_group.dc_rg.name
  tags                = { environment = "lab" }
}

resource "azurerm_subnet" "lab_subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.dc_rg.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_network_security_group" "lab_nsg" {
  name                = "vm-ADDS-lab-nsg"
  location            = azurerm_resource_group.dc_rg.location
  resource_group_name = azurerm_resource_group.dc_rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Internal"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "*"
  }

  tags = { environment = "lab" }
}

resource "azurerm_subnet_network_security_group_association" "lab_nsg_assoc" {
  subnet_id                 = azurerm_subnet.lab_subnet.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}

resource "azurerm_public_ip" "dc_pip" {
  name                = "vm-ADDS-lab-pip"
  location            = azurerm_resource_group.dc_rg.location
  resource_group_name = azurerm_resource_group.dc_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = { environment = "lab", role = "domain-controller" }
}

resource "azurerm_network_interface" "dc_nic" {
  name                = "vm-ADDS-lab-nic"
  location            = azurerm_resource_group.dc_rg.location
  resource_group_name = azurerm_resource_group.dc_rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.0.4"
    public_ip_address_id          = azurerm_public_ip.dc_pip.id
  }

  tags = { environment = "lab", role = "domain-controller" }
}

resource "azurerm_network_interface_security_group_association" "dc_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.dc_nic.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                = "vm-ADDS-lab"
  resource_group_name = azurerm_resource_group.dc_rg.name
  location            = azurerm_resource_group.dc_rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.dc_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-g2"
    version   = "latest"
  }

  tags = { environment = "lab", role = "domain-controller" }
}

resource "azurerm_public_ip" "client_pip" {
  name                = "client01-ip"
  location            = azurerm_resource_group.client_rg.location
  resource_group_name = azurerm_resource_group.client_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = { environment = "lab", role = "client" }
}

resource "azurerm_network_interface" "client_nic" {
  name                = "client01-nic"
  location            = azurerm_resource_group.client_rg.location
  resource_group_name = azurerm_resource_group.client_rg.name
  dns_servers         = ["10.1.0.4"]

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client_pip.id
  }

  tags = { environment = "lab", role = "client" }
}

resource "azurerm_network_interface_security_group_association" "client_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.client_nic.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}

resource "azurerm_windows_virtual_machine" "client01" {
  name                = "client01"
  resource_group_name = azurerm_resource_group.client_rg.name
  location            = azurerm_resource_group.client_rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.client_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-g2"
    version   = "latest"
  }

  tags = { environment = "lab", role = "client" }

  depends_on = [azurerm_windows_virtual_machine.dc]
}

output "dc_public_ip" {
  description = "Public IP of the Domain Controller"
  value       = azurerm_public_ip.dc_pip.ip_address
}

output "client01_public_ip" {
  description = "Public IP of client01"
  value       = azurerm_public_ip.client_pip.ip_address
}

output "dc_private_ip" {
  description = "Private IP of DC — used for DNS on client01"
  value       = azurerm_network_interface.dc_nic.private_ip_address
}

output "rdp_dc" {
  description = "RDP command for Domain Controller"
  value       = "mstsc /v:${azurerm_public_ip.dc_pip.ip_address}"
}

output "rdp_client01" {
  description = "RDP command for client01"
  value       = "mstsc /v:${azurerm_public_ip.client_pip.ip_address}"
}
