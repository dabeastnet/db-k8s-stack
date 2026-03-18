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
helm upgrade --install db-argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f helm/argocd-values.yaml
```

### Key configuration

| Section | Setting | Value | Reason |
|---------|---------|-------|--------|
| `global.tolerations` | control-plane taint | `NoSchedule` toleration | Allows ArgoCD pre-install Jobs to schedule on cp1 before workers join |
| `server.extraArgs` | `--insecure` | enabled | ArgoCD serves plain HTTP; TLS is terminated by Cloudflare Tunnel |
| `server.ingress.enabled` | `true` | — | Creates a `db-argocd-server` Ingress |
| `server.ingress.ingressClassName` | `nginx` | — | Uses the `db-ingress-nginx` controller |
| `server.ingress.hostname` | `argocd.beckersd.com` | — | Public hostname via Cloudflare Tunnel |
| `server.ingress.annotations` | `ssl-redirect: "false"`, `backend-protocol: "HTTP"` | — | Prevents nginx from doing its own SSL redirect; tells nginx to talk HTTP to ArgoCD |
| `server.service.type` | `ClusterIP` | — | ArgoCD is not directly exposed; access is via the ingress |
| `controller.replicas` | `1` | — | Single application controller sufficient for dev cluster |

### Why `--insecure`?

ArgoCD by default generates a self-signed certificate and redirects all HTTP to HTTPS. In this setup, Cloudflare Tunnel terminates TLS at the Cloudflare edge and forwards plain HTTP to the cloudflared pod, which forwards it to the nginx ingress, which proxies it to ArgoCD. Running ArgoCD in `--insecure` mode prevents a redirect loop and avoids certificate issues inside the cluster.

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
