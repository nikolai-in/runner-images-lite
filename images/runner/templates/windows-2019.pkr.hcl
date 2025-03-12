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

variable "agent_tools_directory" {
  type    = string
  default = "C:\\hostedtoolcache\\windows"
}

variable "image_folder" {
  type    = string
  default = "C:\\image"
}

variable "image_os" {
  type    = string
  default = "win19"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "imagedata_file" {
  type    = string
  default = "C:\\imagedata.json"
}

variable "temp_dir" {
  type    = string
  default = "C:\\temp"
}

variable "winrm_password" {
  type      = string
  default   = "Administrator"
  sensitive = true
}

variable "winrm_user" {
  type    = string
  default = "Administrator"
}

variable "helper_script_folder" {
  type    = string
  default = "C:\\Program Files\\WindowsPowerShell\\Modules\\"
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox Server URL"
}

variable "proxmox_password" {
  type        = string
  description = "Proxmox password"
  sensitive   = true
}

variable "proxmox_user" {
  type        = string
  description = "Proxmox username"
  sensitive   = true
}

variable "node" {
  type        = string
  description = "Proxmox cluster node"
}

variable "clone_vm_id" {
  type        = number
  description = "ID of the vm to clone"
}

variable "memory" {
  type        = number
  description = "VM memory in MB"
}

variable "cores" {
  type        = number
  description = "Amount of CPU cores"
}

variable "socket" {
  type        = number
  description = "Amount of CPU sockets"
}

variable "vlan" {
  type        = number
  description = "Network VLAN Tag (optional, set to -1 to disable VLAN tagging)"
  default     = -1
  validation {
    condition     = var.vlan == -1 || (var.vlan >= 1 && var.vlan <= 4094)
    error_message = "VLAN tag must be -1 (for no tagging) or between 1 and 4094."
  }
}

variable "bridge" {
  type        = string
  description = "Network bridge name"
}

source "proxmox-clone" "windows2019" {
  clone_vm_id          = var.clone_vm_id
  template_name        = "runner-win2019-${formatdate("YYYY-MM-DD", timestamp())}"
  template_description = "Created on: ${timestamp()}"
  vm_name              = "building-runner-win2019-${formatdate("YYYY-MM-DD", timestamp())}"
  full_clone           = false

  # Proxmox Host Conection
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.node

  memory          = var.memory
  cores           = var.cores
  sockets         = var.socket
  cpu_type        = "host"
  os              = "win10"
  boot            = "order=scsi0"
  scsi_controller = "virtio-scsi-pci"


  # Network
  network_adapters {
    model    = "virtio"
    bridge   = var.bridge
    vlan_tag = var.vlan >= 1 ? var.vlan : null
  }
  communicator   = "winrm"
  winrm_username = var.winrm_user
  winrm_password = var.winrm_password
  winrm_timeout  = "90m"
  winrm_port     = "5986"
  winrm_use_ssl  = true
  winrm_insecure = true
}

build {
  name    = "Proxmox Build"
  sources = ["source.proxmox-clone.windows2019"]

  provisioner "powershell" {
    inline = [
      "New-Item -Path ${var.image_folder} -ItemType Directory -Force",
      "New-Item -Path ${var.temp_dir} -ItemType Directory -Force"
    ]
  }

  provisioner "file" {
    destination = "${var.image_folder}\\"
    sources = [
      "${path.root}/../assets",
      "${path.root}/../scripts",
      "${path.root}/../toolsets"
    ]
  }

  provisioner "powershell" {
    inline = [
      "Move-Item '${var.image_folder}\\assets\\post-gen' 'C:\\post-generation'",
      "Remove-Item -Recurse '${var.image_folder}\\assets'",
      "Move-Item '${var.image_folder}\\scripts\\helpers' '${var.helper_script_folder}\\ImageHelpers'",
      "New-Item -Type Directory -Path '${var.helper_script_folder}\\TestsHelpers\\'",
      "Move-Item '${var.image_folder}\\scripts\\tests\\Helpers.psm1' '${var.helper_script_folder}\\TestsHelpers\\TestsHelpers.psm1'",
      "Move-Item '${var.image_folder}\\scripts\\tests' '${var.image_folder}\\tests'",
      "Remove-Item -Recurse '${var.image_folder}\\scripts'",
      "Move-Item '${var.image_folder}\\toolsets\\toolset-2019.json' '${var.image_folder}\\toolset.json'",
      "Remove-Item -Recurse '${var.image_folder}\\toolsets'"
    ]
  }

  provisioner "windows-shell" {
    inline = [
      "net user ${var.winrm_user} ${var.winrm_password} /add /passwordchg:no /passwordreq:yes /active:yes /Y",
      "net localgroup Administrators ${var.winrm_user} /add",
      "winrm set winrm/config/service/auth @{Basic=\"true\"}",
      "winrm get winrm/config/service/auth"
    ]
  }

  provisioner "powershell" {
    inline = ["if (-not ((net localgroup Administrators) -contains '${var.winrm_user}')) { exit 1 }"]
  }

  provisioner "powershell" {
    elevated_password = "${var.winrm_password}"
    elevated_user     = "${var.winrm_user}"
    inline            = ["bcdedit.exe /set TESTSIGNING ON"]
  }

  provisioner "powershell" {
    elevated_password = "${var.winrm_password}"
    elevated_user     = "${var.winrm_user}"
    scripts           = ["${path.root}/../scripts/build/Install-NET48.ps1"]
    valid_exit_codes  = [0, 3010]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "AGENT_TOOLSDIRECTORY=${var.agent_tools_directory}", "IMAGEDATA_FILE=${var.imagedata_file}", "IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    execution_policy = "unrestricted"
    scripts = [
      "${path.root}/../scripts/build/Configure-WindowsDefender.ps1",
      "${path.root}/../scripts/build/Configure-PowerShell.ps1",
      "${path.root}/../scripts/build/Install-PowerShellModules.ps1",
      "${path.root}/../scripts/build/Install-WindowsFeatures.ps1",
      "${path.root}/../scripts/build/Install-Chocolatey.ps1",
      "${path.root}/../scripts/build/Configure-BaseImage.ps1",
      "${path.root}/../scripts/build/Configure-ImageDataFile.ps1",
      "${path.root}/../scripts/build/Configure-SystemEnvironment.ps1",
      "${path.root}/../scripts/build/Configure-DotnetSecureChannel.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    inline = ["Set-Service -Name wlansvc -StartupType Manual", "if ($(Get-Service -Name wlansvc).Status -eq 'Running') { Stop-Service -Name wlansvc}"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/../scripts/build/Install-VCRedist.ps1",
      "${path.root}/../scripts/build/Install-Docker.ps1",
      "${path.root}/../scripts/build/Install-DockerWinCred.ps1",
      "${path.root}/../scripts/build/Install-DockerCompose.ps1",
      "${path.root}/../scripts/build/Install-PowershellCore.ps1",
      "${path.root}/../scripts/build/Install-WebPlatformInstaller.ps1",
      "${path.root}/../scripts/build/Install-Runner.ps1",
      "${path.root}/../scripts/build/Install-TortoiseSvn.ps1"
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
      "${path.root}/../scripts/build/Install-VisualStudio.ps1",
      "${path.root}/../scripts/build/Install-KubernetesTools.ps1",
      "${path.root}/../scripts/build/Install-NET48-devpack.ps1"
    ]
    valid_exit_codes = [0, 3010]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/../scripts/build/Install-Wix.ps1",
      "${path.root}/../scripts/build/Install-WDK.ps1",
      "${path.root}/../scripts/build/Install-VSExtensions.ps1",
      # "${path.root}/../scripts/build/Install-AzureCli.ps1",
      # "${path.root}/../scripts/build/Install-AzureDevOpsCli.ps1",
      "${path.root}/../scripts/build/Install-ChocolateyPackages.ps1",
      "${path.root}/../scripts/build/Install-JavaTools.ps1",
      "${path.root}/../scripts/build/Install-Kotlin.ps1",
      "${path.root}/../scripts/build/Install-OpenSSL.ps1"
    ]
  }

  provisioner "powershell" {
    execution_policy = "remotesigned"
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts          = ["${path.root}/../scripts/build/Install-ServiceFabricSDK.ps1"]
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
      "${path.root}/../scripts/build/Install-ActionsCache.ps1",
      "${path.root}/../scripts/build/Install-Ruby.ps1",
      "${path.root}/../scripts/build/Install-PyPy.ps1",
      "${path.root}/../scripts/build/Install-Toolset.ps1",
      "${path.root}/../scripts/build/Configure-Toolset.ps1",
      "${path.root}/../scripts/build/Install-NodeJS.ps1",
      "${path.root}/../scripts/build/Install-AndroidSDK.ps1",
      "${path.root}/../scripts/build/Install-PowershellAzModules.ps1",
      "${path.root}/../scripts/build/Install-Pipx.ps1",
      "${path.root}/../scripts/build/Install-Git.ps1",
      "${path.root}/../scripts/build/Install-GitHub-CLI.ps1",
      "${path.root}/../scripts/build/Install-PHP.ps1",
      "${path.root}/../scripts/build/Install-Rust.ps1",
      "${path.root}/../scripts/build/Install-Sbt.ps1",
      "${path.root}/../scripts/build/Install-Chrome.ps1",
      "${path.root}/../scripts/build/Install-EdgeDriver.ps1",
      "${path.root}/../scripts/build/Install-Firefox.ps1",
      "${path.root}/../scripts/build/Install-Selenium.ps1",
      "${path.root}/../scripts/build/Install-IEWebDriver.ps1",
      "${path.root}/../scripts/build/Install-Apache.ps1",
      "${path.root}/../scripts/build/Install-Nginx.ps1",
      "${path.root}/../scripts/build/Install-Msys2.ps1",
      "${path.root}/../scripts/build/Install-WinAppDriver.ps1",
      "${path.root}/../scripts/build/Install-R.ps1",
      "${path.root}/../scripts/build/Install-AWSTools.ps1",
      "${path.root}/../scripts/build/Install-DACFx.ps1",
      "${path.root}/../scripts/build/Install-MysqlCli.ps1",
      "${path.root}/../scripts/build/Install-SQLPowerShellTools.ps1",
      "${path.root}/../scripts/build/Install-SQLOLEDBDriver.ps1",
      "${path.root}/../scripts/build/Install-DotnetSDK.ps1",
      "${path.root}/../scripts/build/Install-Mingw64.ps1",
      "${path.root}/../scripts/build/Install-Haskell.ps1",
      "${path.root}/../scripts/build/Install-Stack.ps1",
      "${path.root}/../scripts/build/Install-Miniconda.ps1",
      "${path.root}/../scripts/build/Install-AzureCosmosDbEmulator.ps1",
      "${path.root}/../scripts/build/Install-Mercurial.ps1",
      "${path.root}/../scripts/build/Install-Zstd.ps1",
      "${path.root}/../scripts/build/Install-NSIS.ps1",
      "${path.root}/../scripts/build/Install-CloudFoundryCli.ps1",
      "${path.root}/../scripts/build/Install-Vcpkg.ps1",
      "${path.root}/../scripts/build/Install-PostgreSQL.ps1",
      "${path.root}/../scripts/build/Install-Bazel.ps1",
      "${path.root}/../scripts/build/Install-AliyunCli.ps1",
      "${path.root}/../scripts/build/Install-RootCA.ps1",
      "${path.root}/../scripts/build/Install-MongoDB.ps1",
      "${path.root}/../scripts/build/Install-GoogleCloudCLI.ps1",
      "${path.root}/../scripts/build/Install-CodeQLBundle.ps1",
      "${path.root}/../scripts/build/Install-BizTalkBuildComponent.ps1",
      "${path.root}/../scripts/build/Configure-Diagnostics.ps1",
      "${path.root}/../scripts/build/Configure-DynamicPort.ps1",
      "${path.root}/../scripts/build/Configure-GDIProcessHandleQuota.ps1",
      "${path.root}/../scripts/build/Configure-Shell.ps1",
      "${path.root}/../scripts/build/Configure-DeveloperMode.ps1",
      "${path.root}/../scripts/build/Install-LLVM.ps1"
    ]
  }

  provisioner "windows-restart" {
    check_registry        = true
    restart_check_command = "powershell -command \"& {if ((-not (Get-Process TiWorker.exe -ErrorAction SilentlyContinue)) -and (-not [System.Environment]::HasShutdownStarted) ) { Write-Output 'Restart complete' }}\""
    restart_timeout       = "30m"
  }

  provisioner "powershell" {
    pause_before     = "2m0s"
    environment_vars = ["IMAGE_FOLDER=${var.image_folder}", "TEMP_DIR=${var.temp_dir}"]
    scripts = [
      "${path.root}/../scripts/build/Install-WindowsUpdatesAfterReboot.ps1",
      "${path.root}/../scripts/build/Invoke-Cleanup.ps1"
    ]
  }

  provisioner "powershell" {
    environment_vars = ["winrm_user=${var.winrm_user}"]
    scripts = [
      "${path.root}/../scripts/build/Install-NativeImages.ps1",
      "${path.root}/../scripts/build/Configure-System.ps1",
      "${path.root}/../scripts/build/Configure-User.ps1"
    ]
    skip_clean = true
  }

  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
    filters = [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
    update_limit = 25
  }
}