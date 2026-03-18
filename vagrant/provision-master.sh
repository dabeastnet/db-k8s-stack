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

# Vagrant VMs have two NICs: enp0s3 (NAT, 10.0.2.x) and enp0s8 (private, 192.168.56.x).
# Flannel picks enp0s3 by default, which means VXLAN tunnels are built over the NAT
# interface -- cross-node pod traffic never reaches the other VM, breaking DNS and
# all cross-node communication.  Patch the DaemonSet to bind to enp0s8 instead.
su - vagrant -c "kubectl patch daemonset kube-flannel-ds -n kube-flannel --type=json \
  -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--iface=enp0s8\"}]'"
su - vagrant -c "kubectl rollout status daemonset kube-flannel-ds -n kube-flannel --timeout=120s"

# Install Helm (only on the control plane — workers do not need it)
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Install nginx ingress controller via Helm.
# The service type is NodePort because Vagrant/bare-metal clusters have no
# cloud load-balancer.  HTTP lands on 30080 and HTTPS on 30443; both are
# forwarded from the host in the Vagrantfile.
su - vagrant -c "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true"
su - vagrant -c "helm repo update"
su - vagrant -c "helm upgrade --install db-ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.admissionWebhooks.enabled=false"
# No --wait: at this point only cp1 exists and its control-plane taint prevents
# the ingress pod from scheduling.  It will start once a worker joins.

# Install ArgoCD via Helm using the project values file.
# The server runs with --insecure so nginx can proxy it over plain HTTP;
# outer TLS is handled by Cloudflare Tunnel (or cert-manager later).
su - vagrant -c "helm repo add argo https://argoproj.github.io/argo-helm || true"
su - vagrant -c "helm repo update"
su - vagrant -c "helm upgrade --install db-argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f /vagrant/helm/argocd-values.yaml"
# No --wait: same reason as ingress-nginx above.
# The Application CRD is registered by Helm synchronously before any pods
# start, so we just wait for that rather than for all pods to be ready.
echo "Waiting for ArgoCD Application CRD to be registered..."
until su - vagrant -c "kubectl get crd applications.argoproj.io >/dev/null 2>&1"; do
  sleep 3
done

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

# Run the deploy-k8s.sh script to provision optional components such as
# cert-manager ClusterIssuers, monitoring (Prometheus/kube-state-metrics/node-exporter),
# and other add-ons.  This script is idempotent and will skip steps
# if prerequisites like CRDs are not installed, so it is safe to run
# during provisioning.  Running it here ensures that monitoring is
# available without manual intervention.
if [ -f /vagrant/deploy-k8s.sh ]; then
  echo "Running deploy-k8s.sh to install optional components..."
  # Call the script explicitly via bash.  The /vagrant synced folder on
  # Windows hosts is typically mounted with the `noexec` flag inside the VM,
  # which prevents executing a script file directly even if it has the
  # executable bit set.  By invoking bash and passing the script as an
  # argument we avoid the noexec restriction and ensure the script runs
  # during provisioning.  Don't rely on chmod +x here.
  su - vagrant -c "bash /vagrant/deploy-k8s.sh"
fi
