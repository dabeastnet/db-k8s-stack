#!/bin/bash
# Tag and push images to a container registry.

set -e

if [ -z "$REGISTRY" ]; then
  echo "Please set the REGISTRY environment variable (e.g. export REGISTRY=registry.example.com)"
  exit 1
fi

echo "Pushing images to $REGISTRY..."

docker tag db-frontend:latest "$REGISTRY/db-frontend:latest"
docker tag db-api:latest "$REGISTRY/db-api:latest"

docker push "$REGISTRY/db-frontend:latest"
docker push "$REGISTRY/db-api:latest"

echo "Push complete."