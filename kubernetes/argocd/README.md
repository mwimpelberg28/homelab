# Argo CD Manifests

Manifests to expose Argo CD and manage cluster apps via GitOps.

## Apps (`apps/`)

| File | Namespace | Description |
|---|---|---|
| `argocd-ingress.yml` | `argocd` | Ingress for the Argo CD UI/API |
| `metallb.yml` | `metallb-system` | MetalLB bare-metal load balancer |
| `longhorn.yml` | `longhorn-system` | Longhorn distributed block storage |
| `llm-stack.yml` | `llm-stack` | Ollama + Open WebUI + Aider for local LLM inference |
| `otelcol-agent.yml` | `otelcol` | OpenTelemetry node-level DaemonSet collector |
| `otelcol-cluster.yml` | `otelcol` | OpenTelemetry cluster-level aggregating collector |
| `otel-demo.yml` | `otel-demo` | OpenTelemetry demo application |

## Configs (`configs/`)

Per-app configuration referenced by the ArgoCD Applications above:

- `configs/llm-stack/` — Ollama, Open WebUI, and Aider manifests
- `configs/otelcol/` — agent and cluster collector Helm values
- `configs/otel-demo/` — demo app Helm values

## Prerequisites
- A working Kubernetes cluster and `kubectl` context.
- Domain/DNS entries for the Argo CD ingress host.

## Apply

```bash
# Core infrastructure
kubectl apply -f apps/argocd-ingress.yml
kubectl apply -f apps/metallb.yml
kubectl apply -f apps/longhorn.yml

# LLM stack
kubectl apply -f apps/llm-stack.yml

# Observability
kubectl apply -f apps/otelcol-agent.yml
kubectl apply -f apps/otelcol-cluster.yml
kubectl apply -f apps/otel-demo.yml
```

All apps use automated sync with self-heal, so Argo CD will reconcile state continuously after the Application resource is created.