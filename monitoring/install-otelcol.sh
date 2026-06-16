#!/usr/bin/env bash
# Installs the upstream OTel Collector (contrib distro) on a standalone Ubuntu
# host and ships host metrics + journald logs to the Mimir/Loki stack on the
# homelab Pi (see README.md). Mirrors the otelcol-agent config used for the
# k8s cluster in ../kubernetes/observability/otelcol.sh.
set -euo pipefail

MIMIR_ENDPOINT="${MIMIR_ENDPOINT:-http://10.4.20.147:9009/api/v1/push}"
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://10.4.20.147:3100/otlp}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo $0)" >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"

if [[ -z "${OTELCOL_VERSION:-}" ]]; then
  # Capture the full response before parsing it: piping straight into
  # `grep -m1` can SIGPIPE curl if grep closes the pipe mid-write.
  LATEST="$(curl -fsSL https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases/latest)"
  OTELCOL_VERSION="$(grep -m1 '"tag_name"' <<<"$LATEST" | sed -E 's/.*"v([^"]+)".*/\1/')"
fi

PKG="otelcol-contrib_${OTELCOL_VERSION}_linux_${ARCH}.deb"
URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/${PKG}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing otelcol-contrib v${OTELCOL_VERSION} (${ARCH})..."
curl -fsSL "$URL" -o "$TMP/$PKG"
dpkg -i "$TMP/$PKG"

# journald receiver needs the service user in this group to read the journal
usermod -aG systemd-journal otelcol-contrib

install -d -m 0755 /etc/otelcol-contrib
cat > /etc/otelcol-contrib/config.yaml <<EOF
receivers:
  hostmetrics:
    collection_interval: 15s
    scrapers:
      cpu: {}
      disk: {}
      filesystem: {}
      load: {}
      memory: {}
      network: {}
      paging: {}
      processes: {}
  journald:
    priority: info

processors:
  memory_limiter:
    check_interval: 5s
    limit_percentage: 80
    spike_limit_percentage: 25
  resourcedetection/system:
    detectors: [system]
    system:
      hostname_sources: [os]
  batch:
    timeout: 10s
    send_batch_size: 1000

exporters:
  prometheusremotewrite:
    endpoint: "${MIMIR_ENDPOINT}"
    headers:
      X-Scope-OrgID: "anonymous"
    resource_to_telemetry_conversion:
      enabled: true
    tls:
      insecure: true
  otlphttp/loki:
    endpoint: "${LOKI_ENDPOINT}"
    tls:
      insecure: true

service:
  pipelines:
    metrics:
      receivers:  [hostmetrics]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters:  [prometheusremotewrite]
    logs:
      receivers:  [journald]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters:  [otlphttp/loki]
EOF

systemctl enable --now otelcol-contrib

echo ""
echo "otelcol-contrib installed and running."
echo "Metrics -> ${MIMIR_ENDPOINT}"
echo "Logs    -> ${LOKI_ENDPOINT}"
echo "Status:  systemctl status otelcol-contrib"
echo "Logs:    journalctl -u otelcol-contrib -f"
