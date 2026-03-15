#!/bin/bash
# Usage: ./update_name.sh <new-name>
#
# This script updates the 'name' field in the 'person' table of the database.
# It requires that the following environment variables are set:
#   DB_HOST     - database host
#   DB_PORT     - database port
#   DB_NAME     - database name
#   DB_USER     - database user
#   DB_PASSWORD - database password

set -e

NEW_NAME=$1
if [ -z "$NEW_NAME" ]; then
  echo "Usage: $0 <new-name>"
  exit 1
fi

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_NAME" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Environment variables DB_HOST, DB_USER, DB_NAME and DB_PASSWORD must be set"
  exit 1
fi

export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -c "UPDATE person SET name = '$NEW_NAME' WHERE id = 1;"
echo "Name updated to $NEW_NAME"