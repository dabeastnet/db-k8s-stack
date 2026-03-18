# api — FastAPI Backend Service

## Purpose

The `api` component is the backend for db-k8s-stack. It exposes a REST API over HTTP that reads data from a PostgreSQL database, reports its own container identity, and publishes Prometheus metrics. It is the only component with direct database access.

## Directory structure

```
api/
├── Dockerfile                          Container image definition
├── docker-entrypoint.sh                Startup script: waits for DB, runs migrations, starts server
├── requirements.txt                    Python package dependencies
├── alembic.ini                         Alembic migration tool configuration
├── app/
│   ├── __init__.py
│   ├── main.py                         FastAPI application and route handlers
│   ├── db.py                           SQLAlchemy engine, session factory, declarative base
│   └── models.py                       ORM model: Person(id, name)
└── migrations/
    ├── env.py                          Alembic runtime environment
    └── versions/
        └── 001_create_person_table.py  Initial migration: creates person table and seeds data
```

## API endpoints

| Method | Path | Description | Prometheus counter |
|--------|------|-------------|-------------------|
| `GET` | `/api/name` | Returns `{"name": "<value>"}` from the first row of `person` | `db_api_requests_total{endpoint="/api/name"}` |
| `GET` | `/api/container-id` | Returns container ID + pod metadata | `db_api_requests_total{endpoint="/api/container-id"}` |
| `GET` | `/healthz` | Liveness probe — always `{"status": "ok"}` | — |
| `GET` | `/readyz` | Readiness probe — runs `SELECT 1`, returns 503 on DB failure | — |
| `GET` | `/metrics` | Prometheus text exposition format | — |

### `/api/name` detail

Queries `SELECT * FROM person LIMIT 1`. If no row exists, returns `{"name": "Unknown"}`. The default row (`id=1`, `name="Dieter Beckers"`) is inserted by the Alembic migration.

### `/api/container-id` detail

Reads `/proc/self/cgroup` and matches three regex patterns in order:

1. `cri-containerd-([a-f0-9]{64})\.scope` — containerd in systemd cgroup v2
2. `containerd[-:/]([a-f0-9]{64})` — generic containerd
3. `\b([a-f0-9]{64})\b` — any 64-character hex string (Docker fallback)

Returns the first 12 characters of the matched ID. Also returns:
- `pod_name` — from the `POD_NAME` environment variable (set via downward API in K8s)
- `hostname` — from the `HOSTNAME` environment variable (set to `spec.nodeName` in K8s)

## Startup flow (`docker-entrypoint.sh`)

1. Apply defaults for `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` if not set
2. Export `PGPASSWORD=$DB_PASSWORD` so `pg_isready` can authenticate against password-protected PostgreSQL
3. Poll `pg_isready -h $DB_HOST -p $DB_PORT -U $DB_USER` every 2 seconds until it returns success
4. Build `DATABASE_URL` from individual `DB_*` variables if `DATABASE_URL` is not already set
5. Run `alembic upgrade head` — applies all pending migrations (idempotent on subsequent runs)
6. `exec "$@"` — launches Uvicorn: `uvicorn app.main:app --host 0.0.0.0 --port 8000`

## Database layer (`app/db.py`)

SQLAlchemy engine is created once at module import time:

```python
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,          # Test connections before using them from the pool
    pool_size=5,                 # Configurable via DB_POOL_SIZE env var
    max_overflow=10,             # Configurable via DB_MAX_OVERFLOW env var
)
```

`pool_pre_ping=True` means SQLAlchemy checks that a connection is still alive before handing it to a request, preventing stale connection errors after PostgreSQL restarts.

Routes use dependency injection to get a session:

```python
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

## Database model (`app/models.py`)

```python
class Person(Base):
    __tablename__ = "person"
    id   = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
```

One row is the expected steady state. `update_name.sh` updates `id=1` directly via `psql`.

## Migrations (`migrations/versions/001_create_person_table.py`)

The single migration (revision `001_create_person_table`) runs on every container start via `alembic upgrade head`:

- **upgrade**: Creates the `person` table with `id` (PK, autoincrement) and `name` (VARCHAR 255, NOT NULL), then inserts `('Dieter Beckers')`
- **downgrade**: Drops the `person` table

Because Alembic tracks applied revisions in the `alembic_version` table, re-running `upgrade head` on an already-migrated database is safe and does nothing.

## Configuration (environment variables)

| Variable | Default in entrypoint | Source in K8s | Description |
|----------|-----------------------|---------------|-------------|
| `DB_HOST` | `db-postgres` | `db-app-config` ConfigMap | PostgreSQL hostname |
| `DB_PORT` | `5432` | `db-app-config` ConfigMap | PostgreSQL port |
| `DB_NAME` | `postgres` | `db-app-config` ConfigMap | Database name |
| `DB_USER` | `postgres` | `db-app-secret` Secret | Database username |
| `DB_PASSWORD` | `postgres` | `db-app-secret` Secret | Database password |
| `PGPASSWORD` | (same as `DB_PASSWORD`) | `db-app-secret` Secret | Used by `pg_isready` in entrypoint |
| `DATABASE_URL` | constructed | — | Full SQLAlchemy URL; auto-built if absent |
| `DB_POOL_SIZE` | `5` | — | SQLAlchemy connection pool size |
| `DB_MAX_OVERFLOW` | `10` | — | SQLAlchemy max extra connections |
| `POD_NAME` | `""` | Downward API (`metadata.name`) | Kubernetes pod name; returned in `/api/container-id` |
| `HOSTNAME` | `""` | Downward API (`spec.nodeName`) | Node hostname; returned in `/api/container-id` |

## Dockerfile walkthrough

```dockerfile
FROM python:3.11-slim
WORKDIR /app

