#!/usr/bin/env bash
# Replaces grafana.sh / Alloy with upstream OTel Collector.
# Uninstall first if Alloy is running:
#   helm uninstall grafana-k8s-monitoring -n grafana
set -euo pipefail

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# ── 1. DaemonSet — one per node ───────────────────────────────────────────────
# Collects: host metrics, kubelet stats, pod logs, journald
# Receives: OTLP from apps (apps send to otelcol-agent svc ClusterIP)
helm upgrade --install --atomic --timeout 300s otelcol-agent \
  open-telemetry/opentelemetry-collector \
  --namespace otelcol --create-namespace --values - <<'EOF'
mode: daemonset

image:
  repository: otel/opentelemetry-collector-contrib

# Presets wire up the volume mounts, RBAC, and env vars automatically
presets:
  hostMetrics:
    enabled: true        # mounts /hostfs, adds hostmetrics receiver
  kubeletMetrics:
    enabled: true        # adds kubeletstats receiver with serviceAccount auth
  logsCollection:
    enabled: true        # mounts /var/log/pods, adds filelog receiver
    includeCollectorLogs: false
  kubernetesAttributes:
    enabled: true        # adds k8s_attributes processor + RBAC
    extractAllPodLabels: true

tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule

service:
  enabled: true
  type: ClusterIP

ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    hostPort: 0
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    hostPort: 0
    protocol: TCP
  jaeger-compact:
    enabled: false
  jaeger-thrift:
    enabled: false
  jaeger-grpc:
    enabled: false
  zipkin:
    enabled: false

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"
    # hostmetrics + kubeletstats + filelog injected by presets above
    kubeletstats:
      insecure_skip_verify: true

  processors:
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
    batch:
      timeout: 10s
      send_batch_size: 1000
    # k8s_attributes injected by preset
    # Stamp host.name with the actual k8s node name (KUBE_NODE_NAME is injected
    # by the hostMetrics preset via the downward API)
    resource/node_name:
      attributes:
        - key: host.name
          value: "${env:K8S_NODE_NAME}"
          action: upsert

  exporters:
    prometheusremotewrite:
      endpoint: "http://10.4.20.147:9009/api/v1/push"
      headers:
        X-Scope-OrgID: "anonymous"
      resource_to_telemetry_conversion:
        enabled: true
      tls:
        insecure: true

    otlphttp/loki:
      endpoint: "http://10.4.20.147:3100/otlp"
      tls:
        insecure: true

    otlp/tempo:
      endpoint: "10.4.20.147:4317"
      tls:
        insecure: true

  service:
    pipelines:
      metrics:
        receivers:  [otlp, hostmetrics, kubeletstats]
        processors: [memory_limiter, resource/node_name, k8s_attributes, batch]
        exporters:  [prometheusremotewrite]
      logs:
        receivers:  [otlp, filelog]
        processors: [memory_limiter, resource/node_name, k8s_attributes, batch]
        exporters:  [otlphttp/loki]
      traces:
        receivers:  [otlp]
        processors: [memory_limiter, resource/node_name, k8s_attributes, batch]
        exporters:  [otlp/tempo]
EOF

# ── 2. Deployment — runs once for cluster-wide telemetry ─────────────────────
# Collects: Kubernetes cluster metrics (node/pod/deployment state)
#           Kubernetes events (as logs to Loki)
helm upgrade --install --atomic --timeout 300s otelcol-cluster \
  open-telemetry/opentelemetry-collector \
  --namespace otelcol --values - <<'EOF'
mode: deployment
replicaCount: 1

image:
  repository: otel/opentelemetry-collector-contrib

presets:
  clusterMetrics:
    enabled: true        # adds k8s_cluster receiver + RBAC
  kubernetesEvents:
    enabled: true        # adds k8sobjects receiver watching events

# No OTLP ports needed here — apps talk to the agent DaemonSet
ports:
  otlp:
    enabled: false
  otlp-http:
    enabled: false

config:
  processors:
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
    batch:
      timeout: 10s

  exporters:
    prometheusremotewrite:
      endpoint: "http://10.4.20.147:9009/api/v1/push"
      headers:
        X-Scope-OrgID: "anonymous"
      resource_to_telemetry_conversion:
        enabled: true
      tls:
        insecure: true

    otlphttp/loki:
      endpoint: "http://10.4.20.147:3100/otlp"
      tls:
        insecure: true

  service:
    pipelines:
      metrics:
        receivers:  [k8s_cluster]
        processors: [memory_limiter, batch]
        exporters:  [prometheusremotewrite]
      logs:
        receivers:  [k8sobjects]
        processors: [memory_limiter, batch]
        exporters:  [otlphttp/loki]
EOF

echo ""
echo "otelcol-agent  (DaemonSet)  running in namespace: otelcol"
echo "otelcol-cluster (Deployment) running in namespace: otelcol"
echo ""
echo "OTLP endpoint for apps:"
echo "  gRPC  otelcol-agent-opentelemetry-collector.otelcol.svc.cluster.local:4317"
echo "  HTTP  otelcol-agent-opentelemetry-collector.otelcol.svc.cluster.local:4318"
echo ""
echo "Update otel-demo my-values-file.yaml exporter endpoint to the HTTP address above."
