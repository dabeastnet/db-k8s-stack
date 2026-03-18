# k8s/monitoring — Prometheus, Grafana & Exporters

## Purpose

This directory contains all manifests for the observability stack. It deploys Prometheus, Grafana, kube-state-metrics and node-exporter into the `monitoring` namespace without requiring the Prometheus Operator. A `ServiceMonitor` manifest is also included for environments where the Operator is available.

## Components

| Manifest | Resource | Description |
|----------|----------|-------------|
| `namespace.yaml` | Namespace `monitoring` | Isolates monitoring workloads |
| `prometheus.yaml` | ConfigMap, ServiceAccount, ClusterRole, ClusterRoleBinding, Deployment, Service | Prometheus server |
| `kube-state-metrics.yaml` | ServiceAccount, ClusterRole, ClusterRoleBinding, Deployment, Service | Cluster-state metrics exporter |
| `node-exporter.yaml` | ServiceAccount, ClusterRole, ClusterRoleBinding, DaemonSet, Service | Per-node hardware/OS metrics |
| `grafana.yaml` | 3× ConfigMap, Deployment, Service | Grafana with pre-built dashboard |
| `service-monitor.yaml` | ServiceMonitor `db-api-servicemonitor` | Prometheus Operator scrape config for `db-api` |

## Prometheus (`prometheus.yaml`)

Scrape configuration (static, no Operator required):

| Job | Target | What it collects |
|-----|--------|-----------------|
| `prometheus` | `localhost:9090` | Prometheus self-metrics |
| `kube-state-metrics` | `db-kube-state-metrics.monitoring.svc.cluster.local:8080` | Kubernetes object state |
| `db-api` | `db-api.db-stack.svc.cluster.local:80/metrics` | Application request counters |
| `kubernetes-nodes` | All nodes via Kubernetes SD on port 9100 | node-exporter metrics |

The `kubernetes-nodes` job uses Kubernetes service discovery (`role: node`) and relabels the `node` label from `__meta_kubernetes_node_name` so graphs show human-readable node names (`cp1`, `worker1`, `worker2`) rather than IP addresses.

RBAC: `ClusterRole` grants `get/list/watch` on nodes, pods, services, and endpoints.

**Service**: NodePort `30090` → Prometheus web UI.
**Access locally**: `http://localhost:19090` (forwarded by Vagrantfile: guest 30090 → host 19090).

Storage uses `emptyDir` — metrics are lost on pod restart. For persistence, replace with a PersistentVolumeClaim.

## kube-state-metrics (`kube-state-metrics.yaml`)

Exports Kubernetes object metrics (e.g. `kube_pod_status_phase`, `kube_node_status_condition`, `kube_pod_container_status_restarts_total`). These power the "Running Pods" and "Ready Nodes" panels in Grafana.

- **Image**: `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0`
- **Port**: `8080`

## node-exporter (`node-exporter.yaml`)

Runs as a `DaemonSet` — one pod per node (including the control plane via a toleration). Exposes hardware and OS metrics such as CPU, memory, disk I/O, and network statistics on port `9100`.

- **Image**: `prom/node-exporter:v1.8.0`
- **Host mounts**: `/proc`, `/sys`, `/` (read-only) mapped into the container
- `hostNetwork: true` and `hostPID: true` are required for accurate host-level metrics

## Grafana (`grafana.yaml`)

Grafana is pre-provisioned via three ConfigMaps mounted into the container at startup:

| ConfigMap | Mount path | Purpose |
|-----------|-----------|---------|
| `db-grafana-datasources` | `/etc/grafana/provisioning/datasources` | Auto-registers Prometheus as the default datasource |
| `db-grafana-dashboard-provider` | `/etc/grafana/provisioning/dashboards` | Configures file-based dashboard loading |
| `db-grafana-dashboard` | `/var/lib/grafana/dashboards` | Pre-built `db-k8s-stack Overview` dashboard |

### Pre-built dashboard panels

| Panel | Type | Query |
|-------|------|-------|
| Running Pods (db-stack) | Stat | `sum(kube_pod_status_phase{namespace="db-stack",phase="Running"})` |
| Ready Nodes | Stat | `count(kube_node_status_condition{condition="Ready",status="true"})` |
| API Requests (last 5m) | Stat | `sum(increase(db_api_requests_total[5m]))` |
| Pod Restarts (last 1h) | Stat | `sum(increase(kube_pod_container_status_restarts_total{namespace="db-stack"}[1h]))` |
| Node CPU Usage % | Time series | `100 * (1 - avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m])))` |
| Node Memory Usage % | Time series | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` |
| API Request Rate (req/s) | Time series | `sum by(endpoint)(rate(db_api_requests_total[5m]))` |
| Node Disk I/O (bytes/s) | Time series | Read + write bytes per node |

**Credentials**: `admin` / `admin` (default; change after first login).

**Service**: NodePort `30030` → Grafana UI.
**Access locally**: `http://localhost:13000` (forwarded by Vagrantfile: guest 30030 → host 13000).

## ServiceMonitor (`service-monitor.yaml`)

Defines a `ServiceMonitor` resource for the Prometheus Operator (separate from the static scrape config above):

```yaml
selector:
  matchLabels:
    app: db-api
namespaceSelector:
  matchNames: [db-stack]
endpoints:
  - port: http
    path: /metrics
    interval: 15s
```

This manifest requires the Prometheus Operator CRDs. The apply is wrapped in a non-fatal block in `deploy-k8s.sh` and skipped gracefully if the CRDs are not installed.

## Accessing the UIs

| Service | URL (local via Vagrant) | Notes |
|---------|------------------------|-------|
| Prometheus | `http://localhost:19090` | No authentication |
| Grafana | `http://localhost:13000` | `admin` / `admin` |

Both ports are forwarded automatically by the Vagrantfile. No `kubectl port-forward` is needed.

## Dependencies

- The `monitoring` namespace must exist before applying other manifests (created by `namespace.yaml`)
- node-exporter requires `hostNetwork`, `hostPID`, and read access to `/proc`, `/sys`, `/`
- The `db-api` scrape job assumes the API service is reachable at `db-api.db-stack.svc.cluster.local:80`
- `service-monitor.yaml` requires Prometheus Operator CRDs
