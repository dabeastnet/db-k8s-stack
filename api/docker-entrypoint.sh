#!/bin/sh
# entrypoint for the FastAPI application
set -e

# Provide defaults for connection parameters if not set
: "${DB_HOST:=db-postgres}"
: "${DB_PORT:=5432}"
: "${DB_NAME:=postgres}"
: "${DB_USER:=postgres}"
: "${DB_PASSWORD:=postgres}"

echo "Waiting for PostgreSQL to become available at ${DB_HOST}:${DB_PORT}..."

# pg_isready will attempt to connect using the supplied user but will not
# prompt for a password.  When the PostgreSQL instance enforces password
# authentication (as our statefulset does), pg_isready will continually
# report "no response" unless a password is supplied via the environment.
# Export PGPASSWORD so pg_isready can authenticate with the credentials
# provided in the DB_* variables.  Without this, the readiness loop
# would never exit and the API container would fail its startup probe.
export PGPASSWORD="$DB_PASSWORD"

until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" > /dev/null 2>&1; do
    sleep 2
done

# Compose DATABASE_URL if not supplied
if [ -z "$DATABASE_URL" ]; then
    export DATABASE_URL="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
fi

echo "DATABASE_URL=$DATABASE_URL"

# Run database migrations
echo "Applying database migrations..."
alembic upgrade head

# Launch the application
exec "$@"