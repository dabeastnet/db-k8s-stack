# vagrant — Cluster Provisioning

## Purpose

This directory contains the shell scripts that provision a three-node kubeadm Kubernetes cluster on VirtualBox. The `Vagrantfile` in the repository root drives the process. Running `vagrant up` from the repo root creates a fully functional cluster with the entire application stack deployed automatically — no manual steps required.

## Cluster topology

| VM | Role | Private IP | Memory | CPUs |
|----|------|-----------|--------|------|
| `cp1` | Control plane | `192.168.56.10` | 4096 MB | 2 |
| `worker1` | Worker | `192.168.56.20` | 4096 MB | 2 |
| `worker2` | Worker | `192.168.56.21` | 4096 MB | 2 |

All VMs run **Ubuntu 20.04 LTS** (`ubuntu/focal64`) and have the repository mounted at `/vagrant`.

## Host port forwarding (cp1 only)

| Host port | Guest NodePort | Service |
|-----------|---------------|---------|
| `18080` | `30080` | nginx ingress HTTP |
| `18443` | `30443` | nginx ingress HTTPS |
| `19090` | `30090` | Prometheus web UI |
| `13000` | `30030` | Grafana web UI |

## Scripts

### `provision-common.sh` — runs on all nodes

1. Disables swap (required by kubeadm)
2. Installs: `curl`, `gnupg`, `ca-certificates`, `apt-transport-https`, `software-properties-common`
3. Loads kernel modules: `overlay`, `br_netfilter`
4. Sets sysctl for Kubernetes networking (`bridge-nf-call-iptables`, `ip_forward`)
5. Installs **containerd** and enables systemd cgroup driver
6. Creates `/mnt/postgres-data` for the PostgreSQL PersistentVolume hostPath
7. Adds the Kubernetes v1.29 APT repository
8. Installs: `kubelet`, `kubeadm`, `kubectl`, `cri-tools`, `conntrack`, `kubernetes-cni`
9. Configures kubelet to advertise the `192.168.56.x` IP

### `provision-master.sh` — runs on cp1 only

1. Detects the `192.168.56.x` IP and runs `kubeadm init --pod-network-cidr=10.244.0.0/16`
2. Sets up kubeconfig for the `vagrant` user
3. Installs **Flannel** CNI and patches the DaemonSet to bind to `enp0s8`:
   ```bash
   kubectl patch daemonset kube-flannel-ds -n kube-flannel --type=json \
     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--iface=enp0s8"}]'
   ```
   Without this patch, Flannel uses the NAT interface and cross-node pod traffic fails entirely.
4. Installs **Helm**
5. Installs **db-ingress-nginx** (NodePort 30080/30443, webhooks disabled)
6. Installs **db-argocd** from `helm/argocd-values.yaml`; waits for the ArgoCD Application CRD
7. Generates `/vagrant/join.sh` with the kubeadm join command (token valid 24 h)
8. Applies core manifests: namespace, configmap, secret, postgres, api, frontend, ingress
9. Calls `deploy-k8s.sh` to install monitoring, cloudflared, and the ArgoCD Application

### `provision-worker.sh` — runs on worker1 and worker2

1. Polls `192.168.56.10:6443` with `nc` every 5 s until the API server responds
2. Executes `/vagrant/join.sh` to join the cluster

The poll loop prevents failures caused by workers starting before cp1's API server is ready.

### `scripts/update_name.sh`

Updates the name stored in PostgreSQL without direct database access.

**Prerequisites**: `kubectl` configured, `DB_USER`, `DB_NAME`, and `DB_PASSWORD` set.

```bash
export DB_USER=demo DB_NAME=demo DB_PASSWORD=demo
./vagrant/scripts/update_name.sh "Alice"
```

Finds the `db-postgres` pod and executes `UPDATE person SET name = 'Alice' WHERE id = 1`.

### `scripts/load_env_var.sh`

Prompts for `DB_USER` and `DB_PASSWORD` interactively and exports them. Use with `source`:

```bash
source ./vagrant/scripts/load_env_var.sh
```

## Key design decisions

### Flannel interface fix

VirtualBox VMs have two NICs: `enp0s3` (NAT, `10.0.2.x`) and `enp0s8` (host-only, `192.168.56.x`). Flannel auto-detection picks `enp0s3` by default. VirtualBox NAT does not route traffic between VMs, so VXLAN tunnels built on `enp0s3` never deliver packets to other nodes. Forcing `--iface=enp0s8` makes Flannel use the shared private network.

### No `--wait` on Helm installs

At provisioning time only cp1 exists. The control-plane taint prevents ingress-nginx and ArgoCD pods from scheduling until workers join. `--wait` would time out. The `global.tolerations` in `argocd-values.yaml` allows the ArgoCD CRD-management pre-install Job to run on cp1 specifically.

### Worker join retry loop

Workers begin provisioning nearly simultaneously with cp1. The API server may not be listening yet. The `nc` poll in `provision-worker.sh` waits until `192.168.56.10:6443` accepts connections before running the join command.

## Usage

```bash
# Create and provision all three VMs
vagrant up

# SSH into the control plane
vagrant ssh cp1

# Check cluster status
vagrant ssh cp1 -- kubectl get nodes
vagrant ssh cp1 -- kubectl get pods -A

# Re-apply manifests without destroying
vagrant provision cp1

# Destroy everything
vagrant destroy -f
```

## Regenerating the join token

The join token in `join.sh` expires after 24 hours. To generate a new one:

```bash
vagrant ssh cp1
kubeadm token create --print-join-command | tee /vagrant/join.sh
chmod +x /vagrant/join.sh
```

## Requirements

- [Vagrant](https://www.vagrantup.com/) ≥ 2.3
- [VirtualBox](https://www.virtualbox.org/) ≥ 7.0
- ≥ 14 GB available RAM (3 × 4096 MB + host overhead)
- Internet access for package and image downloads
