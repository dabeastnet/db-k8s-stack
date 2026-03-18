#!/usr/bin/env bash

# Deploy the database stack into a Kubernetes cluster.  This script wraps the
# various kubectl apply commands needed to create secrets, configmaps,
# deployments, services, ingress, monitoring components and optional
# GitOps resources.  It assumes that `kubectl` is already configured to
# connect to your cluster (e.g. via kubeconfig) and that optional
# dependencies such as cert‑manager or the Prometheus operator may or may
# not be present.  When optional CRDs are missing the relevant
# manifests are skipped gracefully.

set -e

# Namespace that all core application resources live in.  Update this
# variable to change the target namespace.
NAMESPACE=db-stack

# Compute the absolute path to the directory containing this script.  This
# allows us to reference the manifests in the k8s/ folder regardless of
# the working directory from which the script is executed.  Without this
# the script would attempt to apply relative paths from the current
# directory which fails when run by Vagrant provisioners or other tools.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_DIR="$SCRIPT_DIR/k8s"

echo "Creating namespace $NAMESPACE..."
kubectl apply -f "$K8S_DIR/namespace.yaml"

echo "Applying secrets and configmaps..."
kubectl apply -f "$K8S_DIR/secret.example.yaml"
kubectl apply -f "$K8S_DIR/configmap.yaml"

echo "Deploying PostgreSQL..."
kubectl apply -f "$K8S_DIR/postgres/postgres.yaml"

echo "Deploying API..."
kubectl apply -f "$K8S_DIR/api/deployment.yaml"
kubectl apply -f "$K8S_DIR/api/service.yaml"

echo "Deploying frontend..."
kubectl apply -f "$K8S_DIR/frontend/deployment.yaml"
kubectl apply -f "$K8S_DIR/frontend/service.yaml"

echo "Configuring TLS ClusterIssuers..."
# Create ClusterIssuers if cert‑manager is installed.  Skip silently
# otherwise to avoid failing the script when CRDs are absent.  cert‑manager
# CRDs define the ClusterIssuer kind.
set +e
kubectl apply -f "$K8S_DIR/cert-manager/clusterissuer.yaml" || echo "Skipping ClusterIssuer creation; cert-manager CRDs not found."
set -e

echo "Creating Ingress..."
kubectl apply -f "$K8S_DIR/ingress/ingress.yaml"

echo "Configuring Prometheus monitoring..."
# Create the monitoring namespace and deploy Prometheus along with
# exporters.  These resources use a NodePort service for Prometheus so
# that the service is reachable outside of the cluster when combined
# with port‑forwarding in the Vagrantfile.
kubectl apply -f "$K8S_DIR/monitoring/namespace.yaml"
kubectl apply -f "$K8S_DIR/monitoring/prometheus.yaml"
kubectl apply -f "$K8S_DIR/monitoring/kube-state-metrics.yaml"
kubectl apply -f "$K8S_DIR/monitoring/node-exporter.yaml"

# Attempt to create a ServiceMonitor only when the CRD exists.  The
# Prometheus operator defines the ServiceMonitor kind.  When the operator
# is not installed this manifest will fail to apply; in that case we
# simply log a message and continue.
set +e
kubectl apply -f "$K8S_DIR/monitoring/service-monitor.yaml" || echo "Skipping ServiceMonitor creation; monitoring CRDs not found."
set -e

echo "Creating ArgoCD application..."
# The ArgoCD Application CRD may not be installed in all clusters.  If the
# CRDs are missing (e.g. when ArgoCD is not deployed), attempting to
# apply this manifest will result in an error such as "no matches for kind
# \"Application\"".  Wrap this operation in a non‑fatal block so that
# absence of ArgoCD does not cause the entire deployment script to fail.
set +e
kubectl apply -f "$K8S_DIR/argocd/application.yaml" || echo "Skipping ArgoCD application creation; ArgoCD CRDs not found."
set -e

echo "Deployment complete.  Use 'kubectl get all -n $NAMESPACE' to inspect the deployed resources."