# helm — Helm Chart Values

## Purpose

This directory holds Helm values files used when installing third-party charts on the cluster. Helm is installed on the control plane node by `vagrant/provision-master.sh` and the releases are created during provisioning.

## Contents

| File/Directory | Description |
|----------------|-------------|
| `argocd-values.yaml` | Values for the `argo/argo-cd` Helm chart (release name `db-argocd`) |
| `db-app/` | Placeholder directory for a future application Helm chart |

## ArgoCD (`argocd-values.yaml`)

### Helm release

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install db-argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f helm/argocd-values.yaml
```

This creates the `db-argocd` Helm release in the `argocd` namespace. All ArgoCD component pods will be named with the `db-argocd-` prefix (e.g., `db-argocd-server`, `db-argocd-application-controller`).

### Full values file annotated

```yaml
global:
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"

server:
  extraArgs:
    - --insecure
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: argocd.beckersd.com
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "false"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
  service:
    type: ClusterIP

controller:
  replicas: 1
```

### Key configuration

| Section | Setting | Value | Reason |
|---------|---------|-------|--------|
| `global.tolerations` | control-plane taint | `NoSchedule` toleration | Allows ArgoCD pre-install Jobs to schedule on cp1 before workers join |
| `server.extraArgs` | `--insecure` | enabled | ArgoCD serves plain HTTP; TLS is terminated by Cloudflare Tunnel |
| `server.ingress.enabled` | `true` | — | Creates a `db-argocd-server` Ingress resource |
| `server.ingress.ingressClassName` | `nginx` | — | Uses the `db-ingress-nginx` controller |
| `server.ingress.hostname` | `argocd.beckersd.com` | — | Public hostname via Cloudflare Tunnel; must be a direct subdomain of `beckersd.com` (Cloudflare Universal SSL wildcard `*.beckersd.com` does not cover two levels deep) |
| `server.ingress.annotations` | `ssl-redirect: "false"`, `backend-protocol: "HTTP"` | — | Prevents nginx from redirecting to HTTPS; tells nginx to use HTTP when proxying to ArgoCD backend |
| `server.service.type` | `ClusterIP` | — | ArgoCD is not directly exposed; access is via the ingress |
| `controller.replicas` | `1` | — | Single application controller sufficient for this dev cluster |

### Why `--insecure`?

ArgoCD by default generates a self-signed certificate and redirects all HTTP to HTTPS. In this setup, Cloudflare Tunnel terminates TLS at the Cloudflare edge and forwards plain HTTP to the `db-cloudflared` pod, which forwards it to the `db-ingress-nginx` controller, which proxies it to ArgoCD. Running ArgoCD in `--insecure` mode prevents a redirect loop and avoids certificate validation failures inside the cluster.

### Why `global.tolerations`?

At the time `provision-master.sh` runs on cp1, the worker nodes have not yet joined the cluster. The control-plane node carries a taint `node-role.kubernetes.io/control-plane:NoSchedule` that prevents regular pods from scheduling on it. The ArgoCD Helm chart includes pre-install Jobs (for CRD management) that must complete before the install proceeds. Without the toleration, these Jobs cannot schedule on cp1 and the `helm upgrade --install` command times out.

The toleration is intentionally applied at `global` scope so it covers all ArgoCD components (server, controller, repo-server, dex), though in practice only the pre-install Jobs need it — the regular pods will schedule on the workers once they join.

### ArgoCD chart version note

This configuration is compatible with the ArgoCD Helm chart **v9.x**. In v9.x the ingress uses `hostname:` (a single string) rather than the older `hosts:` array. Using `hosts:` in v9.x will result in the ingress being created with a placeholder hostname (`argocd.example.com`) instead of the configured value.

### Enabling HTTPS (optional)

Once cert-manager is installed, uncomment the following annotations in `argocd-values.yaml` and run `helm upgrade`:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

This will request a Let's Encrypt certificate for `argocd.beckersd.com` and configure nginx to redirect HTTP to HTTPS.

### Accessing ArgoCD

| Access method | URL |
|---------------|-----|
| Public (via Cloudflare Tunnel) | `https://argocd.beckersd.com` |

Retrieve the initial admin password (changes on each cluster rebuild):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## Other Helm releases

The following charts are installed by `vagrant/provision-master.sh` but do not have separate values files (they use only `--set` flags):

### db-ingress-nginx

```bash
helm upgrade --install db-ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.admissionWebhooks.enabled=false
```

- NodePort mode because the cluster has no cloud load-balancer
- Admission webhooks disabled to prevent scheduling failures during initial provisioning
- Controller service DNS: `db-ingress-nginx-controller.ingress-nginx.svc.cluster.local`

## Relationship to other components

- **`vagrant/provision-master.sh`** — installs all Helm releases during cluster provisioning
- **`k8s/argocd/application.yaml`** — applied after ArgoCD is running to enable GitOps sync
- **`k8s/ingress/ingress.yaml`** — uses `ingressClassName: nginx` which matches the `db-ingress-nginx` controller
