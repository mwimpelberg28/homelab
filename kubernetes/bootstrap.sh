#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the homelab cluster end to end:
#   1. Installs Argo CD (via install-argocd.sh)
#   2. Registers the infrastructure apps (ingress, MetalLB, NFS CSI) and waits for them
#   3. Registers the observability apps (otelcol, then otel-demo) and waits for them
#
# Apps are applied in phases rather than all at once: the single control-plane
# node's etcd falls behind if every chart syncs simultaneously, and the
# observability apps depend on MetalLB and the nfs StorageClass anyway.
#
# Safe to re-run; every step is idempotent.
#
# Usage:
#   bash kubernetes/bootstrap.sh
#   SKIP_ARGOCD_INSTALL=1 bash kubernetes/bootstrap.sh   # Argo CD already installed
#   APP_TIMEOUT=1200 bash kubernetes/bootstrap.sh        # seconds to wait per phase
#
# Note: on Talos, PodSecurity "baseline" is enforced by default. MetalLB, the NFS
# CSI driver and the otelcol agent need host access, so their Applications set
# pod-security.kubernetes.io/enforce=privileged via managedNamespaceMetadata.

NAMESPACE="${NAMESPACE:-argocd}"
APP_TIMEOUT="${APP_TIMEOUT:-900}"
SKIP_ARGOCD_INSTALL="${SKIP_ARGOCD_INSTALL:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="${SCRIPT_DIR}/argocd/apps"

INFRA_APPS=(argocd-ingress metallb csi-driver-nfs)
OTELCOL_APPS=(otelcol-agent otelcol-cluster)
DEMO_APPS=(otel-demo)

log() { printf '\n==> %s\n' "$*"; }

# Wait until every named Application is Synced and Healthy, printing status on change.
wait_for_apps() {
  local deadline=$(( $(date +%s) + APP_TIMEOUT )) last="" status pending app
  while true; do
    status=""
    pending=0
    for app in "$@"; do
      local s
      s=$(kubectl -n "${NAMESPACE}" get application "${app}" \
        -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
      status+="${app}=${s:-unknown} "
      [[ "${s}" == "Synced/Healthy" ]] || pending=1
    done
    if [[ "${status}" != "${last}" ]]; then
      echo "    ${status}"
      last="${status}"
    fi
    (( pending == 0 )) && return 0
    if (( $(date +%s) >= deadline )); then
      echo "Timed out after ${APP_TIMEOUT}s waiting for: $*" >&2
      echo "Inspect with: kubectl -n ${NAMESPACE} get applications; kubectl get pods -A | grep -v Running" >&2
      return 1
    fi
    sleep 10
  done
}

apply_phase() {
  local name="$1"; shift
  log "Registering ${name} apps: $*"
  local app
  for app in "$@"; do
    kubectl apply -f "${APPS_DIR}/${app}.yml"
  done
  log "Waiting for ${name} apps to become Synced/Healthy (timeout ${APP_TIMEOUT}s)"
  wait_for_apps "$@"
}

# --- Preflight ---------------------------------------------------------------
command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }
log "Using kube context: $(kubectl config current-context)"
kubectl cluster-info >/dev/null

# Warn about app manifests that no phase covers, so new apps aren't silently skipped.
known=" ${INFRA_APPS[*]} ${OTELCOL_APPS[*]} ${DEMO_APPS[*]} "
for f in "${APPS_DIR}"/*.yml; do
  n="$(basename "${f}" .yml)"
  [[ "${known}" == *" ${n} "* ]] || echo "WARNING: ${f} is not in any bootstrap phase; add it to bootstrap.sh" >&2
done

# --- Argo CD -----------------------------------------------------------------
if [[ "${SKIP_ARGOCD_INSTALL}" == "1" ]]; then
  log "Skipping Argo CD install (SKIP_ARGOCD_INSTALL=1)"
else
  log "Installing Argo CD"
  NAMESPACE="${NAMESPACE}" bash "${SCRIPT_DIR}/install-argocd.sh"
fi
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s >/dev/null

# --- Apps --------------------------------------------------------------------
apply_phase infrastructure "${INFRA_APPS[@]}"
apply_phase otelcol "${OTELCOL_APPS[@]}"
apply_phase otel-demo "${DEMO_APPS[@]}"

# --- Summary -----------------------------------------------------------------
log "All apps Synced/Healthy"
kubectl -n "${NAMESPACE}" get applications

lb_ip() {
  kubectl -n "$1" get svc "$2" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}
echo
echo "Argo CD UI:  http://$(lb_ip "${NAMESPACE}" argocd-server-lb)  (user: admin)"
echo "otel-demo:   http://$(lb_ip otel-demo otel-demo-frontend-proxy-lb)"
if kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  echo "Admin password: $(kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d)"
fi
