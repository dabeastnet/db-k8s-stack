# k8s — Kubernetes Manifests

## Purpose

This directory contains all Kubernetes manifests for deploying and operating the db-k8s-stack on a kubeadm cluster. Manifests are organised by component and applied by `deploy-k8s.sh` or synchronised automatically by ArgoCD.

## Directory structure

```
k8s/
├── namespace.yaml          # db-stack namespace
├── configmap.yaml          # Non-secret application configuration
├── secret.example.yaml     # Secret template (do not commit real secrets)
├── api/
│   ├── deployment.yaml     # db-api Deployment (2 replicas, spread constraints, probes)
│   └── service.yaml        # db-api ClusterIP Service (port 80 → container 8000)
├── frontend/
│   ├── deployment.yaml     # db-frontend Deployment (1 replica, probes)
│   └── service.yaml        # db-frontend ClusterIP Service (port 80 → container 8080)
├── postgres/
│   └── postgres.yaml       # PersistentVolume, PVC, StatefulSet, ClusterIP Service
├── ingress/
│   └── ingress.yaml        # nginx Ingress with host rules and catch-all
├── cert-manager/
│   └── clusterissuer.yaml  # Let's Encrypt ClusterIssuers (prod + staging)
├── cloudflared/
│   └── deployment.yaml     # Cloudflare Tunnel agent + token Secret
├── argocd/
│   └── application.yaml    # ArgoCD Application (GitOps sync from this repo)
└── monitoring/
    ├── namespace.yaml       # monitoring namespace
    ├── prometheus.yaml      # Prometheus ConfigMap, RBAC, Deployment, NodePort Service
    ├── kube-state-metrics.yaml  # kube-state-metrics Deployment and Service
    ├── node-exporter.yaml   # node-exporter DaemonSet (runs on all nodes)
    ├── grafana.yaml         # Grafana Deployment, ConfigMaps, NodePort Service
    └── service-monitor.yaml # ServiceMonitor for scraping db-api (Prometheus Operator CRD)
```

## Namespaces

| Namespace | Contents |
|-----------|---------|
| `db-stack` | Application workloads: frontend, API, PostgreSQL, Cloudflare tunnel |
| `monitoring` | Prometheus, Grafana, kube-state-metrics, node-exporter |
| `ingress-nginx` | nginx ingress controller (Helm-managed, release `db-ingress-nginx`) |
| `argocd` | ArgoCD (Helm-managed, release `db-argocd`) |

## Core application resources

### ConfigMap (`configmap.yaml`)

Provides non-sensitive database connection parameters to the API:

| Key | Value |
|-----|-------|
| `DB_HOST` | `db-postgres` |
| `DB_PORT` | `5432` |
| `DB_NAME` | `demo` |

### Secret (`secret.example.yaml`)

Template for the `db-app-secret` Secret. Contains `DB_USER` and `DB_PASSWORD` using `stringData`. **Copy and rename this file; never commit real credentials.**

Default development values: `demo` / `demo`.

### API Deployment (`api/deployment.yaml`)

- **Image**: `ghcr.io/dabeastnet/db-api:v6`
- **Replicas**: 2
- **Topology spread**: `maxSkew=1` over `kubernetes.io/hostname` ensures one replica per worker node
- **Startup probe**: `GET /healthz` — up to 300 s grace period
- **Readiness probe**: `GET /readyz` — fails if PostgreSQL is unreachable
- **Liveness probe**: `GET /healthz` — triggers restart if the process becomes unresponsive
- **Security context**: `runAsUser: 1001`, `runAsGroup: 1001`, `fsGroup: 1001`
- **Env vars**: `DB_*` from ConfigMap/Secret; `POD_NAME` and `HOSTNAME` from downward API

### PostgreSQL (`postgres/postgres.yaml`)

- **StatefulSet** `db-postgres`: 1 replica, `postgres:16-alpine`
- **PersistentVolume** `db-postgres-pv`: 1 Gi hostPath at `/mnt/postgres-data` (created by `provision-common.sh`)
- **PersistentVolumeClaim** `db-postgres-pvc`: binds to the above PV via `storageClassName: manual`
- **Service** `db-postgres`: ClusterIP on port 5432

### Ingress (`ingress/ingress.yaml`)

Uses `ingressClassName: nginx` (served by the `db-ingress-nginx` Helm release).

Two rules are defined:

1. **Named host** `project.beckersd.com` — routes `/api` to `db-api:80` and `/` to `db-frontend:80`
2. **Catch-all** (no host) — same routing, matches `localhost`, IP addresses, and any unrecognised hostname (used for local access via `http://localhost:18080`)

TLS is commented out pending cert-manager activation.

### Cloudflare Tunnel (`cloudflared/deployment.yaml`)

- **Secret** `db-cloudflared-token` — stores the Cloudflare Tunnel token
- **Deployment** `db-cloudflared` — runs `cloudflare/cloudflared:latest` with `tunnel --no-autoupdate run`; reads the token from the Secret via the `TUNNEL_TOKEN` environment variable
- The tunnel connects outbound to Cloudflare; traffic routing (`project.beckersd.com` → nginx ingress) is configured in the Cloudflare Zero Trust dashboard

### cert-manager (`cert-manager/clusterissuer.yaml`)

Defines two `ClusterIssuer` resources for Let's Encrypt:

| Issuer | Server | Use |
|--------|--------|-----|
| `letsencrypt-prod` | `https://acme-v02.api.letsencrypt.org/directory` | Production certificates |
| `letsencrypt-staging` | `https://acme-staging-v02.api.letsencrypt.org/directory` | Testing (no rate limits) |

**Before use**: update `spec.acme.email` in `clusterissuer.yaml` to a real email address. Also uncomment the TLS section in `ingress/ingress.yaml` and add the `cert-manager.io/cluster-issuer` annotation.

Requires cert-manager CRDs to be installed; the apply is wrapped in a non-fatal block in `deploy-k8s.sh`.

### ArgoCD Application (`argocd/application.yaml`)

Declares the `db-app` ArgoCD Application:

- **Source**: `https://github.com/dabeastnet/db-k8s-stack.git`, path `k8s/`, branch `HEAD`
- **Destination**: `https://kubernetes.default.svc`, namespace `db-stack`
- **Sync policy**: automated with `prune: true` and `selfHeal: true`

Apply this manifest after ArgoCD is running to activate the GitOps workflow:

```bash
kubectl apply -f k8s/argocd/application.yaml
```

## Deploying

Use the provided script from the repository root:

```bash
./deploy-k8s.sh
```

This applies all manifests in the correct order: namespace → secrets/configmap → postgres → api → frontend → cert-manager (optional) → ingress → monitoring → cloudflared → argocd application.

## Relationship to other components

- **`vagrant/`** — The Vagrant provisioner (`provision-master.sh`) calls `deploy-k8s.sh` automatically after cluster initialisation.
- **`helm/`** — The Helm-managed components (ingress-nginx, ArgoCD) are installed by `provision-master.sh` before these manifests are applied.
- **`api/`** and **`frontend/`** — Source code for the images referenced in the Deployments.
