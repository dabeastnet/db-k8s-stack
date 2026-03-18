# vagrant — Cluster Provisioning

## Purpose

This directory contains all shell scripts that provision a three-node kubeadm Kubernetes cluster on VirtualBox. The `Vagrantfile` in the repository root drives the process. Running `vagrant up` from the repo root creates a fully functional cluster with the entire application stack deployed — no manual steps required after provisioning completes.

## Cluster topology

| VM | Role | Private IP | Memory | CPUs |
|----|------|-----------|--------|------|
| `cp1` | Control plane | `192.168.56.10` | 4096 MB | 2 |
| `worker1` | Worker | `192.168.56.20` | 4096 MB | 2 |
| `worker2` | Worker | `192.168.56.21` | 4096 MB | 2 |

All VMs run **Ubuntu 20.04 LTS** (`ubuntu/focal64`) and share the repository via a synced folder at `/vagrant`.

## Host port forwarding (on `cp1`)

| Host port | Guest NodePort | Service |
|-----------|---------------|---------|
| `18080` | `30080` | nginx ingress HTTP → frontend + API |
| `18443` | `30443` | nginx ingress HTTPS |
| `19090` | `30090` | Prometheus web UI |
| `13000` | `30030` | Grafana web UI |

All ports use `auto_correct: true` so Vagrant picks an alternative host port if the preferred one is occupied.

---

## Scripts

### `provision-common.sh` — all nodes

This script runs on **every node** (cp1, worker1, worker2) before any role-specific provisioning.

#### What it does, step by step

**1. Disable swap**
```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```
kubeadm requires swap to be off. The `sed` command comments out the swap entry so it stays disabled after reboots.

**2. Install base packages**
```bash
apt-get install -y apt-transport-https ca-certificates curl gnupg \
    lsb-release software-properties-common
```
Required for adding the Kubernetes APT repository with GPG verification.

**3. Load kernel modules**
```bash
modprobe overlay
modprobe br_netfilter
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```
- `overlay` — used by containerd for container layer storage
- `br_netfilter` — allows iptables to inspect bridged traffic (required for Kubernetes network policies and kube-proxy)

The `/etc/modules-load.d/k8s.conf` file ensures they're loaded on every boot.

**4. Set sysctl parameters**
```bash
cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```
These parameters are mandatory for Kubernetes networking to function correctly:
- `bridge-nf-call-iptables` / `bridge-nf-call-ip6tables` — makes iptables rules apply to bridged traffic (pods on the same node)
- `ip_forward` — enables IP packet forwarding between interfaces (required for pod routing)

**5. Install containerd**
```bash
apt-get install -y containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd
```
containerd is the container runtime. Enabling `SystemdCgroup = true` ensures containerd uses the same cgroup driver as kubelet (systemd), which is required for kubeadm clusters.

**6. Create PostgreSQL data directory**
```bash
mkdir -p /mnt/postgres-data
```
The PostgreSQL PersistentVolume in `k8s/postgres/postgres.yaml` uses `hostPath: /mnt/postgres-data`. This directory must exist on the node before the pod starts. The `fsGroup: 999` on the StatefulSet ensures the postgres container can write to it.

**7. Add Kubernetes v1.29 APT repository**
```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=...] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
    > /etc/apt/sources.list.d/kubernetes.list
```
Uses the official Kubernetes package repository for v1.29.

**8. Install Kubernetes tools**
```bash
apt-get install -y kubelet kubeadm kubectl cri-tools conntrack kubernetes-cni
```
- `kubelet` — the node agent that runs pods
- `kubeadm` — cluster bootstrap tool
- `kubectl` — CLI for interacting with the cluster
- `cri-tools` (`crictl`) — low-level container runtime inspection
- `conntrack` — required by kube-proxy for tracking connections
- `kubernetes-cni` — CNI plugin binaries

**9. Configure kubelet node IP**
```bash
PRIVATE_IP=$(hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.56\.')
echo "KUBELET_EXTRA_ARGS=--node-ip=$PRIVATE_IP" >/etc/default/kubelet
systemctl daemon-reload && systemctl restart kubelet
```
Vagrant VMs have two NICs. Without this setting, kubelet registers the node with the NAT IP (`10.0.2.x`), causing all three nodes to appear to have the same IP. Setting `--node-ip` to the host-only interface IP (`192.168.56.x`) gives each node a unique, routable address.

---

### `provision-master.sh` — cp1 only

This script runs **only on the control plane** (`cp1`) after `provision-common.sh`.

#### What it does, step by step

