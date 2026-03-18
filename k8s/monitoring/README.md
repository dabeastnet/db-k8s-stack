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

### Resources created

1. **ConfigMap `db-prometheus-config`** — holds the full `prometheus.yml` scrape configuration
2. **ServiceAccount `db-prometheus`** — identity for RBAC
3. **ClusterRole `db-prometheus`** — grants `get/list/watch` on nodes, pods, services, and endpoints
4. **ClusterRoleBinding `db-prometheus`** — binds the ClusterRole to the ServiceAccount
5. **Deployment `db-prometheus`** — single replica running `prom/prometheus:v2.51.0`
6. **Service `db-prometheus`** — NodePort `30090` exposing the Prometheus web UI

### Scrape configuration

All scrape jobs are static (no Prometheus Operator required):

| Job | Target | Interval | What it collects |
|-----|--------|----------|-----------------|
| `prometheus` | `localhost:9090` | 15 s | Prometheus self-metrics (uptime, rule evaluation, scrape stats) |
| `kube-state-metrics` | `db-kube-state-metrics.monitoring.svc.cluster.local:8080` | 15 s | Kubernetes object state (pod phases, node conditions, container restarts) |
| `db-api` | `db-api.db-stack.svc.cluster.local:80/metrics` | 15 s | Application counters (`db_api_requests_total`) |
| `kubernetes-nodes` | All nodes via K8s SD on port 9100 | 15 s | node-exporter CPU, memory, disk, network per node |

The `kubernetes-nodes` job uses Kubernetes service discovery (`role: node`) with a `relabel_configs` block that:
- Replaces `__address__` with `<node-IP>:9100` (node-exporter port)
- Sets the `node` label from `__meta_kubernetes_node_name` so graphs display `cp1`, `worker1`, `worker2` instead of raw IP addresses

### Storage and retention

Prometheus uses `emptyDir` storage — all metrics are **lost when the pod restarts**. This is acceptable for a development cluster. To add persistence:

```yaml
volumes:
  - name: prometheus-storage
    persistentVolumeClaim:
      claimName: prometheus-pvc
```

**Service**: NodePort `30090` → Prometheus web UI.
**Access locally**: `http://localhost:19090` (Vagrantfile forwards guest 30090 → host 19090).

## kube-state-metrics (`kube-state-metrics.yaml`)

Exports Kubernetes object state as Prometheus metrics. These are distinct from the resource usage metrics exposed by node-exporter — kube-state-metrics reflects the *desired and actual state* of Kubernetes objects rather than hardware counters.

- **Image**: `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0`
- **Port**: `8080`

Key metrics used by the dashboard:

| Metric | Description |
|--------|-------------|
| `kube_pod_status_phase` | Current phase of each pod (Running, Pending, Failed, etc.) |
| `kube_node_status_condition` | Node conditions (Ready, MemoryPressure, DiskPressure) |
| `kube_pod_container_status_restarts_total` | Cumulative container restarts per pod |

RBAC: `ClusterRole` grants `get/list/watch` on pods, nodes, services, deployments, replicasets, statefulsets, endpoints, persistentvolumeclaims, and namespaces.

## node-exporter (`node-exporter.yaml`)

Runs as a `DaemonSet` — one pod scheduled on **every node** (cp1, worker1, worker2) via a toleration for the control-plane taint. Exposes hardware and OS metrics on port `9100`.

- **Image**: `prom/node-exporter:v1.8.0`
- **Host mounts**: `/proc`, `/sys`, `/` (read-only) — required to read kernel-level counters

| Setting | Value | Reason |
|---------|-------|--------|
| `hostNetwork: true` | — | Node-exporter binds to the host network so Prometheus can reach it at the node's IP on port 9100 |
| `hostPID: true` | — | Needed to read process-level metrics from `/proc` |
| `readOnlyRootFilesystem` | `true` | Reduces attack surface — no writes needed |

Key metrics:

| Metric | Description |
|--------|-------------|
| `node_cpu_seconds_total` | CPU time per mode (idle, user, system, iowait) |
| `node_memory_MemAvailable_bytes` | Available physical memory |
| `node_memory_MemTotal_bytes` | Total physical memory |
| `node_disk_read_bytes_total` / `node_disk_written_bytes_total` | Disk I/O per device |
| `node_network_receive_bytes_total` / `node_network_transmit_bytes_total` | Network I/O per interface |

## Grafana (`grafana.yaml`)

### Resources created

Grafana is configured entirely via ConfigMaps at startup — no manual dashboard import or datasource configuration is needed.

| ConfigMap | Mount path | Purpose |
|-----------|-----------|---------|
| `db-grafana-datasources` | `/etc/grafana/provisioning/datasources` | Auto-registers Prometheus (`http://db-prometheus.monitoring.svc.cluster.local:9090`) as the default datasource |
| `db-grafana-dashboard-provider` | `/etc/grafana/provisioning/dashboards` | Tells Grafana to load JSON dashboard files from `/var/lib/grafana/dashboards` |
| `db-grafana-dashboard` | `/var/lib/grafana/dashboards` | Pre-built `db-k8s-stack Overview` dashboard JSON |

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

### Grafana deployment details

- **Image**: `grafana/grafana:10.4.0`
- **Port**: `3000` (internal); exposed via NodePort `30030`
- **Run as**: UID 472 (official Grafana image default)
- **Storage**: `emptyDir` — dashboards survive pod restarts because they are re-provisioned from ConfigMaps on startup; user-created dashboards are lost

**Credentials**: `admin` / `admin` (change after first login with `GF_SECURITY_ADMIN_PASSWORD` env var or via the UI).

**Service**: NodePort `30030` → Grafana UI.
**Access locally**: `http://localhost:13000` (Vagrantfile forwards guest 30030 → host 13000).

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

## Deploying the monitoring stack

The monitoring stack is applied automatically by `deploy-k8s.sh`. To apply manually:

```bash
kubectl apply -f k8s/monitoring/namespace.yaml
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/kube-state-metrics.yaml
kubectl apply -f k8s/monitoring/node-exporter.yaml
kubectl apply -f k8s/monitoring/grafana.yaml

# Optional — only if Prometheus Operator CRDs are installed
kubectl apply -f k8s/monitoring/service-monitor.yaml
```

Order matters: `namespace.yaml` must be applied first. The other manifests can be applied in any order.

## Useful kubectl commands

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# View Prometheus logs
kubectl logs -n monitoring -l app=db-prometheus --tail=50

# View Grafana logs
kubectl logs -n monitoring -l app=db-grafana --tail=50

# Verify Prometheus scrape targets (port-forward first)
kubectl port-forward svc/db-prometheus -n monitoring 9090:9090
# Then open: http://localhost:9090/targets

# Access Grafana directly via port-forward
kubectl port-forward svc/db-grafana -n monitoring 3000:3000
# Then open: http://localhost:3000
```

## Dependencies

- The `monitoring` namespace must exist before applying other manifests (created by `namespace.yaml`)
- node-exporter requires `hostNetwork`, `hostPID`, and read access to `/proc`, `/sys`, `/`
- The `db-api` scrape job assumes the API service is reachable at `db-api.db-stack.svc.cluster.local:80`
- `service-monitor.yaml` requires Prometheus Operator CRDs
