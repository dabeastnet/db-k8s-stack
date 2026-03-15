#!/bin/bash
set -e

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

# Add Kubernetes apt repository (new pkgs.k8s.io repo for v1.29)
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
