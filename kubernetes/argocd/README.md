# Argo CD Manifests

Manifests to expose Argo CD and manage core apps via GitOps.

## Contents
- **Argo CD Ingress:** [argocd-ingress.yml](argocd-ingress.yml) — ingress for Argo CD UI/API.
- **MetalLB App:** [metallb.yml](metallb.yml) — deploy MetalLB via Argo CD.
- **Longhorn Storage:** [longhorn.yml](longhorn.yml) & [longhornconfigs.yml](longhornconfigs.yml) — Longhorn and tuning configs.

## Prerequisites
- A working Kubernetes cluster and `kubectl` context.
- Domain/DNS entries for the Argo CD ingress host.

## Apply Manifests

```bash
kubectl apply -f argocd-ingress.yml
kubectl apply -f metallb.yml
kubectl apply -f longhorn.yml
kubectl apply -f longhornconfigs.yml
```

Secure the ingress with TLS and configure credentials for Argo CD according to your environment.