#!/usr/bin/env bash
#
# talos-cluster.sh - build (or wipe) a 1 control plane + 2 worker Talos cluster
#
#   ./talos-cluster.sh up      # build the cluster from VMs booted off the Talos ISO
#   ./talos-cluster.sh reset   # wipe every node back to maintenance mode (DESTRUCTIVE)
#
# Before "up":
#   * every VM is booted from the Talos ISO and shows "maintenance mode" on its console
#   * every VM's boot order is DISK FIRST, CD-ROM second (Proxmox: Options > Boot Order),
#     so after installing it reboots from disk instead of back into the ISO
#   * the IPs below are reserved in DHCP so they never change
#   * talosctl matches the Talos version on the ISO (talosctl version --client)
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Settings - edit these
# ----------------------------------------------------------------------------
CLUSTER_NAME="mwimpelberg-cluster"
INSTALL_DISK="/dev/sda"            # /dev/vda if the VMs use VirtIO Block disks
WORKDIR="${HOME}/git/talos"

# "IP hostname"
CONTROLPLANE="10.4.20.102 k8s-c01-n01"
WORKERS=(
  "10.4.20.56 k8s-c01-n02"
  "10.4.20.79 k8s-c01-n03"
)

# ----------------------------------------------------------------------------
CP_IP="${CONTROLPLANE%% *}"
CP_NAME="${CONTROLPLANE##* }"
ALL_NODES=("${CONTROLPLANE}" "${WORKERS[@]}")
export TALOSCONFIG="${WORKDIR}/talosconfig"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxx  %b\033[0m\n' "$*" >&2; exit 1; }

# wait_until <timeout-seconds> <description> <command...>
wait_until() {
  local timeout=$1 desc=$2; shift 2
  local start=$SECONDS
  printf '    waiting for %s ' "$desc"
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS - start > timeout )); then
      printf '\n'; die "timed out after ${timeout}s waiting for ${desc}"
    fi
    printf '.'; sleep 10
  done
  printf ' ok\n'
}

worker_ips() { local w; for w in "${WORKERS[@]}"; do printf '%s\n' "${w%% *}"; done; }

# Drop any HostnameConfig document from a multi-document Talos config, then
# append one with a static hostname. (Talos 1.12+ generates "auto: stable",
# which conflicts with a static "hostname", so a plain patch can't be used.)
write_node_config() {
  local base=$1 name=$2 out=$3
  awk '
    function flush() {
      if (buf != "" && buf !~ /(^|\n)kind:[ \t]*HostnameConfig[ \t]*(\n|$)/) {
        if (n++) printf "---\n"
        printf "%s", buf
      }
      buf = ""
    }
    /^---[ \t]*$/ { flush(); next }
    { buf = buf $0 "\n" }
    END { flush() }
  ' "$base" > "$out"
  printf -- '---\napiVersion: v1alpha1\nkind: HostnameConfig\nhostname: %s\n' "$name" >> "$out"
}

etcd_state() {
  talosctl -n "$CP_IP" service etcd 2>/dev/null | awk '$1 == "STATE" { print $2 }'
}
etcd_ready_for_bootstrap() { [[ "$(etcd_state)" =~ ^(Preparing|Running)$ ]]; }

