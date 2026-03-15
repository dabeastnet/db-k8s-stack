#!/bin/bash
# Launch the application stack locally using Docker Compose.

set -e

echo "Starting local stack with Docker Compose..."
docker compose up --build