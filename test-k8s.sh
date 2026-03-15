#!/bin/bash
# Smoke test for the Kubernetes deployment.
# Port-forwards the API and frontend services to localhost and exercises the endpoints.

set -e

NAMESPACE=${NAMESPACE:-db-stack}
API_PORT_LOCAL=18000
FRONTEND_PORT_LOCAL=18080

echo "Port-forwarding API and frontend services..."

# Start port-forwarding in the background
kubectl port-forward svc/db-api -n "$NAMESPACE" "$API_PORT_LOCAL":80 > /dev/null 2>&1 &
PF_API_PID=$!
kubectl port-forward svc/db-frontend -n "$NAMESPACE" "$FRONTEND_PORT_LOCAL":80 > /dev/null 2>&1 &
PF_FE_PID=$!

# Give port-forwarding a moment to establish
sleep 5

API_URL="http://localhost:$API_PORT_LOCAL"
FRONTEND_URL="http://localhost:$FRONTEND_PORT_LOCAL"

echo "Testing API /api/name endpoint..."
curl -s "$API_URL/api/name"

echo "Testing API /api/container-id endpoint..."
curl -s "$API_URL/api/container-id"

echo "Testing API health endpoints..."
curl -s "$API_URL/healthz"
curl -s "$API_URL/readyz"

echo "Testing metrics endpoint (first few lines)..."
curl -s "$API_URL/metrics" | head -n 5

echo "Fetching frontend page..."
curl -s "$FRONTEND_URL" | head -n 10

echo "Stopping port-forwards..."
kill $PF_API_PID $PF_FE_PID

echo "Kubernetes smoke tests completed."