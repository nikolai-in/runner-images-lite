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
      "autounattend.xml" = templatefile("./assets/templates/unattend.pkrtpl", { password = var.winrm_password, cdrom_drive = var.cdrom_drive, index = lookup(var.image_index, var.template, "core") })
    }
    cd_label         = "Unattend"
    iso_storage_pool = var.iso_storage
    unmount          = true
    type             = "sata"
    index            = 0
  }

  template_name           = "templ-win22-runner-${var.template}"
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

  // Try to fix some warnings
  provisioner "powershell" {
    elevated_password = "${var.winrm_password}"
    elevated_user     = "${var.winrm_user}"
    inline = [
      "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force",
      "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force",
      "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force",
      "$ProfileDir = Split-Path $PROFILE -Parent",
      "if (-not (Test-Path $ProfileDir)) { New-Item -Path $ProfileDir -ItemType Directory -Force }",
      "if (Test-Path $PROFILE) { Remove-Item -Path $PROFILE -Force }",
      "Set-Content -Path $PROFILE -Value '# PowerShell Profile' -Force",
      "Write-Output 'PowerShell profile has been created with execution policy set to RemoteSigned'"
    ]
  }

  // Begin runner template
  provisioner "powershell" {
    inline = [
      "New-Item -Path ${var.image_folder} -ItemType Directory -Force",
      "New-Item -Path ${var.temp_dir} -ItemType Directory -Force",
      "# Clean up any existing files from previous runs",
      "if (Test-Path '${var.image_folder}\\assets') { Remove-Item -Recurse -Force '${var.image_folder}\\assets' }",
      "if (Test-Path '${var.image_folder}\\scripts') { Remove-Item -Recurse -Force '${var.image_folder}\\scripts' }",
      "if (Test-Path '${var.image_folder}\\toolsets') { Remove-Item -Recurse -Force '${var.image_folder}\\toolsets' }"
    ]
  }

  provisioner "file" {
    destination = "${var.image_folder}\\"
    sources = [
      "${path.root}/assets/assets",
      "${path.root}/assets/scripts",
      "${path.root}/assets/toolsets"
    ]
  }

  provisioner "powershell" {
    inline = [
      "# Handle post-gen directory",
      "if (Test-Path 'C:\\post-generation') { Remove-Item -Recurse -Force 'C:\\post-generation' }",
      "if (Test-Path '${var.image_folder}\\assets\\post-gen') { Move-Item -Force '${var.image_folder}\\assets\\post-gen' 'C:\\post-generation' }",

      "# Clean up assets directory",
      "if (Test-Path '${var.image_folder}\\assets') { Remove-Item -Recurse -Force '${var.image_folder}\\assets' }",

      "# Handle SoftwareReport directory",
      "if (Test-Path '${var.image_folder}\\SoftwareReport') { Remove-Item -Recurse -Force '${var.image_folder}\\SoftwareReport' }",
      "if (Test-Path '${var.image_folder}\\scripts\\docs-gen') { Move-Item -Force '${var.image_folder}\\scripts\\docs-gen' '${var.image_folder}\\SoftwareReport' }",

      "# Handle ImageHelpers directory",
      "if (Test-Path '${var.helper_script_folder}\\ImageHelpers') { Remove-Item -Recurse -Force '${var.helper_script_folder}\\ImageHelpers' }",
      "if (Test-Path '${var.image_folder}\\scripts\\helpers') { Move-Item -Force '${var.image_folder}\\scripts\\helpers' '${var.helper_script_folder}\\ImageHelpers' }",

      "# Handle TestsHelpers directory",
      "New-Item -Type Directory -Path '${var.helper_script_folder}\\TestsHelpers\\' -Force",
      "if (Test-Path '${var.image_folder}\\scripts\\tests\\Helpers.psm1') { Move-Item -Force '${var.image_folder}\\scripts\\tests\\Helpers.psm1' '${var.helper_script_folder}\\TestsHelpers\\TestsHelpers.psm1' }",

      "# Handle tests directory",
      "if (Test-Path '${var.image_folder}\\tests') { Remove-Item -Recurse -Force '${var.image_folder}\\tests' }",
      "if (Test-Path '${var.image_folder}\\scripts\\tests') { Move-Item -Force '${var.image_folder}\\scripts\\tests' '${var.image_folder}\\tests' }",

      "# Clean up scripts directory",
      "if (Test-Path '${var.image_folder}\\scripts') { Remove-Item -Recurse -Force '${var.image_folder}\\scripts' }",

      "# Handle toolset.json",
      "if (Test-Path '${var.image_folder}\\toolset.json') { Remove-Item -Force '${var.image_folder}\\toolset.json' }",
      "if (Test-Path '${var.image_folder}\\toolsets\\toolset-2022.json') { Move-Item -Force '${var.image_folder}\\toolsets\\toolset-2022.json' '${var.image_folder}\\toolset.json' }",

      "# Clean up toolsets directory",
      "if (Test-Path '${var.image_folder}\\toolsets') { Remove-Item -Recurse -Force '${var.image_folder}\\toolsets' }"
    ]
  }

  provisioner "powershell" {
    inline = ["if (-not ((net localgroup Administrators) -contains '${var.winrm_user}')) { exit 1 }"]
  }

  provisioner "powershell" {
    elevated_password = "${var.winrm_password}"
    elevated_user     = "${var.winrm_user}"
    scripts           = ["${path.root}/assets/scripts/build/Install-NET48.ps1"]
    valid_exit_codes  = [0, 3010]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "AGENT_TOOLSDIRECTORY=${var.agent_tools_directory}", "IMAGEDATA_FILE=${var.imagedata_file}", "IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    execution_policy = "unrestricted"
    scripts = [
      "${path.root}/assets/scripts/build/Configure-WindowsDefender.ps1",
      "${path.root}/assets/scripts/build/Configure-PowerShell.ps1",
      "${path.root}/assets/scripts/build/Install-PowerShellModules.ps1",
      "${path.root}/assets/scripts/build/Install-WindowsFeatures.ps1",
      "${path.root}/assets/scripts/build/Install-Chocolatey.ps1",
      "${path.root}/assets/scripts/build/Configure-BaseImage.ps1",
      "${path.root}/assets/scripts/build/Configure-ImageDataFile.ps1",
      "${path.root}/assets/scripts/build/Configure-SystemEnvironment.ps1",
      "${path.root}/assets/scripts/build/Configure-DotnetSecureChannel.ps1"
    ]
  }

  provisioner "windows-restart" {
    check_registry        = true
    restart_check_command = "powershell -command \"& {while ( (Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue).State -ne 'Enabled' ) { Start-Sleep 30; Write-Output 'InProgress' }}\""
    restart_timeout       = "10m"
  }

  provisioner "powershell" {
    inline = ["Set-Service -Name wlansvc -StartupType Manual", "if ($(Get-Service -Name wlansvc).Status -eq 'Running') { Stop-Service -Name wlansvc}"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-Docker.ps1",
      "${path.root}/assets/scripts/build/Install-DockerWinCred.ps1",
      "${path.root}/assets/scripts/build/Install-DockerCompose.ps1",
      "${path.root}/assets/scripts/build/Install-PowershellCore.ps1",
      "${path.root}/assets/scripts/build/Install-WebPlatformInstaller.ps1",
      "${path.root}/assets/scripts/build/Install-Runner.ps1",
      "${path.root}/assets/scripts/build/Install-TortoiseSvn.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "powershell" {
    elevated_password = "${var.winrm_password}"
    elevated_user     = "${var.winrm_user}"
    environment_vars  = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-VisualStudio.ps1",
      "${path.root}/assets/scripts/build/Install-KubernetesTools.ps1",
    ]
    valid_exit_codes = [0, 1603, 3010]
  }

  provisioner "windows-restart" {
    check_registry  = true
    restart_timeout = "10m"
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-Wix.ps1",
      "${path.root}/assets/scripts/build/Install-WDK.ps1",
      "${path.root}/assets/scripts/build/Install-VSExtensions.ps1",
      # "${path.root}/assets/scripts/build/Install-AzureCli.ps1",
      # "${path.root}/assets/scripts/build/Install-AzureDevOpsCli.ps1",
      "${path.root}/assets/scripts/build/Install-ChocolateyPackages.ps1",
      "${path.root}/assets/scripts/build/Install-JavaTools.ps1",
      "${path.root}/assets/scripts/build/Install-Kotlin.ps1",
      "${path.root}/assets/scripts/build/Install-OpenSSL.ps1"
    ]
    valid_exit_codes = [0, 1603, 3010]
  }

  provisioner "powershell" {
    execution_policy = "remotesigned"
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts          = ["${path.root}/assets/scripts/build/Install-ServiceFabricSDK.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "windows-shell" {
    inline = ["wmic product where \"name like '%%microsoft azure powershell%%'\" call uninstall /nointeractive"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-ActionsCache.ps1",
      "${path.root}/assets/scripts/build/Install-Ruby.ps1",
      "${path.root}/assets/scripts/build/Install-PyPy.ps1",
      "${path.root}/assets/scripts/build/Install-Toolset.ps1",
      "${path.root}/assets/scripts/build/Configure-Toolset.ps1",
      "${path.root}/assets/scripts/build/Install-NodeJS.ps1",
      "${path.root}/assets/scripts/build/Install-AndroidSDK.ps1",
      "${path.root}/assets/scripts/build/Install-PowershellAzModules.ps1",
      "${path.root}/assets/scripts/build/Install-Pipx.ps1",
      "${path.root}/assets/scripts/build/Install-Git.ps1",
      "${path.root}/assets/scripts/build/Install-GitHub-CLI.ps1",
      "${path.root}/assets/scripts/build/Install-PHP.ps1",
      "${path.root}/assets/scripts/build/Install-Rust.ps1",
      "${path.root}/assets/scripts/build/Install-Sbt.ps1",
      "${path.root}/assets/scripts/build/Install-Chrome.ps1",
      "${path.root}/assets/scripts/build/Install-EdgeDriver.ps1",
      "${path.root}/assets/scripts/build/Install-Firefox.ps1",
      "${path.root}/assets/scripts/build/Install-Selenium.ps1",
      "${path.root}/assets/scripts/build/Install-IEWebDriver.ps1",
      "${path.root}/assets/scripts/build/Install-Apache.ps1",
      "${path.root}/assets/scripts/build/Install-Nginx.ps1",
      "${path.root}/assets/scripts/build/Install-Msys2.ps1",
      "${path.root}/assets/scripts/build/Install-WinAppDriver.ps1",
      "${path.root}/assets/scripts/build/Install-R.ps1",
      # "${path.root}/assets/scripts/build/Install-AWSTools.ps1",
      "${path.root}/assets/scripts/build/Install-DACFx.ps1",
      "${path.root}/assets/scripts/build/Install-MysqlCli.ps1",
      "${path.root}/assets/scripts/build/Install-SQLPowerShellTools.ps1",
      "${path.root}/assets/scripts/build/Install-SQLOLEDBDriver.ps1",
      "${path.root}/assets/scripts/build/Install-DotnetSDK.ps1",
      "${path.root}/assets/scripts/build/Install-Mingw64.ps1",
      "${path.root}/assets/scripts/build/Install-Haskell.ps1",
      "${path.root}/assets/scripts/build/Install-Stack.ps1",
      "${path.root}/assets/scripts/build/Install-Miniconda.ps1",
      # "${path.root}/assets/scripts/build/Install-AzureCosmosDbEmulator.ps1",
      "${path.root}/assets/scripts/build/Install-Mercurial.ps1",
      "${path.root}/assets/scripts/build/Install-Zstd.ps1",
      "${path.root}/assets/scripts/build/Install-NSIS.ps1",
      "${path.root}/assets/scripts/build/Install-Vcpkg.ps1",
      "${path.root}/assets/scripts/build/Install-PostgreSQL.ps1",
      "${path.root}/assets/scripts/build/Install-Bazel.ps1",
      # "${path.root}/assets/scripts/build/Install-AliyunCli.ps1",
      "${path.root}/assets/scripts/build/Install-RootCA.ps1",
      # "${path.root}/assets/scripts/build/Install-MongoDB.ps1",
      # "${path.root}/assets/scripts/build/Install-GoogleCloudCLI.ps1",
      "${path.root}/assets/scripts/build/Install-CodeQLBundle.ps1",
      "${path.root}/assets/scripts/build/Install-BizTalkBuildComponent.ps1",
      "${path.root}/assets/scripts/build/Configure-Diagnostics.ps1",
      "${path.root}/assets/scripts/build/Configure-DynamicPort.ps1",
      "${path.root}/assets/scripts/build/Configure-GDIProcessHandleQuota.ps1",
      "${path.root}/assets/scripts/build/Configure-Shell.ps1",
      "${path.root}/assets/scripts/build/Configure-DeveloperMode.ps1",
      "${path.root}/assets/scripts/build/Install-LLVM.ps1"
    ]
  }

  provisioner "windows-restart" {
    check_registry        = true
    restart_check_command = "powershell -command \"& {if ((-not (Get-Process TiWorker.exe -ErrorAction SilentlyContinue)) -and (-not [System.Environment]::HasShutdownStarted) ) { Write-Output 'Restart complete' }}\""
    restart_timeout       = "30m"
  }

  // Final provisioning steps - you can add the optional test scripts if needed
  provisioner "powershell" {
    pause_before     = "2m0s"
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-WindowsUpdatesAfterReboot.ps1",
      "${path.root}/assets/scripts/build/Invoke-Cleanup.ps1"
    ]
  }

  provisioner "powershell" {
    environment_vars = ["winrm_user=${var.winrm_user}"]
    scripts = [
      "${path.root}/assets/scripts/build/Install-NativeImages.ps1",
      "${path.root}/assets/scripts/build/Configure-System.ps1",
      "${path.root}/assets/scripts/build/Configure-User.ps1"
    ]
    skip_clean = true
  }

  // Finalize the image
  provisioner "powershell" {
    inline = [
      "Set-Location -Path \"C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\conf\"",
      "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /unattend:unattend.xml"
    ]
  }

}