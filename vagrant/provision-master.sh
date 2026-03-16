#!/bin/bash
set -e

JOIN_SCRIPT=/vagrant/join.sh

# Initialize control plane if not already
if [ ! -f /etc/kubernetes/admin.conf ]; then
  # Detect the private IP on the host‐only network.  Relying on `hostname -I | awk '{print $2}'`
  # often returns the wrong interface (e.g. the NAT 10.0.2.x address), which
  # prevents the control plane from being reachable by worker nodes.  We pick
  # the first 192.168.56.x address instead.
  APISERVER_IP=$(hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.56\.') || true
  if [ -z "$APISERVER_IP" ]; then
    # Fallback to the second address if no 192.168.56.x was found
    APISERVER_IP=$(hostname -I | awk '{print $2}')
  fi
  kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$APISERVER_IP"
fi

# Setup kubeconfig for vagrant user
mkdir -p /home/vagrant/.kube
cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config

# Install Flannel CNI plugin
su - vagrant -c "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

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
