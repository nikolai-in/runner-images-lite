packer {
  required_plugins {
    windows-update = {
      version = "~> 0.14.3"
      source  = "github.com/rgl/windows-update"
    }
    proxmox = {
      version = "~> 1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}


source "proxmox-iso" "windows10iot" {

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
  boot    = "order=ide2;scsi0"

  efi_config {
    efi_storage_pool  = var.efi_storage
    pre_enrolled_keys = true
    efi_type          = "4m"
  }

  # Windows ISO File - Updated to use boot_iso block
  boot_iso {
    iso_file = var.windows_iso
    unmount  = true
  }

  additional_iso_files {
    cd_files = ["./build_files/drivers/*", "./build_files/scripts/ConfigureRemotingForAnsible.ps1", "./build_files/software/virtio-win-guest-tools.exe"]
    cd_content = {
      "autounattend.xml" = templatefile("./build_files/templates/unattend.pkrtpl", { password = var.winrm_password, cdrom_drive = var.cdrom_drive })
    }
    cd_label         = "Unattend"
    iso_storage_pool = var.iso_storage
    unmount          = true
    type             = "sata"
    index            = 0
  }

  template_name           = "templ-win10iot-${var.template}"
  template_description    = "Created on: ${timestamp()}"
  vm_name                 = "win10iot-${var.template}"
  memory                  = var.memory
  cores                   = var.cores
  sockets                 = var.socket
  cpu_type                = "host"
  os                      = "win10"
  scsi_controller         = "virtio-scsi-pci"
  cloud_init              = false
  cloud_init_storage_pool = var.cloud_init_storage

  # Network
  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  # Storage
  disks {
    storage_pool = var.disk_storage
    # storage_pool_type = "btrfs"
    type       = "scsi"
    disk_size  = var.disk_size_gb
    cache_mode = "writeback"
    format     = "raw"
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
  boot_wait = "4s"
  boot_command = [
    "<enter><wait><enter>"
  ]

}

build {
  name    = "Proxmox Build"
  sources = ["source.proxmox-iso.windows10iot"]

  # First restart to make sure we're fully booted
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # Enable Administrator account immediately via both methods
  provisioner "powershell" {
    inline = [
      "net user Administrator /active:yes",
      "Write-Host 'Administrator account enabled via net user command'"
    ]
    pause_before = "1m"
  }

  # Run our dedicated script for enabling Administrator
  provisioner "powershell" {
    script = "./build_files/scripts/EnableAdmin.ps1"
  }

  # Restart to ensure account settings are applied
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # Check if Administrator is enabled before proceeding
  provisioner "powershell" {
    inline = [
      "if ((([ADSI]'WinNT://./Administrator').Properties['UserFlags'].Value -band 0x2) -ne 0) {",
      "    Write-Host 'ERROR: Administrator account is still disabled!'",
      "    exit 1",
      "} else {",
      "    Write-Host 'SUCCESS: Administrator account is enabled.'",
      "}"
    ]
  }

  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
    update_limit = 25
  }

  provisioner "powershell" {
    script       = "./build_files/scripts/InstallCloudBase.ps1"
    pause_before = "1m"
  }

  provisioner "file" {
    source      = "./build_files/config/"
    destination = "C://Program Files//Cloudbase Solutions//Cloudbase-Init//conf"
  }

  # Make sure Administrator is still enabled after CloudBase-Init installation
  provisioner "powershell" {
    inline = [
      "net user Administrator /active:yes",
      "Write-Host 'Administrator account re-enabled'"
    ]
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
