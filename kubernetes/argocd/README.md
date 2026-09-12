# Argo CD Manifests

Manifests to expose Argo CD and manage cluster apps via GitOps.

## Apps (`apps/`)

| File | Namespace | Description |
|---|---|---|
| `argocd-ingress.yml` | `argocd` | Ingress for the Argo CD UI/API |
| `metallb.yml` | `metallb-system` | MetalLB bare-metal load balancer |
| `csi-driver-nfs.yml` | `csi-driver-nfs` | NFS CSI driver + default `nfs` StorageClass (Synology NAS-backed) |
| `otelcol-agent.yml` | `otelcol` | OpenTelemetry node-level DaemonSet collector |
| `otelcol-cluster.yml` | `otelcol` | OpenTelemetry cluster-level aggregating collector |
| `otel-demo.yml` | `otel-demo` | OpenTelemetry demo application |

## Configs (`configs/`)

Per-app configuration referenced by the ArgoCD Applications above:

- `configs/csi-driver-nfs/` — `nfs` StorageClass pointed at the NAS export
- `configs/otelcol/` — agent and cluster collector Helm values
- `configs/otel-demo/` — demo app Helm values
- `configs/otel-demo-lb/` — LoadBalancer Service exposing the demo's frontend-proxy

## Prerequisites
- A working Kubernetes cluster and `kubectl` context.
- Domain/DNS entries for the Argo CD ingress host.

## Apply

```bash
# Core infrastructure
kubectl apply -f apps/argocd-ingress.yml
kubectl apply -f apps/metallb.yml
kubectl apply -f apps/csi-driver-nfs.yml

# Observability
kubectl apply -f apps/otelcol-agent.yml
kubectl apply -f apps/otelcol-cluster.yml
kubectl apply -f apps/otel-demo.yml
```

All apps use automated sync with self-heal, so Argo CD will reconcile state continuously after the Application resource is created.