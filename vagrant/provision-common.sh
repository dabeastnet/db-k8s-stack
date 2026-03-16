#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Common setup tasks for all nodes
# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Install base packages
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# Load kernel modules required for Kubernetes
modprobe overlay
modprobe br_netfilter

# Ensure modules are loaded on boot
cat <<CONF_EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
CONF_EOF

# Set sysctl params required by Kubernetes networking
cat <<SYS_EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYS_EOF

sysctl --system

# Install containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# enable systemd cgroups for containerd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd



# Ensure a hostPath exists for the PostgreSQL PersistentVolume.  Without this
# directory the hostPath PV defined in the manifests cannot be created.  The
# directory is owned by root; the postgres container runs with fsGroup 999 so
# POSIX permissions are still respected via the group permission bits on the
# volume.
mkdir -p /mnt/postgres-data

# Add Kubernetes apt repository (new pkgs.k8s.io repo for v1.29)
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

# apt-get update -y
# apt-get install -y kubelet kubeadm kubectl
# apt-mark hold kubelet kubeadm kubectl
# systemctl enable kubelet


apt-get update
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  kubelet kubeadm kubectl cri-tools conntrack kubernetes-cni



# -----------------------------------------------------------------------------
# Configure kubelet to advertise the correct node IP
#
# In a Vagrant environment each VM has multiple network interfaces.  By default
# kubelet will pick the first internal address (often the NAT IP 10.0.2.x) when
# registering the node.  This leads to all nodes reporting the same IP and
# causes networking issues and API server timeouts.  To fix this, detect the
# address on the host‐only network (192.168.56.x) and set it via
# KUBELET_EXTRA_ARGS.  Writing to /etc/default/kubelet ensures kubelet picks up
# the flag on startup.  After writing the config we reload and restart
# kubelet so the change takes effect immediately.
PRIVATE_IP=$(hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.56\.') || true
if [ -n "$PRIVATE_IP" ]; then
  cat <<EOF >/etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$PRIVATE_IP
EOF
  # systemctl daemon-reload
  # # kubelet may not be running yet, but restart to pick up new args if it is
  # systemctl restart kubelet || true
  if systemctl list-unit-files | grep -q '^kubelet.service'; then
    systemctl daemon-reload
    systemctl enable kubelet
    systemctl restart kubelet
  fi
fi