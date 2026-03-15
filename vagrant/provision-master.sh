#!/bin/bash
set -e

JOIN_SCRIPT=/vagrant/join.sh

# Initialize control plane if not already
if [ ! -f /etc/kubernetes/admin.conf ]; then
  kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$(hostname -I | awk '{print $2}')"
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
