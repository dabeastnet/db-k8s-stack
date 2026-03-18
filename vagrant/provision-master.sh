#!/bin/bash
set -e

JOIN_SCRIPT=/vagrant/join.sh

# Initialize control plane if not already
if [ ! -f /etc/kubernetes/admin.conf ]; then
  # Detect the private IP on the host-only network. Relying on
  # `hostname -I | awk '{print $2}'` is brittle and may pick the NAT interface.
  APISERVER_IP=$(hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.56\.') || true
  if [ -z "$APISERVER_IP" ]; then
    APISERVER_IP=$(hostname -I | awk '{print $2}')
  fi
  kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$APISERVER_IP"
fi

# Setup kubeconfig for vagrant user
mkdir -p /home/vagrant/.kube
cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config

# Install Flannel CNI plugin.
# In Vagrant, flannel will otherwise pick the default NAT interface (10.0.2.15)
# on every node, which breaks cross-node pod traffic. Patch the manifest so
# flanneld binds to the host-only interface used between VMs.
FLANNEL_MANIFEST=/tmp/kube-flannel.yml
curl -fsSL -o "$FLANNEL_MANIFEST" https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sed -i '/- --kube-subnet-mgr/a\        - --iface=enp0s8' "$FLANNEL_MANIFEST"
su - vagrant -c "kubectl apply -f $FLANNEL_MANIFEST"

# Generate join script
kubeadm token create --print-join-command >"${JOIN_SCRIPT}"
chmod +x "${JOIN_SCRIPT}"

# Deploy application manifests (namespace, configmap, secret, postgres, api, frontend, ingress)
K8S_DIR=/vagrant/k8s
# Namespace and configmap
su - vagrant -c "kubectl apply -f ${K8S_DIR}/namespace.yaml || true"
su - vagrant -c "kubectl apply -f ${K8S_DIR}/configmap.yaml || true"
# Secret (generate default if not provided)
if ! su - vagrant -c "kubectl get secret db-app-secret -n db-stack >/dev/null 2>&1"; then
  su - vagrant -c "kubectl apply -f ${K8S_DIR}/secret.example.yaml"
fi
# PostgreSQL
su - vagrant -c "kubectl apply -f ${K8S_DIR}/postgres/postgres.yaml"
# API components
su - vagrant -c "kubectl apply -f ${K8S_DIR}/api/service.yaml"
su - vagrant -c "kubectl apply -f ${K8S_DIR}/api/deployment.yaml"
# Frontend
su - vagrant -c "kubectl apply -f ${K8S_DIR}/frontend/service.yaml"
su - vagrant -c "kubectl apply -f ${K8S_DIR}/frontend/deployment.yaml"
# Ingress
su - vagrant -c "kubectl apply -f ${K8S_DIR}/ingress/ingress.yaml"

# Deploy optional components from the repo root so relative paths resolve correctly
if [ -f /vagrant/deploy-k8s.sh ]; then
  echo "Running deploy-k8s.sh to install optional components..."
  su - vagrant -c "cd /vagrant && chmod +x ./deploy-k8s.sh && ./deploy-k8s.sh"
fi
