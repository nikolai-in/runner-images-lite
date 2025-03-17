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

variable "winrm_password" {
  type        = string
  description = "Windows Remote Management password"
  sensitive   = true
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox Server URL"
}

variable "node" {
  type        = string
  description = "Proxmox cluster node"
}

variable "windows_iso" {
  type        = string
  description = "Location of ISO file in the Proxmox environment"
}

variable "iso_storage" {
  type        = string
  description = "Proxmox storage location for additional iso files"
}

variable "efi_storage" {
  type        = string
  description = "Location of EFI storage on proxmox host"
}

variable "cloud_init_storage" {
  type        = string
  description = "Loaction of cloud-init files/iso/yaml config"
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

variable "disk_storage" {
  type        = string
  description = "Disk storage location"
}

variable "disk_size_gb" {
  type        = string
  description = " Disk size including GB so <size>GB"
}

variable "winrm_user" {
  type        = string
  description = "WinRM user"
}

variable "cdrom_drive" {
  type        = string
  description = "CD-ROM Driveletter for extra iso"
  default     = "D:"
}

variable "perform_windows_updates" {
  type        = bool
  default     = true
  description = "Whether to perform Windows updates during build"
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
  default = "win19" // keep this as win19 for now
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

variable "helper_script_folder" {
  type    = string
  default = "C:\\Program Files\\WindowsPowerShell\\Modules\\"
}