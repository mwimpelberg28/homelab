terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.57.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://proxmox.rp.mwimpelberg.com"
  insecure = true
  username = "root@pam"
  password = var.proxmox_password
}

resource "proxmox_virtual_environment_vm" "k8s_c01_n01" {
  node_name = "pven0"
  name      = "k8s-c01-n01"
  vm_id     = 101

  cpu {
    cores   = 1
    sockets = 2
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  operating_system {
    type = "l26"
  }

  bios    = "seabios"
  machine = "pc-i440fx-8.0"

  boot_order = ["scsi0", "ide2", "net0"]

  disk {
    interface    = "scsi0"
    datastore_id = "proxmox_vms"
    size         = 80
    file_format  = "qcow2"
    iothread     = true
  }

  cdrom {
    interface = "ide2"

    # file_id = "<datastore_id>:<content_type>/<file_name>"
    file_id = "isos:iso/ubuntu-24.04-live-server-amd64.iso"
  }

  network_device {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = true
  }

  agent {
    enabled = false
  }

  startup {
    order = 1
  }
}



resource "proxmox_virtual_environment_vm" "k8s_c01_n02" {
  node_name = "pven1"
  name      = "k8s-c01-n02"
  vm_id     = 105

  cpu {
    cores   = 1
    sockets = 2
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  operating_system {
    type = "l26"
  }

  bios    = "seabios"
  machine = "pc-i440fx-8.0"

  boot_order = ["scsi0", "ide2", "net0"]

  disk {
    interface    = "scsi0"
    datastore_id = "proxmox_vms"
    size         = 80
    file_format  = "qcow2"
    iothread     = true
  }

  cdrom {
    interface = "ide2"

    # file_id = "<datastore_id>:<content_type>/<file_name>"
    file_id = "isos:iso/ubuntu-24.04-live-server-amd64.iso"
  }

  network_device {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = true
  }

  agent {
    enabled = false
  }

  startup {
    order = 1
  }
}

resource "proxmox_virtual_environment_vm" "k8s_c01_n03" {
  node_name = "pven2"
  name      = "k8s-c01-n03"
  vm_id     = 107

  cpu {
    cores   = 1
    sockets = 2
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  operating_system {
    type = "l26"
  }

  bios    = "seabios"
  machine = "pc-i440fx-8.0"

  boot_order = ["scsi0", "ide2", "net0"]

  disk {
    interface    = "scsi0"
    datastore_id = "proxmox_vms"
    size         = 80
    file_format  = "qcow2"
    iothread     = true
  }

  cdrom {
    interface = "ide2"

    # file_id = "<datastore_id>:<content_type>/<file_name>"
    file_id = "isos:iso/ubuntu-24.04-live-server-amd64.iso"
  }

  network_device {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = true
  }

  agent {
    enabled = false
  }

  startup {
    order = 1
  }
}

