# k8s — Kubernetes Manifests

## Purpose

This directory contains all Kubernetes manifests for the db-k8s-stack. Manifests are organised by component and applied in order by `deploy-k8s.sh`, or synchronised automatically from Git by ArgoCD. The stack runs in the `db-stack` namespace; monitoring runs in a separate `monitoring` namespace.

## Directory structure

```
k8s/
├── namespace.yaml              db-stack namespace
├── configmap.yaml              Non-secret DB connection parameters (db-app-config)
├── secret.example.yaml         Secret template — db-app-secret (do NOT commit real secrets)
├── api/
│   ├── deployment.yaml         db-api Deployment: 2 replicas, topology spread, probes, limits
│   └── service.yaml            db-api ClusterIP Service: port 80 → container 8000
├── frontend/
│   ├── deployment.yaml         db-frontend Deployment: 1 replica, probes, limits
│   └── service.yaml            db-frontend ClusterIP Service: port 80 → container 8080
├── postgres/
│   └── postgres.yaml           PersistentVolume, PVC, StatefulSet, ClusterIP Service
├── ingress/
│   └── ingress.yaml            nginx Ingress: host rules for project.beckersd.com + catch-all
├── cert-manager/
│   └── clusterissuer.yaml      Let's Encrypt ClusterIssuers (prod + staging)
├── cloudflared/
│   └── deployment.yaml         Cloudflare Tunnel Deployment + token Secret
├── argocd/
│   └── application.yaml        ArgoCD Application (GitOps sync from GitHub)
└── monitoring/
    └── (see k8s/monitoring/README.md)
```

## Namespaces

| Namespace | Managed by | Contents |
|-----------|-----------|---------|
| `db-stack` | `deploy-k8s.sh` / ArgoCD | frontend, API, PostgreSQL, Cloudflare tunnel |
| `monitoring` | `deploy-k8s.sh` | Prometheus, Grafana, kube-state-metrics, node-exporter |
| `ingress-nginx` | Helm (`db-ingress-nginx`) | nginx ingress controller |
| `argocd` | Helm (`db-argocd`) | ArgoCD components |

---

## Shared configuration

### `namespace.yaml`

Creates the `db-stack` namespace. Applied first so all subsequent resources can reference it.

### `configmap.yaml` — `db-app-config`

Non-sensitive database connection parameters shared by the API:

| Key | Value |
|-----|-------|
| `DB_HOST` | `db-postgres` |
| `DB_PORT` | `5432` |
| `DB_NAME` | `demo` |

### `secret.example.yaml` — `db-app-secret`

Template file showing the structure of the required Secret. Uses `stringData` (Kubernetes base64-encodes it automatically):

| Key | Example value |
|-----|--------------|
| `DB_USER` | `demo` |
| `DB_PASSWORD` | `demo` |

**Important**: this file contains only example credentials for development. Never commit real passwords. In `provision-master.sh`, the secret is only applied if `db-app-secret` does not already exist — so you can pre-create it with real credentials before provisioning.

---

## API (`api/`)

### `api/deployment.yaml`

**Image**: `ghcr.io/dabeastnet/db-api:v6`
**Replicas**: 2
**Namespace**: `db-stack`

#### Topology spread

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: db-api
```

Ensures exactly one replica lands on each worker node. `DoNotSchedule` means a third replica would remain `Pending` if only two nodes are schedulable — which is intentional since the cluster has exactly two workers.

#### Environment variables

| Variable | Source |
|----------|--------|
| `DB_HOST` | `db-app-config` ConfigMap key `DB_HOST` |
| `DB_PORT` | `db-app-config` ConfigMap key `DB_PORT` |
| `DB_NAME` | `db-app-config` ConfigMap key `DB_NAME` |
| `DB_USER` | `db-app-secret` Secret key `DB_USER` |
| `DB_PASSWORD` | `db-app-secret` Secret key `DB_PASSWORD` |
| `PGPASSWORD` | `db-app-secret` Secret key `DB_PASSWORD` (duplicate — needed by `pg_isready` in the entrypoint) |
| `POD_NAME` | Downward API: `metadata.name` (pod name) |
| `HOSTNAME` | Downward API: `spec.nodeName` (node name — note: overrides the container's `$HOSTNAME`) |

#### Health probes

| Probe | Endpoint | Timing | Behaviour on failure |
|-------|----------|--------|---------------------|
| Startup | `GET /healthz` | period=10s, failureThreshold=30 | Pod killed after 300 s if never healthy |
| Readiness | `GET /readyz` | initialDelay=20s, period=10s | Pod removed from service endpoints; traffic stops |
| Liveness | `GET /healthz` | initialDelay=60s, period=20s | Pod restarted |

The startup probe gives the API up to 300 seconds to start (covering DB wait + Alembic migration time). Only after the startup probe succeeds does Kubernetes begin evaluating readiness and liveness probes.

`/readyz` runs `SELECT 1` against PostgreSQL. If the DB is unreachable the probe returns 503 and the pod is removed from the load balancer until the DB recovers.

#### Resource limits

| | CPU | Memory |
|-|-----|--------|
| Requests | `100m` | `128Mi` |
| Limits | `500m` | `512Mi` |

#### Security context

```yaml
securityContext:
  runAsUser: 1001
  runAsGroup: 1001
  fsGroup: 1001
