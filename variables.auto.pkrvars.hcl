# Image index
# 1 = Windows 10 IoT Enterprise LTSC
# 2 = Windows 10 IoT Enterprise LTSC with Desktop Experience
image_index = {
  "core"    = 1
  "desktop" = 2
}

node        = "pve"
proxmox_url = "https://172.16.50.11:8006/api2/json"

windows_iso        = "local:iso/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
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

winrm_user = "Administrator"
