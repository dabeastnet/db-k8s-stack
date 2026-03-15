#!/bin/bash
# Build the frontend and API images.

set -e

echo "Building frontend image..."
docker build -t db-frontend:latest ./frontend

echo "Building API image..."
docker build -t db-api:latest ./api

echo "Build complete. Images tagged as db-frontend:latest and db-api:latest."