**1. kubeadm init**
```bash
APISERVER_IP=$(hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.56\.') || true
kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$APISERVER_IP"
```
Initialises the control plane. `--pod-network-cidr=10.244.0.0/16` matches Flannel's default range. `--apiserver-advertise-address` is set to the private IP so worker nodes can reach the API server.

**2. Set up kubeconfig**
```bash
mkdir -p /home/vagrant/.kube
cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
```
Makes `kubectl` work for the `vagrant` user without `sudo`.

**3. Install Flannel CNI**
```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```
Flannel provides VXLAN-based pod networking.

**4. Fix Flannel NIC selection**
```bash
kubectl patch daemonset kube-flannel-ds -n kube-flannel --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--iface=enp0s8"}]'
kubectl rollout status daemonset kube-flannel-ds -n kube-flannel --timeout=120s
```
Vagrant VMs have two NICs: `enp0s3` (VirtualBox NAT, `10.0.2.x`) and `enp0s8` (host-only, `192.168.56.x`). Flannel's auto-detection picks `enp0s3` by default. Because VirtualBox NAT cannot route traffic between VMs, VXLAN packets sent over `enp0s3` never arrive at other nodes — breaking all cross-node pod communication, DNS, and the API server.

The `--iface=enp0s8` argument forces Flannel to use the private network where VMs can reach each other. Without this fix, the cluster appears to initialise correctly but all cross-node connectivity fails silently.

**5. Install Helm**
```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```
Only installed on cp1 since workers do not manage charts.

**6. Install db-ingress-nginx**
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install db-ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.admissionWebhooks.enabled=false
```
- `NodePort` mode because there is no cloud load-balancer
- NodePorts 30080/30443 match the Vagrantfile port-forward configuration
- Admission webhooks disabled to avoid the pre-install Job failing to schedule (cp1 has a control-plane taint and no workers have joined yet)
- No `--wait` for the same scheduling reason; the pod starts once workers join

**7. Install db-argocd**
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install db-argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f /vagrant/helm/argocd-values.yaml
echo "Waiting for ArgoCD Application CRD to be registered..."
until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  sleep 3
done
```
The `argocd-values.yaml` includes `global.tolerations` for the control-plane taint, allowing the CRD-management pre-install Job to run on cp1. The CRD wait loop ensures the `application.yaml` manifest can be applied later without an "unknown kind" error.

**8. Generate join.sh**
```bash
kubeadm token create --print-join-command >"${JOIN_SCRIPT}"
chmod +x "${JOIN_SCRIPT}"
```
Writes the `kubeadm join` command to `/vagrant/join.sh` (visible on the host as `join.sh` in the repo root). The token is valid for 24 hours.

**9. Apply core manifests**
```bash
kubectl apply -f ${K8S_DIR}/namespace.yaml
kubectl apply -f ${K8S_DIR}/configmap.yaml
kubectl apply -f ${K8S_DIR}/secret.example.yaml   # only if db-app-secret doesn't already exist
kubectl apply -f ${K8S_DIR}/postgres/postgres.yaml
kubectl apply -f ${K8S_DIR}/api/service.yaml
kubectl apply -f ${K8S_DIR}/api/deployment.yaml
kubectl apply -f ${K8S_DIR}/frontend/service.yaml
kubectl apply -f ${K8S_DIR}/frontend/deployment.yaml
kubectl apply -f ${K8S_DIR}/ingress/ingress.yaml
```

**10. Run deploy-k8s.sh**
```bash
bash /vagrant/deploy-k8s.sh
```
Applies monitoring (Prometheus, Grafana, exporters), Cloudflare tunnel, and the ArgoCD Application manifest. Called via `bash` instead of executing directly to bypass the `noexec` flag that VirtualBox sets on the `/vagrant` mount on Windows hosts.

---

### `provision-worker.sh` — worker1 and worker2

```bash
APISERVER=192.168.56.10
until nc -z -w 3 "${APISERVER}" 6443 2>/dev/null; do
  echo "  API server not ready yet, retrying in 5s..."
  sleep 5
done
bash "${JOIN_SCRIPT}" --v=5
```

**Why the wait loop?** VMs boot nearly in parallel. If worker provisioning starts before cp1's `kubeadm init` has finished and the API server is listening, the join command fails immediately with a timeout. The `nc` poll tests TCP connectivity to port 6443 every 5 seconds until it succeeds, then proceeds with the join. `--v=5` enables verbose output to make join failures easier to diagnose.

---

### `scripts/update_name.sh`

Updates the name stored in the PostgreSQL database. Requires `kubectl` to be configured and the database credentials to be exported.

