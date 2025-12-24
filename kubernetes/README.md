# Homelab Kubernetes

Manifests and helper files to bootstrap and manage a home Kubernetes cluster with Canal (CNI), MetalLB (bare‑metal load balancer), Argo CD (GitOps), and Longhorn (distributed block storage). It also includes optional Terraform to provision cluster VMs.

> Tip: Apply resources gradually in the order below (CNI → MetalLB → Argo CD/Ingress → Storage), validating each step.

## Folder layout

- `canal.yml`: Installs the Canal CNI (Calico + Flannel) for cluster networking.
- `terraform/vms.tf`: Terraform for provisioning cluster VMs (provider-specific; update variables/provider to match your environment).
- `argocd/`
  - `argocd-ingress.yml`: Ingress for Argo CD (choose this or the one under `metallb/`, not both).
  - `longhorn.yml`: Argo CD Application or manifests to install Longhorn.
  - `longhornconfigs.yml`: Longhorn StorageClass / settings.
  - `metallb.yml`: Argo CD Application or manifests to deploy MetalLB.
- `metallb/`
  - `metallb-native.yaml`: MetalLB (native mode) core components.
  - `ipaddresspool.yaml`: IPAddressPool CR; set the LoadBalancer IP range for your LAN.
  - `l2.yaml`: L2Advertisement CR; advertises assigned IPs on your L2 network.
  - `argocd-ingress.yml`: Alternative Ingress for Argo CD.
  - `metallb.sh`: Helper script for installing/configuring MetalLB (optional).

## Prerequisites

- A Kubernetes cluster you control (kubeadm, k3s, etc.).
- `kubectl` configured to talk to the cluster.
- Optional: `terraform` if using `vms.tf` to create VMs.
- Optional: An Ingress controller (e.g., NGINX) if you enable the Argo CD Ingress.

 

## Quick start

### 1) (Optional) Provision VMs
If you intend to create the cluster VMs using Terraform here, review and edit `terraform/vms.tf` (and any referenced variables/provider blocks), then run:

```bash
cd terraform
terraform init
terraform plan
terraform apply
cd ..
```

#### 1b) Build the cluster with Ansible

After provisioning VMs, use the bundled Ansible to prepare nodes and bootstrap Kubernetes:

- Inventory: `ansible/inventory`
- Node prep: `ansible/prereq.yml`
- Cluster bootstrap: `ansible/bootstrap.yml`

Configure inventory and test SSH:

```bash
ansible -i ansible/inventory all -m ping
```

Prepare nodes (swap, kernel modules, container runtime, etc.):

```bash
ansible-playbook -i ansible/inventory ansible/prereq.yml
```

Bootstrap control plane and join workers:

```bash
ansible-playbook -i ansible/inventory ansible/bootstrap.yml
```

Ensure your kubeconfig is available on your workstation (copy from the control plane if needed), then continue below.

### 2) Install CNI (Canal)
Apply the Canal CNI before anything else that depends on networking:

```bash
kubectl apply -f canal.yml
```

Wait for nodes to become `Ready` and core pods to stabilize:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### 3) Install Argo CD (GitOps)
Install Argo CD with the helper script:

```bash
bash install-argocd.sh
# Optional: override namespace
NAMESPACE=my-argocd bash install-argocd.sh
```

Obtain the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4) Deploy Argo CD Ingress
Apply the Argo CD ingress to expose the UI:

```bash
kubectl apply -f argocd/configs/argocd-ingress/argocd-ingress.yml
```

Validate the ingress is created:

```bash
kubectl get ingress -n argocd
```

### 5) Deploy MetalLB via Argo CD
Edit `argocd/apps/metallb/ipaddresspool.yaml` to set an address range on your LAN that MetalLB may allocate (non‑overlapping with DHCP), then deploy MetalLB via Argo CD:

```bash
kubectl apply -f argocd/apps/metallb.yml
```

Validate:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspools.metallb.io -A
kubectl get l2advertisements.metallb.io -A
```

### 6) Deploy Longhorn via Argo CD
Deploy Longhorn storage using the Argo CD Application:

```bash
kubectl apply -f argocd/apps/longhorn.yml
kubectl apply -f argocd/apps/longhornconfigs.yml
```

Validate storage is available:

```bash
kubectl get pods -n longhorn-system
kubectl get sc
```

## Common checks

```bash
# Nodes and CNI
kubectl get nodes -o wide
kubectl get pods -A | grep -i cni

# MetalLB health and allocated LoadBalancer IPs
kubectl get pods -n metallb-system
kubectl get svc -A | grep LoadBalancer

# Argo CD
kubectl get pods -n argocd

# Longhorn
kubectl get pods -n longhorn-system
kubectl get sc
```

## Screenshot

A quick view of pods across all namespaces:

![All namespaces pods](../images/all-namespaces.png)

## Configuration notes

- MetalLB IP range: update `metallb/ipaddresspool.yaml` to match your network (ensure it does not overlap DHCP).
- Ingress hostnames/annotations: update the chosen `argocd-ingress.yml` to match your domain and Ingress controller.
- Terraform: update providers, credentials, and variables in `terraform/vms.tf` to match your environment.

## Cleanup

Caution: Removing the CNI on a running cluster will break networking. Remove applications first, then infrastructure components.

```bash
# Apps and supporting configs (as applicable)
kubectl delete -f argocd/ || true
kubectl delete -f metallb/ || true

# CNI last (only if you intend to tear down the cluster)
kubectl delete -f canal.yml || true
```

## Notes

- Apply manifests in a controlled order and verify between steps, especially on bare metal.
- This folder is meant to be customized; treat the provided YAMLs as sane defaults/starters and adjust to your LAN (IP ranges, domains, storage, etc.).

---

For project context and licensing, see the repository root README and LICENSE.