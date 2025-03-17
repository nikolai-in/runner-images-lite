packer {
  required_plugins {
    windows-update = {
      version = "~> 0.16.9"
      source  = "github.com/rgl/windows-update"
    }
    proxmox = {
      version = "~> 1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "windows" {

  # Proxmox Host Connection
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.node

  # BIOS - UEFI
  bios = "ovmf"

  # Machine type
  # Q35 less resource overhead and newer chipset
  machine = "q35"

  efi_config {
    efi_storage_pool  = var.efi_storage
    pre_enrolled_keys = true
    efi_type          = "4m"
  }

  boot_iso {
    iso_file         = var.windows_iso
    iso_storage_pool = var.iso_storage
    unmount          = true
  }

  additional_iso_files {
    cd_files = ["./assets/drivers/*", "./assets/scripts/ConfigureRemotingForAnsible.ps1", "./assets/software/virtio-win-guest-tools.exe"]
    cd_content = {
      "autounattend.xml" = templatefile("./assets/templates/unattend.pkrtpl", { password = var.winrm_password, cdrom_drive = var.cdrom_drive })
    }
    cd_label         = "Unattend"
    iso_storage_pool = var.iso_storage
    unmount          = true
    type             = "sata"
    index            = 0
  }

  template_name           = "templ-win-runner"
  template_description    = "Created on: ${timestamp()}"
  vm_name                 = "win-runner"
  memory                  = var.memory
  cores                   = var.cores
  sockets                 = var.socket
  cpu_type                = "host"
  os                      = "win10"
  scsi_controller         = "virtio-scsi-pci"
  cloud_init              = true
  cloud_init_storage_pool = var.cloud_init_storage
  serials                 = ["socket"]

  # Network
  network_adapters {
    model    = "virtio"
    bridge   = var.bridge
    vlan_tag = var.vlan >= 1 ? var.vlan : null
  }

  # Storage
  disks {
    storage_pool = var.disk_storage
    type         = "scsi"
    disk_size    = var.disk_size_gb
    cache_mode   = "writeback"
    format       = "raw"
  }

  # WinRM
  communicator   = "winrm"
  winrm_username = var.winrm_user
  winrm_password = var.winrm_password
  winrm_timeout  = "1h"
  winrm_port     = "5986"
  winrm_use_ssl  = true
  winrm_insecure = true

  # Boot
  boot      = "order=scsi0"
  boot_wait = "3s"
  boot_command = [
    "<enter><wait><enter>",
  ]

}

build {
  name    = "Proxmox Build"
  sources = ["source.proxmox-iso.windows"]

  provisioner "windows-restart" {
  }

  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
    # This will only run when perform_windows_updates is true
    only = var.perform_windows_updates ? ["proxmox-iso.windows"] : [""]
  }

  provisioner "powershell" {
    script       = "./assets/scripts/InstallCloudBase.ps1"
    pause_before = "1m"
  }

  provisioner "file" {
    source      = "./assets/config/"
    destination = "C://Program Files//Cloudbase Solutions//Cloudbase-Init//conf"
  }

  provisioner "powershell" {
    inline = [
      "Set-Service cloudbase-init -StartupType Manual",
      "Stop-Service cloudbase-init -Force -Confirm:$false"
    ]
  }

  provisioner "powershell" {
    inline = [
      "Set-Location -Path \"C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\conf\"",
      "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /unattend:unattend.xml"
    ]
  }

}