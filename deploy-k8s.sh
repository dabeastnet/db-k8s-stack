#!/bin/bash
# Deploy the application stack to a Kubernetes cluster.
# This script assumes that kubectl is configured to talk to your cluster
# and that ingress-nginx, cert-manager and the Prometheus operator are installed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE=db-stack

echo "Creating namespace $NAMESPACE..."
kubectl apply -f k8s/namespace.yaml

echo "Applying secrets and configmaps..."
kubectl apply -f k8s/secret.example.yaml
kubectl apply -f k8s/configmap.yaml

echo "Deploying PostgreSQL..."
kubectl apply -f k8s/postgres/postgres.yaml

echo "Deploying API..."
kubectl apply -f k8s/api/deployment.yaml
kubectl apply -f k8s/api/service.yaml

echo "Deploying frontend..."
kubectl apply -f k8s/frontend/deployment.yaml
kubectl apply -f k8s/frontend/service.yaml

echo "Configuring TLS ClusterIssuers..."
#
# The TLS ClusterIssuer manifests depend on cert‑manager CRDs.  When
# cert‑manager has not yet been installed into the cluster, applying
# these manifests causes kubectl to return a non‑zero exit code which
# would normally abort this script because of `set -e` at the top of
# the file.  To allow the remainder of the deployment to proceed, we
# temporarily disable the "exit on error" behaviour while attempting
# to apply the ClusterIssuer.  If the CRDs are missing the apply will
# simply fail and we log a message.  If cert‑manager is installed the
# ClusterIssuers will be created successfully.
set +e
kubectl apply -f k8s/cert-manager/clusterissuer.yaml || echo "Skipping ClusterIssuer creation; cert-manager CRDs not found."
set -e

echo "Creating Ingress..."
kubectl apply -f k8s/ingress/ingress.yaml

echo "Configuring Prometheus monitoring..."

# Create the monitoring namespace and deploy Prometheus along with exporters.
kubectl apply -f k8s/monitoring/namespace.yaml

# Deploy core monitoring components.  These manifests install Prometheus,
# kube‑state‑metrics for Kubernetes object state and the node exporter for
# node‑level metrics.  The service monitor is retained for compatibility with
# the Prometheus Operator but will be ignored by the standalone Prometheus
# deployed here.
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/kube-state-metrics.yaml
kubectl apply -f k8s/monitoring/node-exporter.yaml

if kubectl api-resources | grep -q '^servicemonitors[[:space:]]'; then
  kubectl apply -f k8s/monitoring/service-monitor.yaml
else
  echo "Skipping ServiceMonitor creation; Prometheus Operator CRDs not found."
fi

echo "Creating ArgoCD application..."
if kubectl api-resources | grep -q '^applications[[:space:]]'; then
  kubectl apply -f k8s/argocd/application.yaml
else
  echo "Skipping ArgoCD application creation; Argo CD CRDs not found."
fi

echo "Deployment complete.  Use kubectl get all -n $NAMESPACE to monitor resources."