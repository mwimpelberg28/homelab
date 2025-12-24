#!/usr/bin/env bash
set -euo pipefail

# Installs Argo CD into the current Kubernetes cluster and optionally applies the local ingress.
# Usage:
#   bash kubernetes/install-argocd.sh
#   NAMESPACE=my-argocd bash kubernetes/install-argocd.sh

NAMESPACE="${NAMESPACE:-argocd}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Argo CD into namespace: ${NAMESPACE}"
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl create namespace "${NAMESPACE}"
fi

echo "Applying Argo CD upstream install manifest: ${INSTALL_URL}"
kubectl apply -n "${NAMESPACE}" -f "${INSTALL_URL}"

echo "Waiting for Argo CD deployments to be ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/argocd-server --timeout=300s
kubectl -n "${NAMESPACE}" rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n "${NAMESPACE}" rollout status deploy/argocd-application-controller --timeout=300s
# Dex may be optional depending on version/config; ignore errors if absent
kubectl -n "${NAMESPACE}" rollout status deploy/argocd-dex-server --timeout=300s || true

# Apply local ingress if present
INGRESS_YAML="${SCRIPT_DIR}/argocd/argocd-ingress.yml"
if [[ -f "${INGRESS_YAML}" ]]; then
  echo "Applying local Argo CD ingress: ${INGRESS_YAML}"
  kubectl apply -f "${INGRESS_YAML}"
else
  echo "No local ingress found at ${INGRESS_YAML}. Skipping ingress apply."
fi

echo "Fetching initial admin password:"
if kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true
  echo
else
  echo "argocd-initial-admin-secret not found yet. It may appear shortly after pods initialize."
fi

echo "Done. Verify status with: kubectl get pods -n ${NAMESPACE}"