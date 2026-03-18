# api — FastAPI Backend Service

## Purpose

The `api` component is the backend service for the db-k8s-stack. It exposes a REST API that reads data from PostgreSQL, reports its container identity, and publishes Prometheus metrics. It is consumed by the Apache frontend via the nginx ingress controller.

## What this component does

- Returns the name stored in the PostgreSQL `person` table via `GET /api/name`
- Reports the running container ID and pod metadata via `GET /api/container-id`
- Provides liveness and readiness probe endpoints used by Kubernetes health checks
- Exposes a Prometheus metrics endpoint at `/metrics` counting requests per endpoint and method
- Runs Alembic migrations on startup to ensure the `person` table exists and is seeded

## Key files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build based on `python:3.11-slim`; creates non-root user `appuser` (UID 1001) |
| `docker-entrypoint.sh` | Waits for PostgreSQL via `pg_isready`, runs `alembic upgrade head`, then launches Uvicorn |
| `requirements.txt` | Python dependencies: FastAPI, Uvicorn, SQLAlchemy, Alembic, psycopg2-binary, prometheus-client |
| `app/main.py` | FastAPI application with all route handlers |
| `app/db.py` | SQLAlchemy engine and session factory; reads connection settings from environment variables |
| `app/models.py` | SQLAlchemy `Person` model (`id`, `name`) mapped to the `person` table |
| `app/migrations/versions/001_create_person_table.py` | Alembic migration that creates `person` and seeds `Dieter Beckers` |
| `alembic.ini` | Alembic configuration; `sqlalchemy.url` is overridden at runtime from the environment |

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/name` | Returns `{"name": "..."}` from the first row of the `person` table |
| `GET` | `/api/container-id` | Returns `{"container_id": "...", "pod_name": "...", "hostname": "..."}` |
| `GET` | `/healthz` | Liveness probe — always returns `{"status": "ok"}` |
| `GET` | `/readyz` | Readiness probe — executes `SELECT 1` and returns 200 or 503 |
| `GET` | `/metrics` | Prometheus exposition format; exposes `db_api_requests_total` counter |

## Configuration (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `db-postgres` | PostgreSQL hostname |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `postgres` | Database name |
| `DB_USER` | `postgres` | Database user |
| `DB_PASSWORD` | `postgres` | Database password |
| `DATABASE_URL` | constructed | Full SQLAlchemy URL; built automatically if not set |
| `POD_NAME` | `""` | Injected by Kubernetes downward API; surfaced in `/api/container-id` |
| `HOSTNAME` | `""` | Node hostname; injected from `spec.nodeName` in the Deployment |

In Kubernetes these variables are populated from the `db-app-config` ConfigMap and `db-app-secret` Secret (see `k8s/configmap.yaml` and `k8s/secret.example.yaml`).

## Container details

- **Base image**: `python:3.11-slim`
- **Published image**: `ghcr.io/dabeastnet/db-api:v6`
- **Listening port**: `8000`
- **Run as**: `appuser` UID/GID 1001
- **Build tools**: `build-essential`, `libpq-dev`, `postgresql-client` (installed for `pg_isready` in entrypoint)

## Dependencies

- PostgreSQL must be reachable at `DB_HOST:DB_PORT` before the API starts. The entrypoint polls `pg_isready` until the database is available.
- Alembic migrations run once on startup; subsequent starts are idempotent.

## Building locally

```bash
docker build -t db-api:latest ./api
```

Or use the repository helper script from the repo root:

```bash
./build.sh
```

## Running locally

See `docker-compose.yml` in the repo root and `LOCAL_TESTING.md` for full local testing instructions.

```bash
docker compose up --build
curl http://localhost:8000/api/name
```

## Relationship to other components

- **`frontend`** — The frontend JavaScript fetches `/api/name` and `/api/container-id` via the nginx ingress proxy. In Docker Compose the Apache httpd proxy (`ProxyPass /api`) is also used.
- **`k8s/api/`** — Kubernetes Deployment and Service manifests that run this image in the cluster.
- **`k8s/monitoring/`** — Prometheus scrapes `/metrics`. The `service-monitor.yaml` defines the scrape target.
- **PostgreSQL** — The API's only external dependency; connection managed by SQLAlchemy with connection pooling.

## Notes

- Container ID detection works by parsing `/proc/self/cgroup` with three regex patterns covering `cri-containerd`, generic `containerd`, and bare 64-character hex IDs. Only the first 12 characters are returned.
- Resource limits in the Kubernetes Deployment: requests `100m` CPU / `128Mi` memory; limits `500m` CPU / `512Mi` memory.
- Two replicas are deployed with `topologySpreadConstraints` to distribute them across worker nodes.