```

Matches the `appuser` created in the Dockerfile.

### `api/service.yaml`

```yaml
kind: Service
name: db-api
type: ClusterIP
port: 80 → targetPort: http (8000)
```

The nginx ingress routes `path: /api` to `db-api:80`.

---

## Frontend (`frontend/`)

### `frontend/deployment.yaml`

**Image**: `ghcr.io/dabeastnet/db-frontend:v3`
**Replicas**: 1

#### Health probes

| Probe | Endpoint | Initial delay | Period |
|-------|----------|--------------|--------|
| Readiness | `GET /` | 10 s | 10 s |
| Liveness | `GET /` | 20 s | 20 s |

#### Resource limits

| | CPU | Memory |
|-|-----|--------|
| Requests | `50m` | `64Mi` |
| Limits | `200m` | `256Mi` |

### `frontend/service.yaml`

```yaml
kind: Service
name: db-frontend
type: ClusterIP
port: 80 → targetPort: http (8080)
```

The nginx ingress routes `path: /` to `db-frontend:80`.

---

## PostgreSQL (`postgres/postgres.yaml`)

Three resources in one file:

### PersistentVolume `db-postgres-pv`

```yaml
capacity: 1Gi
accessModes: [ReadWriteOnce]
persistentVolumeReclaimPolicy: Retain
storageClassName: manual
hostPath: /mnt/postgres-data
```

`/mnt/postgres-data` is created by `provision-common.sh` on every node. `storageClassName: manual` is a custom label used to bind this PV to its PVC. `Retain` means the data is not deleted when the PVC is removed.

### PersistentVolumeClaim `db-postgres-pvc`

```yaml
accessModes: [ReadWriteOnce]
storage: 1Gi
storageClassName: manual
```

Binds to `db-postgres-pv`.

### StatefulSet `db-postgres`

- **Image**: `postgres:16-alpine`
- **Image pull policy**: `IfNotPresent`
- **Port**: 5432
- **Security context**: `fsGroup: 999` (PostgreSQL default GID)
- **Volume mount**: `/var/lib/postgresql/data` ← `db-postgres-pvc`
- **Env vars**: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` from ConfigMap/Secret

### Service `db-postgres`

```yaml
kind: Service
name: db-postgres
type: ClusterIP
port: 5432 → targetPort: 5432
```

DNS name inside the cluster: `db-postgres.db-stack.svc.cluster.local`. The API uses `DB_HOST=db-postgres` which resolves to this service within the `db-stack` namespace.

---

## Ingress (`ingress/ingress.yaml`)

Uses `ingressClassName: nginx` (served by the `db-ingress-nginx` Helm release).

```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-redirect: "false"
  nginx.ingress.kubernetes.io/proxy-body-size: 4m
```

### Routing rules

**Rule 1 — named host `project.beckersd.com`** (used via Cloudflare Tunnel):

| Path | PathType | Backend |
|------|----------|---------|
| `/api` | Prefix | `db-api:80` |
| `/` | Prefix | `db-frontend:80` |

**Rule 2 — catch-all (no host)** (used for local access via `localhost:18080`):

| Path | PathType | Backend |
|------|----------|---------|
| `/api` | Prefix | `db-api:80` |
| `/` | Prefix | `db-frontend:80` |

The catch-all rule matches requests with any `Host` header (including `localhost`, IP addresses, and unknown hostnames). This is what makes `http://localhost:18080` work in the Vagrant environment without setting a custom Host header.

### TLS (commented out)

The TLS section and the `cert-manager.io/cluster-issuer` annotation are commented out. To enable HTTPS via cert-manager:

