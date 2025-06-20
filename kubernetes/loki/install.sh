helm install --values values.yaml loki grafana/loki --namespace loki --create-namespace
kubectl patch svc loki -n loki -p '{"spec": {"type": "LoadBalancer"}}'

