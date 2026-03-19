# Verification Guide

This document explains how to verify every requirement of the db-k8s-stack project. Follow the steps in order — the cluster must be running before most verifications are possible.

## Prerequisites

Start the cluster if it is not already running:

```bash
vagrant up
```

Provisioning takes 10–20 minutes. When complete, all three VMs (`cp1`, `worker1`, `worker2`) are up and the full stack is deployed.

---

## 1. Cluster is running (10/20 baseline)

### 1.1 Verify all nodes are Ready

```bash
vagrant ssh cp1 -- kubectl get nodes -o wide
```

Expected output — three nodes, all `Ready`:

```
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP      ...
cp1       Ready    control-plane   Xm    v1.29.x   192.168.56.10    ...
worker1   Ready    <none>          Xm    v1.29.x   192.168.56.20    ...
worker2   Ready    <none>          Xm    v1.29.x   192.168.56.21    ...
```

### 1.2 Verify all application pods are Running

```bash
vagrant ssh cp1 -- kubectl get pods -n db-stack -o wide
```

Expected: `db-api` (×2), `db-frontend` (×1), `db-postgres-0` (×1) — all `Running`.

### 1.3 Open the frontend in a browser

Navigate to **http://localhost:18080**

You should see:

```
Welcome, <name>!
API Container ID: <container-id>
```

Both values are fetched live from the API. If they show `Unavailable`, the API or database is not yet ready — wait a minute and refresh.

---

## 2. Web frontend — JavaScript page and automatic layout refresh

### 2.1 Verify the page loads

Open **http://localhost:18080** in a browser. The page should display a greeting and a container ID.

### 2.2 Verify automatic layout refresh

The frontend polls `version.txt` every 15 seconds. To trigger a reload:

1. Edit `frontend/static/version.txt` — change `1` to `2`
2. Rebuild and push the image, then restart the deployment:

   ```bash
   vagrant ssh cp1 -- kubectl rollout restart deployment db-frontend -n db-stack
   ```

3. Keep the browser tab open. Within 15 seconds the page reloads automatically.

---

## 3. API endpoints

### 3.1 `/api/name` — retrieves name from the database

```bash
curl -s http://localhost:18080/api/name
# { "name": "Dieter Beckers" }
```

### 3.2 `/api/container-id` — retrieves the API container ID

```bash
curl -s http://localhost:18080/api/container-id
# { "container_id": "abc123def456", "pod_name": "db-api-xxxxx", "hostname": "worker1" }
```

The `hostname` field shows which worker node the pod is running on.

### 3.3 Verify the name changes after a database update