**Usage**:
```bash
export DB_USER=demo
export DB_NAME=demo
export DB_PASSWORD=demo
./vagrant/scripts/update_name.sh "Alice"
```

**What it does**:
1. Validates that `$1` (new name) is provided
2. Validates that `DB_USER`, `DB_NAME`, `DB_PASSWORD` are set
3. Finds the `db-postgres` pod in the `db-stack` namespace using the label `app=db-postgres`
4. Runs:
   ```bash
   kubectl exec -i -n db-stack <pod> -- env PGPASSWORD="$DB_PASSWORD" \
     psql -U "$DB_USER" -d "$DB_NAME" -v new_name="Alice" <<'SQL'
   UPDATE person SET name = :'new_name' WHERE id = 1;
   SQL
   ```
5. Prints confirmation

**After running**: refresh the browser — `GET /api/name` returns the updated value immediately.

**Namespace override**: set `NAMESPACE=<other>` to target a different namespace.

---

### `scripts/load_env_var.sh`

Interactive helper that prompts for `DB_USER` and `DB_PASSWORD` and exports them to the current shell session.

**Usage** (must be sourced, not executed):
```bash
source ./vagrant/scripts/load_env_var.sh
# or
. ./vagrant/scripts/load_env_var.sh
```

After running, `DB_USER` and `DB_PASSWORD` are available in the shell so `update_name.sh` can be run without manually exporting them.

---

## Vagrant commands reference

```bash
# Create all three VMs and run full provisioning
vagrant up

# Start only one VM (useful if a worker was not created)
vagrant up worker2

# SSH into a specific node
vagrant ssh cp1
vagrant ssh worker1
vagrant ssh worker2

# Run kubectl as the vagrant user on cp1
vagrant ssh cp1 -- kubectl get nodes
vagrant ssh cp1 -- kubectl get pods -A

# Re-run provisioning on a running VM without destroying it
vagrant provision cp1

# Add port-forwarding rules that were added after the VM was created
vagrant reload cp1 --no-provision

# Gracefully stop all VMs
vagrant halt

# Destroy all VMs and free disk space
vagrant destroy -f

# Check the state of all VMs
vagrant status
```

---

## Key design decisions

### Flannel interface binding

All Vagrant VMs created with VirtualBox have two NICs:
- `enp0s3`: VirtualBox NAT — all VMs share `10.0.2.x`; traffic exits the host and re-enters, VMs cannot reach each other
- `enp0s8`: Host-only — unique IPs in `192.168.56.0/24`; VMs on the same host can communicate directly

Flannel's NIC auto-detection always picks the first interface, which is `enp0s3`. The `--iface=enp0s8` patch is the standard fix for all kubeadm-on-Vagrant setups.

### No `--wait` on Helm installs

At the time cp1's provisioning runs, the workers have not joined. The control-plane taint (`node-role.kubernetes.io/control-plane:NoSchedule`) prevents regular pods from scheduling on cp1. Adding `--wait` to the Helm commands would cause them to time out waiting for pods that cannot start yet.

For ArgoCD, `global.tolerations` in `argocd-values.yaml` is the exception: it allows the CRD-management Job to tolerate the control-plane taint so the ArgoCD CRDs are registered before workers join.

### Worker join retry

The `nc` poll in `provision-worker.sh` prevents the race condition where a worker starts provisioning before cp1's API server is ready. Without it, the first `kubeadm join` attempt would fail and Vagrant would report the provisioner as failed, requiring manual intervention.

### bash instead of direct execution

The `/vagrant` synced folder is mounted by VirtualBox with the `noexec` option on Windows hosts. This prevents scripts from being executed directly even if they have the executable bit set. All scripts in `/vagrant` are run via `bash /vagrant/script.sh` rather than `/vagrant/script.sh` to work around this restriction.

---

## Regenerating the join token

The token written to `join.sh` expires after 24 hours. To create a new one after the cluster is running:

```bash
vagrant ssh cp1
sudo kubeadm token create --print-join-command | tee /vagrant/join.sh
chmod +x /vagrant/join.sh
```

Then re-provision any worker that needs to join:

```bash
vagrant provision worker1
```

---

## Requirements

| Requirement | Minimum version |
|-------------|----------------|
| [Vagrant](https://www.vagrantup.com/) | 2.3 |
| [VirtualBox](https://www.virtualbox.org/) | 7.0 |
| Host RAM | 14 GB free (3 × 4096 MB + host overhead) |
| Internet access | Required for package and image downloads during provisioning |
