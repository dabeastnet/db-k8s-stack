# URLs & Endpoints Reference

## 1. Public URLs (via Cloudflare Tunnel)

| URL | Service | Notes |
|-----|---------|-------|
| `https://project.beckersd.com/` | Frontend (Apache) | Serves `index.html` |
| `https://project.beckersd.com/api/name` | db-api | Returns `{"name": "..."}` from PostgreSQL |
| `https://project.beckersd.com/api/container-id` | db-api | Returns `{"container_id": "...", "pod_name": "...", "hostname": "..."}` |
| `https://project.beckersd.com/healthz` | db-api | Liveness probe — returns `{"status": "ok"}` |
| `https://project.beckersd.com/readyz` | db-api | Readiness probe — checks DB connectivity, returns `{"status": "ok"}` or HTTP 503 |
| `https://project.beckersd.com/metrics` | db-api | Prometheus metrics (text/plain) |
| `https://argocd.beckersd.com` | ArgoCD UI | GitOps dashboard — login: `admin` / see secret |

---

## 2. Local Access (Vagrant Port Forwarding)

These are forwarded from your Windows host to `cp1` (192.168.56.10).

| Host URL | Host Port | NodePort (cp1) | Service |
|----------|-----------|----------------|---------|
| `http://localhost:18080/` | 18080 | 30080 | nginx ingress → frontend |
| `http://localhost:18080/api/name` | 18080 | 30080 | nginx ingress → db-api |
| `http://localhost:18080/api/container-id` | 18080 | 30080 | nginx ingress → db-api |
| `http://localhost:18080/healthz` | 18080 | 30080 | nginx ingress → db-api |
| `http://localhost:18080/readyz` | 18080 | 30080 | nginx ingress → db-api |
| `http://localhost:18080/metrics` | 18080 | 30080 | nginx ingress → db-api |
| `https://localhost:18443/` | 18443 | 30443 | nginx ingress (TLS) |
| `http://localhost:19090/` | 19090 | 30090 | Prometheus UI |
| `http://localhost:13000/` | 13000 | 30030 | Grafana UI — login: `admin` / `admin` |

---

## 3. NodePorts (direct on cp1: 192.168.56.10)

| URL | NodePort | Service |
|-----|----------|---------|
| `http://192.168.56.10:30080/` | 30080 | nginx ingress HTTP |
| `https://192.168.56.10:30443/` | 30443 | nginx ingress HTTPS |
| `http://192.168.56.10:30090/` | 30090 | Prometheus UI |
| `http://192.168.56.10:30030/` | 30030 | Grafana UI |

---

## 4. API Endpoints (db-api)

All endpoints are served by FastAPI on container port `8000`, exposed via the `db-api` ClusterIP service on port `80`.

| Method | Path | Description | Response |
|--------|------|-------------|----------|
| `GET` | `/api/name` | Current name from PostgreSQL `person` table | `{"name": "Dieter Beckers"}` |
| `GET` | `/api/container-id` | Container identity info | `{"container_id": "abc123def456", "pod_name": "db-api-...", "hostname": "worker1"}` |
| `GET` | `/healthz` | Liveness probe — always returns OK if process is running | `{"status": "ok"}` — HTTP 200 |
| `GET` | `/readyz` | Readiness probe — verifies PostgreSQL connection with `SELECT 1` | `{"status": "ok"}` — HTTP 200, or HTTP 503 if DB unreachable |
| `GET` | `/metrics` | Prometheus metrics export | `text/plain` — exposes `db_api_requests_total` counter |

### Prometheus metric

| Metric | Labels | Description |
|--------|--------|-------------|
| `db_api_requests_total` | `endpoint`, `method` | Total request count per endpoint and HTTP method |

---

## 5. Internal Cluster DNS (in-cluster only)

| DNS name | Port | Service |
|----------|------|---------|
| `db-api.db-stack.svc.cluster.local` | 80 | API (FastAPI) |
| `db-frontend.db-stack.svc.cluster.local` | 80 | Frontend (Apache) |
| `db-postgres.db-stack.svc.cluster.local` | 5432 | PostgreSQL |
| `db-prometheus.monitoring.svc.cluster.local` | 9090 | Prometheus |
| `db-grafana.monitoring.svc.cluster.local` | 3000 | Grafana |
| `db-kube-state-metrics.monitoring.svc.cluster.local` | 8080 | kube-state-metrics |
| `db-ingress-nginx-controller.ingress-nginx.svc.cluster.local` | 80 / 443 | nginx ingress (Cloudflare tunnel target) |

---

## 6. Grafana & Prometheus Internal Endpoints

| Service | Path | Purpose |
|---------|------|---------|
| Grafana | `/api/health` | Readiness probe (returns HTTP 200 when ready) |
| Prometheus | `/` | Web UI — targets, graph, alerts |
| Prometheus | `/-/ready` | Readiness check |
| Prometheus | `/-/healthy` | Health check |

---

## 7. Prometheus Scrape Targets

Configured in `k8s/monitoring/prometheus.yaml` → `prometheus.yml` ConfigMap.

| Job name | Target | Path | What it scrapes |
|----------|--------|------|-----------------|
| `prometheus` | `localhost:9090` | `/metrics` | Prometheus itself |
| `kube-state-metrics` | `db-kube-state-metrics.monitoring.svc.cluster.local:8080` | `/metrics` | Kubernetes object state |
| `db-api` | `db-api.db-stack.svc.cluster.local:80` | `/metrics` | Application request counters |
| `kubernetes-nodes` | Each node IP `:9100` (auto-discovered) | `/metrics` | node-exporter: CPU, memory, disk, network |

---

## 8. GitHub / External URLs

| URL | Purpose |
|-----|---------|
| `https://github.com/dabeastnet/db-k8s-stack` | Source repository — ArgoCD polls this for GitOps sync |