See [section 5](#5-name-change-reflected-on-page-refresh) below.

---

## 4. Cluster topology — kubeadm, 1 control plane + 2 workers (+4/20)

### 4.1 Confirm the kubeadm cluster topology

```bash
vagrant ssh cp1 -- kubectl get nodes -o wide
```

Three nodes must appear: `cp1` (control-plane), `worker1`, `worker2`.

### 4.2 Confirm control-plane components are healthy

```bash
vagrant ssh cp1 -- kubectl get pods -n kube-system
```

All `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `etcd`, and `coredns` pods must be `Running`.

### 4.3 Confirm CNI (Flannel) is running on all nodes

```bash
vagrant ssh cp1 -- kubectl get pods -n kube-flannel -o wide
```

One `kube-flannel-ds` pod per node, all `Running`.

### 4.4 Confirm Flannel is using the correct network interface

```bash
vagrant ssh cp1 -- bridge fdb show dev flannel.1
```

All `dst` entries must be `192.168.56.x` addresses (the host-only network), **not** `10.0.2.x` (the NAT network). If they show `10.0.2.x`, cross-node traffic is broken — re-provision cp1.

---

## 5. Name change reflected on page refresh

### 5.1 Load database credentials into your shell

Run this on **cp1** (must be sourced, not executed):

```bash
vagrant ssh cp1
source /vagrant/vagrant/scripts/load_env_var.sh
```

### 5.2 Update the name in the database

```bash
bash /vagrant/vagrant/scripts/update_name.sh "Alice"
# Name updated to Alice
```

### 5.3 Verify the change

```bash
curl -s http://localhost:18080/api/name
# { "name": "Alice" }
```

Refresh **http://localhost:18080** in the browser — the displayed name changes to **Alice**.

To restore the original name:

```bash
bash /vagrant/vagrant/scripts/update_name.sh "Dieter Beckers"
```

---

## 6. API load balanced across nodes (+2/20)

The API runs 2 replicas with `topologySpreadConstraints` ensuring one pod on each worker node.

### 6.1 Verify replicas are spread across nodes

```bash
vagrant ssh cp1 -- kubectl get pods -n db-stack -l app=db-api -o wide
```

Expected: one pod on `worker1`, one pod on `worker2`.

### 6.2 Verify load balancing via the ingress

Make several requests and observe that the `hostname` field alternates between `worker1` and `worker2`:

```PowerShell
  1..6 | ForEach-Object {
      (curl "http://localhost:18080/api/container-id") -match '"hostname":"([^"]*)"' | Out-Null
      $matches[0]
  }
```

You should see responses from both worker nodes. The nginx ingress controller round-robins requests between the two API pods.

### 6.3 Verify the ingress is configured

```bash
vagrant ssh cp1 -- kubectl get ingress -n db-stack
vagrant ssh cp1 -- kubectl describe ingress db-app -n db-stack
```

Two rules should appear: one for `project.beckersd.com` and one catch-all (no host).

---

## 7. Health check with automatic restart (+1/20)

The API has three probes:

| Probe | Endpoint | Behaviour on failure |
|-------|----------|---------------------|
| Startup | `/healthz` | Pod killed if not healthy within 300 s |
| Readiness | `/readyz` | Pod removed from load balancer |
| Liveness | `/healthz` | Pod restarted |

### 7.1 Verify probes are configured

```bash
vagrant ssh cp1 -- kubectl describe deployment db-api -n db-stack | grep -A 10 "Liveness\|Readiness\|Startup"
```

All three probes should be listed.

### 7.2 Verify probe endpoints respond

```bash
curl -s http://localhost:18080/healthz
# { "status": "ok" }

curl -s http://localhost:18080/readyz
# { "status": "ok" }
```

### 7.3 Observe automatic restart (simulation)

Check the restart count of the API pods:

```bash
vagrant ssh cp1 -- kubectl get pods -n db-stack -l app=db-api
```

The `RESTARTS` column shows how many times Kubernetes has restarted each pod due to a failed liveness probe. In a healthy cluster this should be `0`.

To simulate an unhealthy pod and watch the restart:

```bash
# Force-kill the process inside one API pod
vagrant ssh cp1 -- kubectl exec -n db-stack \
  $(kubectl get pods -n db-stack -l app=db-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
    kubectl get pods -n db-stack -l app=db-api -o jsonpath='{.items[0].metadata.name}') \
  -- kill 1

# Watch Kubernetes restart it automatically
vagrant ssh cp1 -- kubectl get pods -n db-stack -l app=db-api -w
```

Within ~60 seconds (liveness probe `initialDelaySeconds`) the pod restarts and returns to `Running`.

---

## 8. Prometheus monitoring (+1/20)

### 8.1 Open the Prometheus UI

Navigate to **http://localhost:19090**

### 8.2 Verify all scrape targets are UP

Go to **Status → Targets** (http://localhost:19090/targets).

All four jobs should show **UP**:

| Job | Target |
|-----|--------|
| `prometheus` | `localhost:9090` |
| `kube-state-metrics` | `db-kube-state-metrics.monitoring:8080` |
| `db-api` | `db-api.db-stack:80` |
| `kubernetes-nodes` | All three nodes on port `9100` |

### 8.3 Query application metrics

In the Prometheus query box, run:

```
db_api_requests_total
```

You should see counters for each API endpoint (`/api/name`, `/api/container-id`). Make a few API calls and re-run the query to see the counters increment.

### 8.4 Query node metrics

```
100 * (1 - avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

This returns CPU usage percentage per node. All three nodes (`cp1`, `worker1`, `worker2`) should appear.

### 8.5 Open Grafana

Navigate to **http://localhost:13000**

- Username: `admin`
- Password: `admin`

The pre-built dashboard **db-k8s-stack Overview** should be visible under **Dashboards**. It shows:
- Running pods in `db-stack`
- Ready nodes
- API request rate
- Node CPU and memory usage

---

## 9. HTTPS with valid certificate (+2/20)

HTTPS is provided by Cloudflare Tunnel — the cluster does not need a public IP. Cloudflare holds the TLS certificate.

### 9.1 Verify the public URL is accessible over HTTPS

Open **https://project.beckersd.com** in a browser.

- The padlock icon should be present — the certificate is issued by Cloudflare
- The page content is identical to the local `http://localhost:18080` view

### 9.2 Verify the Cloudflare tunnel pod is running

```bash
vagrant ssh cp1 -- kubectl get pods -n db-stack -l app=db-cloudflared
```

One pod, `Running`.

### 9.3 Verify the tunnel is connected

```bash
vagrant ssh cp1 -- kubectl logs -n db-stack -l app=db-cloudflared --tail=20
```

Look for a line containing `Connection registered` or `Registered tunnel connection`. No `error` lines should be present.

### 9.4 Verify cert-manager ClusterIssuers are configured

```bash
vagrant ssh cp1 -- kubectl get clusterissuer
```

Two issuers should be listed: `letsencrypt-prod` and `letsencrypt-staging`.

> **Note**: cert-manager itself is not installed by default in this cluster — TLS is handled by Cloudflare. The ClusterIssuers are pre-configured so cert-manager can be enabled at any time by running `helm install cert-manager` and uncommenting the TLS block in `k8s/ingress/ingress.yaml`.

---

## 10. ArgoCD via Helm + GitOps workflow (+4/20)

### 10.1 Verify ArgoCD pods are running

```bash
vagrant ssh cp1 -- kubectl get pods -n argocd
```

All ArgoCD component pods (`db-argocd-server`, `db-argocd-application-controller`, `db-argocd-repo-server`, `db-argocd-redis`) should be `Running`.

### 10.2 Get the ArgoCD admin password

The initial admin password is auto-generated on cluster creation and stored in a Kubernetes Secret:

```bash
vagrant ssh cp1 

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

```

Copy the printed password — you will need it to log in.

### 10.3 Open the ArgoCD UI

Navigate to **https://argocd.beckersd.com**

- Username: `admin`
- Password: the value from step 10.2

### 10.4 Verify the ArgoCD Application is synced

In the UI, the `db-app` application should show:

- **Status**: `Synced`
- **Health**: `Healthy`
- **Source**: `https://github.com/dabeastnet/db-k8s-stack.git` → `k8s/`

Or via the CLI:

```bash
vagrant ssh cp1 -- kubectl get application -n argocd db-app
```

The `SYNC STATUS` column should show `Synced` and `HEALTH STATUS` should show `Healthy`.

### 10.5 Verify the Helm release

```bash
vagrant ssh cp1 -- helm list -n argocd
```

The `db-argocd` release should appear with `STATUS: deployed`.

```bash
vagrant ssh cp1 -- helm list -n ingress-nginx
```

The `db-ingress-nginx` release should also appear with `STATUS: deployed`.

### 10.6 Verify GitOps workflow end-to-end

1. Make a change to any manifest in `k8s/` — for example, add a label to `k8s/configmap.yaml`
2. Commit and push to `main`:

   ```bash
   git add k8s/configmap.yaml
   git commit -m "test: add label to verify GitOps"
   git push
   ```

3. Wait up to 3 minutes (ArgoCD polls every ~3 minutes), or trigger an immediate sync:

   ```bash
   vagrant ssh cp1 -- kubectl -n argocd patch app db-app \
     -p '{"operation": {"sync": {}}}' --type merge
   ```

4. In the ArgoCD UI, observe the sync operation. The change appears in the cluster without any manual `kubectl apply`.

5. Revert the test change:

   ```bash
   git revert HEAD --no-edit
   git push
   ```

---

## 11. Summary checklist

| Requirement | Verification method | Expected result |
|-------------|---------------------|-----------------|
| Cluster running (10/20) | `kubectl get nodes` | 3 nodes `Ready` |
| Frontend page | Browser → `http://localhost:18080` | Greeting + container ID visible |
| Auto layout refresh | Edit `version.txt`, restart deployment | Page reloads within 15 s |
| `/api/name` | `curl .../api/name` | `{"name": "..."}` |
| `/api/container-id` | `curl .../api/container-id` | Container ID + node hostname |
| Name update via DB | `update_name.sh "Alice"` + curl | Returns new name |
| HTTPS (+2) | Browser → `https://project.beckersd.com` | Padlock, valid cert |
| Load balancing (+2) | `kubectl get pods -o wide` + repeated curl | Pods on worker1 + worker2, alternating hostnames |
| Health probes (+1) | `kubectl describe deployment db-api` | Startup, readiness, liveness configured |
| Prometheus (+1) | Browser → `http://localhost:19090/targets` | All 4 jobs `UP` |
| Grafana dashboard | Browser → `http://localhost:13000` | `db-k8s-stack Overview` dashboard populated |
| kubeadm cluster (+4) | `kubectl get nodes -o wide` | cp1 + worker1 + worker2, correct IPs |
| ArgoCD via Helm (+4) | `helm list -n argocd` | `db-argocd` deployed |
| GitOps sync | Push change to `k8s/`, observe ArgoCD UI | Change applied automatically |
| ArgoCD UI | Browser → `https://argocd.beckersd.com` | Login works, `db-app` Synced + Healthy |
| `db-` prefix | `kubectl get pods -A` | All custom pods named `db-*` |

---

## Troubleshooting quick reference

**Pods stuck in `Pending`**

```bash
vagrant ssh cp1 -- kubectl describe pod <pod-name> -n db-stack
```

Common cause: `worker2` not yet joined. Fix:

```bash
vagrant up worker2
```

**Cross-node requests failing / DNS errors inside cluster**

```bash
vagrant ssh cp1 -- bridge fdb show dev flannel.1
```

If `dst` shows `10.0.2.x`, Flannel is on the wrong NIC. Re-provision cp1:

```bash
vagrant provision cp1
```

**ArgoCD UI shows `OutOfSync`**

```bash
vagrant ssh cp1 -- kubectl -n argocd patch app db-app \
  -p '{"operation": {"sync": {}}}' --type merge
```

**Cloudflare tunnel not connecting**

```bash
vagrant ssh cp1 -- kubectl logs -n db-stack -l app=db-cloudflared --tail=30
```

If the token is invalid, update `k8s/cloudflared/deployment.yaml` line 9 with the new token and re-apply:

```bash
vagrant ssh cp1 -- kubectl apply -f /vagrant/k8s/cloudflared/deployment.yaml
vagrant ssh cp1 -- kubectl rollout restart deployment db-cloudflared -n db-stack
```

**Retrieve ArgoCD admin password again**

```bash
vagrant ssh cp1 -- kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```
