variable "proxmox_password" {
  description = "Proxmox API password (set via TF_VAR_proxmox_password environment variable)"
  type        = string
  sensitive   = true
}