# Build tools needed for psycopg2 compilation and pg_isready
RUN apt-get update && apt-get install -y build-essential libpq-dev postgresql-client

COPY requirements.txt /app/
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY app/ /app/app/
COPY alembic.ini /app/
COPY migrations/ /app/migrations/
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create a non-root user and transfer ownership
RUN groupadd -r appgroup --gid 1001 && \
    useradd -r -g appgroup --uid 1001 appuser && \
    chown -R appuser:appgroup /app

USER appuser
EXPOSE 8000
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Key points:
- `postgresql-client` is installed so `pg_isready` is available in the entrypoint
- `build-essential` + `libpq-dev` are needed to compile `psycopg2` (C extension)
- The non-root user (`appuser`, UID 1001) matches the `securityContext` in `k8s/api/deployment.yaml`

## Python dependencies (`requirements.txt`)

| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | 0.111.0 | Web framework |
| `uvicorn[standard]` | 0.23.2 | ASGI server |
| `SQLAlchemy` | 2.0.29 | ORM and connection pooling |
| `alembic` | 1.13.1 | Database migration tool |
| `psycopg2-binary` | 2.9.9 | PostgreSQL adapter (binary distribution) |
| `python-dotenv` | 1.0.1 | `.env` file loading for local development |
| `prometheus-client` | 0.20.0 | Prometheus metrics exposition |

## Kubernetes resources (`k8s/api/`)

### Deployment (`k8s/api/deployment.yaml`)

- **Replicas**: 2 — capped at 2 because `topologySpreadConstraints` with `DoNotSchedule` prevents more replicas than schedulable nodes (worker1 + worker2)
- **Topology spread**: `maxSkew: 1` over `kubernetes.io/hostname` — guarantees one replica on each worker node
- **Security context**: `runAsUser: 1001`, `runAsGroup: 1001`, `fsGroup: 1001`
- **Image pull policy**: `IfNotPresent` — avoids re-pulling if the image is already cached on the node

**Probe configuration**:

| Probe | Path | Initial delay | Period | Failure threshold | Purpose |
|-------|------|--------------|--------|------------------|---------|
| Startup | `/healthz` | — | 10 s | 30 (= 300 s grace) | Allows slow migration/DB wait on first start |
| Readiness | `/readyz` | 20 s | 10 s | 3 | Removes pod from load balancer if DB is unreachable |
| Liveness | `/healthz` | 60 s | 20 s | 3 | Restarts pod if it becomes unresponsive |

**Resource limits**:

| | CPU | Memory |
|-|-----|--------|
| Requests | 100m | 128Mi |
| Limits | 500m | 512Mi |

### Service (`k8s/api/service.yaml`)

ClusterIP service named `db-api` in `db-stack` namespace. Maps port 80 → container port 8000. The ingress routes `/api` to this service.

## Building the image

```bash
# Build locally
docker build -t db-api:latest ./api

# Or use the helper script from the repo root
./build.sh
```

## Running locally (Docker Compose)

```bash
docker compose up --build
curl http://localhost:18000/api/name
curl http://localhost:18000/api/container-id
curl http://localhost:18000/healthz
curl http://localhost:18000/readyz
curl http://localhost:18000/metrics
```

The API is exposed on host port **18000** in Docker Compose (container port 8000).

See [LOCAL_TESTING.md](../LOCAL_TESTING.md) for the full test workflow.

## Logging

Structured log format: `%(asctime)s %(levelname)s [%(name)s] %(message)s`

Level: `INFO`. Warnings are emitted when container ID parsing fails. Errors are emitted when the readiness check fails.

## Relationship to other components

| Component | Relationship |
|-----------|-------------|
| `frontend/` | Frontend JavaScript calls `/api/name` and `/api/container-id` at page load |
| `k8s/api/` | Kubernetes Deployment and Service for running this image in the cluster |
| `k8s/monitoring/prometheus.yaml` | Prometheus scrapes `/metrics` via the `db-api` scrape job |
| `k8s/monitoring/service-monitor.yaml` | Prometheus Operator ServiceMonitor for the same purpose |
| `k8s/postgres/postgres.yaml` | The only component that `db-api` directly communicates with |
| `vagrant/scripts/update_name.sh` | Updates the `person` table row that `/api/name` reads |
