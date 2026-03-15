#!/bin/bash
# Deploy the application stack to a Kubernetes cluster.
# This script assumes that kubectl is configured to talk to your cluster
# and that ingress-nginx, cert-manager and the Prometheus operator are installed.

set -e

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
kubectl apply -f k8s/cert-manager/clusterissuer.yaml

echo "Creating Ingress..."
kubectl apply -f k8s/ingress/ingress.yaml

echo "Configuring Prometheus monitoring..."
kubectl apply -f k8s/monitoring/service-monitor.yaml

echo "Creating ArgoCD application..."
kubectl apply -f k8s/argocd/application.yaml

echo "Deployment complete.  Use kubectl get all -n $NAMESPACE to monitor resources."