# ----------------------------------------------------------------------------
cmd_up() {
  command -v talosctl >/dev/null || die "talosctl not found in PATH"
  command -v kubectl  >/dev/null || warn "kubectl not found - the final node check will be skipped"

  mkdir -p "${WORKDIR}/nodes"
  cd "$WORKDIR"
  [[ -e secrets.yaml ]] && die "${WORKDIR}/secrets.yaml already exists. Run '$0 reset' first, or move the old files away."

  log "Checking that every node is in maintenance mode and has ${INSTALL_DISK}"
  local entry ip name
  for entry in "${ALL_NODES[@]}"; do
    ip=${entry%% *}; name=${entry##* }
    local disks
    disks=$(talosctl get disks --insecure -n "$ip" 2>&1) \
      || die "${name} (${ip}) is not reachable in maintenance mode:\n${disks}"
    grep -qw "$(basename "$INSTALL_DISK")" <<<"$disks" \
      || die "${name} (${ip}) has no disk $(basename "$INSTALL_DISK"). Disks found:\n${disks}"
    echo "    ${name} (${ip}) ok"
  done

  log "Generating secrets and machine configs"
  talosctl gen secrets -o secrets.yaml
  talosctl gen config "$CLUSTER_NAME" "https://${CP_IP}:6443" \
    --with-secrets secrets.yaml \
    --install-disk "$INSTALL_DISK" \
    --output-dir "$WORKDIR"

  write_node_config controlplane.yaml "$CP_NAME" "nodes/${CP_NAME}.yaml"
  for entry in "${WORKERS[@]}"; do
    name=${entry##* }
    write_node_config worker.yaml "$name" "nodes/${name}.yaml"
  done
  for entry in "${ALL_NODES[@]}"; do
    name=${entry##* }
    talosctl validate --config "nodes/${name}.yaml" --mode metal >/dev/null \
      || die "nodes/${name}.yaml failed validation"
  done
  echo "    per-node configs written to ${WORKDIR}/nodes/"

  log "Applying configs (nodes will install to disk and reboot)"
  talosctl apply-config --insecure -n "$CP_IP" --file "nodes/${CP_NAME}.yaml"
  echo "    ${CP_NAME} (${CP_IP})"
  for entry in "${WORKERS[@]}"; do
    ip=${entry%% *}; name=${entry##* }
    talosctl apply-config --insecure -n "$ip" --file "nodes/${name}.yaml"
    echo "    ${name} (${ip})"
  done

  log "Configuring talosctl"
  talosctl config endpoint "$CP_IP"
  talosctl config node "$CP_IP"
  talosctl config info

  log "Waiting for ${CP_NAME} to finish installing and boot from disk"
  wait_until 900 "etcd service on ${CP_NAME}" etcd_ready_for_bootstrap

  if [[ "$(etcd_state)" == "Running" ]]; then
    echo "    etcd already running - skipping bootstrap"
  else
    log "Bootstrapping etcd on ${CP_NAME}"
    talosctl bootstrap -n "$CP_IP"
  fi

  log "Waiting for the cluster to become healthy (can take ~5-10 min)"
  talosctl -n "$CP_IP" health \
    --control-plane-nodes "$CP_IP" \
    --worker-nodes "$(worker_ips | paste -sd, -)" \
    --wait-timeout 20m

  log "Writing kubeconfig"
  talosctl -n "$CP_IP" kubeconfig "$WORKDIR" --force
  export KUBECONFIG="${WORKDIR}/kubeconfig"

  if command -v kubectl >/dev/null; then
    kubectl wait --for=condition=Ready nodes --all --timeout=5m
    kubectl get nodes -o wide
  fi

  log "Done"
  cat <<EOF
    Files:      ${WORKDIR}
    Back up:    secrets.yaml, talosconfig, kubeconfig (keep a copy off this machine)

    Add to ~/.bashrc so new terminals work:
      export TALOSCONFIG=${WORKDIR}/talosconfig
      export KUBECONFIG=${WORKDIR}/kubeconfig
EOF
}

# ----------------------------------------------------------------------------
cmd_reset() {
  [[ -f "$TALOSCONFIG" ]] || die "No ${TALOSCONFIG} - can't authenticate to the nodes. Re-create the VMs instead."

  warn "This WIPES all of these nodes back to maintenance mode:"
  local entry
  for entry in "${ALL_NODES[@]}"; do warn "    ${entry##* } (${entry%% *})"; done
  read -r -p "Type the cluster name (${CLUSTER_NAME}) to continue: " answer
  [[ "$answer" == "$CLUSTER_NAME" ]] || die "Aborted."

  local ip name
  for entry in "${WORKERS[@]}" "${CONTROLPLANE}"; do
    ip=${entry%% *}; name=${entry##* }
    log "Resetting ${name} (${ip})"
    talosctl -e "$ip" -n "$ip" reset --graceful=false --reboot --wait=false \
      || warn "reset of ${name} failed (already wiped?) - continuing"
  done

  local archive="${WORKDIR}/old-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$archive"
  ( cd "$WORKDIR" && for f in secrets.yaml talosconfig kubeconfig controlplane.yaml worker.yaml nodes; do
      [[ -e "$f" ]] && mv "$f" "$archive/"
    done ) || true

  log "Reset sent. Old files moved to ${archive}"
  echo "    Wait for every console to show maintenance mode, then run: $0 up"
}

# ----------------------------------------------------------------------------
case "${1:-}" in
  up)    cmd_up ;;
  reset) cmd_reset ;;
  *)     echo "usage: $0 {up|reset}"; exit 1 ;;
esac
