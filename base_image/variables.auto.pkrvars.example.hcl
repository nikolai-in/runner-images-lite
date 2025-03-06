# Image index
# 1 = Windows Core
# 2 = Windows Desktop
image_index = {
  "core"    = 1
  "desktop" = 2
}

node        = ""
proxmox_url = ""

windows_iso        = "local:iso/en-us_windows_server_2019_x64_dvd_f9475476.iso"
iso_storage        = "local"
efi_storage        = "local-lvm"
cloud_init_storage = "local-lvm"

cores  = 2
socket = 1
memory = 4096

vlan         = 30
bridge       = "vmbr0"
disk_storage = "local-lvm"
disk_size_gb = "60G"

winrm_user       = "Administrator"
winrm_password   = "SuperDuperPassword"
proxmox_user     = "pve"
proxmox_password = "123"