1. Install cert-manager and apply `k8s/cert-manager/clusterissuer.yaml`
2. Uncomment the TLS block and `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation
3. Change `ssl-redirect` to `"true"`

---

## cert-manager (`cert-manager/clusterissuer.yaml`)

Two `ClusterIssuer` resources for Let's Encrypt ACME:

| Resource | ACME server | Use |
|----------|-------------|-----|
| `letsencrypt-prod` | `acme-v02.api.letsencrypt.org` | Real certificates (rate-limited) |
| `letsencrypt-staging` | `acme-staging-v02.api.letsencrypt.org` | Test certificates (no rate limits) |

Both use HTTP-01 challenge class with `ingressClass: nginx`.

**Before use**:
1. Replace `admin@example.com` with a real email address in both issuers
2. Install cert-manager CRDs: `helm install cert-manager jetstack/cert-manager --set installCRDs=true`
3. Apply this file: `kubectl apply -f k8s/cert-manager/clusterissuer.yaml`

The apply in `deploy-k8s.sh` is wrapped in a non-fatal block and silently skipped if the CRDs are not installed.

---

## Cloudflare Tunnel (`cloudflared/deployment.yaml`)

### Secret `db-cloudflared-token`

Stores the Cloudflare Tunnel token in the `db-stack` namespace:

```yaml
kind: Secret
name: db-cloudflared-token
stringData:
  token: "<tunnel-token>"
```

### Deployment `db-cloudflared`

- **Image**: `cloudflare/cloudflared:latest`
- **Replicas**: 1
- **Namespace**: `db-stack`
- **Command**: `tunnel --no-autoupdate run`
- **Token**: injected via `TUNNEL_TOKEN` environment variable from the Secret

The pod maintains a persistent outbound connection to Cloudflare's network. Incoming requests for `project.beckersd.com` and `argocd.beckersd.com` are tunnelled to this pod, which forwards them to `db-ingress-nginx-controller.ingress-nginx.svc.cluster.local` (configured in the Cloudflare dashboard, not in these manifests).

**Resource limits**:

| | CPU | Memory |
|-|-----|--------|
| Requests | `50m` | `64Mi` |
| Limits | `200m` | `128Mi` |

---

## ArgoCD Application (`argocd/application.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: db-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/dabeastnet/db-k8s-stack.git
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: db-stack
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**What each field does**:

| Field | Value | Effect |
|-------|-------|--------|
| `repoURL` | GitHub repo URL | ArgoCD polls this repository |
| `targetRevision` | `HEAD` | Always tracks the latest commit on the default branch |
| `path` | `k8s` | Only manifests in the `k8s/` subdirectory are applied |
| `destination.server` | `https://kubernetes.default.svc` | In-cluster deployment |
| `destination.namespace` | `db-stack` | Default namespace for resources that don't specify one |
| `automated.prune` | `true` | Resources deleted from Git are also deleted from the cluster |
| `automated.selfHeal` | `true` | Manual changes to the cluster are reverted to match Git |
| `CreateNamespace` | `true` | ArgoCD creates the `db-stack` namespace if it doesn't exist |

**Apply this manifest** once after provisioning to activate GitOps:
```bash
kubectl apply -f k8s/argocd/application.yaml
```

ArgoCD checks for changes approximately every 3 minutes. To trigger an immediate sync:
```bash
kubectl -n argocd patch app db-app -p '{"operation": {"sync": {}}}' --type merge
```

---

## Deploying

Use the deploy script from the repository root:

```bash
./deploy-k8s.sh
```

Order of operations in `deploy-k8s.sh`:

1. `namespace.yaml`
2. `secret.example.yaml` + `configmap.yaml`
3. `postgres/postgres.yaml`
4. `api/deployment.yaml` + `api/service.yaml`
5. `frontend/deployment.yaml` + `frontend/service.yaml`
6. `cert-manager/clusterissuer.yaml` (non-fatal — skipped if CRDs absent)
7. `ingress/ingress.yaml`
8. `monitoring/namespace.yaml` + monitoring stack
9. `monitoring/service-monitor.yaml` (non-fatal — skipped if CRDs absent)
10. `cloudflared/deployment.yaml`
11. `argocd/application.yaml` (non-fatal — skipped if ArgoCD CRDs absent)

---

## Useful kubectl commands

```bash
# Check all resources in the application namespace
kubectl get all -n db-stack

# Watch pod status
kubectl get pods -n db-stack -w

# Verify API replicas are spread across nodes
kubectl get pods -n db-stack -l app=db-api -o wide

# Check ingress
kubectl get ingress -n db-stack

# View API logs
kubectl logs -n db-stack -l app=db-api --tail=50

# Describe a crashing pod
kubectl describe pod -n db-stack <pod-name>

# Check ArgoCD sync status
kubectl get application -n argocd db-app

# Check Cloudflare tunnel logs
kubectl logs -n db-stack -l app=db-cloudflared --tail=20
```

## Relationship to other components

| Component | Relationship |
|-----------|-------------|
| `vagrant/provision-master.sh` | Calls `deploy-k8s.sh` automatically during cluster provisioning |
| `helm/` | Helm releases (`db-ingress-nginx`, `db-argocd`) must be installed before these manifests |
| `api/` | Source code and Dockerfile for the `db-api` image |
| `frontend/` | Source code and Dockerfile for the `db-frontend` image |
| `k8s/monitoring/` | Monitoring stack (see dedicated README) |
