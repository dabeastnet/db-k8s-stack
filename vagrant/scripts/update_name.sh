#!/bin/bash
# Usage: ./update_name.sh <new-name>

# set -euo pipefail

NEW_NAME="${1:-}"
NAMESPACE="${NAMESPACE:-db-stack}"
DB_LABEL="app=db-postgres"

if [ -z "$NEW_NAME" ]; then
  echo "Usage: $0 <new-name>"
  exit 1
fi

if [ -z "${DB_USER:-}" ] || [ -z "${DB_NAME:-}" ] || [ -z "${DB_PASSWORD:-}" ]; then
  echo "Environment variables DB_USER, DB_NAME and DB_PASSWORD must be set"
  exit 1
fi

DB_POD=$(kubectl get pod -n "$NAMESPACE" -l "$DB_LABEL" -o jsonpath='{.items[0].metadata.name}')

if [ -z "$DB_POD" ]; then
  echo "Could not find a Postgres pod in namespace '$NAMESPACE' with label '$DB_LABEL'"
  exit 1
fi

kubectl exec -i -n "$NAMESPACE" "$DB_POD" -- env PGPASSWORD="$DB_PASSWORD" \
  psql -U "$DB_USER" -d "$DB_NAME" -v new_name="$NEW_NAME" <<'SQL'
UPDATE person
SET name = :'new_name'
WHERE id = 1;
SQL

echo "Name updated to $NEW_NAME"