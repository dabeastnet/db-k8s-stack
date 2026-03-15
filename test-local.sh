#!/bin/bash
# Simple smoke test for the local Docker Compose deployment.

set -e

API_URL=${API_URL:-http://localhost:8000}
FRONTEND_URL=${FRONTEND_URL:-http://localhost:8080}

echo "Testing API /api/name endpoint..."
resp_name=$(curl -s "$API_URL/api/name")
echo "Response: $resp_name"

echo "Testing API /api/container-id endpoint..."
resp_id=$(curl -s "$API_URL/api/container-id")
echo "Response: $resp_id"

echo "Testing health and readiness endpoints..."
curl -s "$API_URL/healthz"
curl -s "$API_URL/readyz"

echo "Testing metrics endpoint (show first few lines)..."
curl -s "$API_URL/metrics" | head -n 5

echo "Testing frontend page..."
curl -s "$FRONTEND_URL" | head -n 10

echo "Smoke tests completed.  Review the output above to verify correctness."