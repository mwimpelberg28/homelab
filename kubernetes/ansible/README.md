# Ansible Bootstrap

Ansible playbooks to prepare and bootstrap Kubernetes nodes for the homelab cluster.

## Contents
- **Inventory:** [inventory](inventory) — target hosts and groups.
- **Pre-reqs:** [prereq.yml](prereq.yml) — install packages and configure base settings.
- **Bootstrap:** [bootstrap.yml](bootstrap.yml) — bring up core components on nodes.

## Prerequisites
- SSH access to all nodes defined in the inventory.
- Ansible installed on your control machine.

## Usage

Run pre-requisites and bootstrap:

```bash
ansible-playbook -i inventory prereq.yml
ansible-playbook -i inventory bootstrap.yml
```

Tip: Adjust variables and host groups in the inventory file to match your environment.