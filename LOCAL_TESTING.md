# Local testing guide

This guide explains how to build the container images, run the application stack locally using Docker Compose and verify that the functional requirements are met.  The steps below should be executed from the root of the repository (`db‑k8s‑stack`).

## Prerequisites

* [Docker](https://docs.docker.com/) installed and running
* Bash or a compatible shell

## Building the images

Run the `build.sh` script to build the `db‑frontend` and `db‑api` images.  This script invokes `docker build` for each component.

```bash
./build.sh
```

If you wish to push the images to a registry, set the `REGISTRY` environment variable and run `push.sh` afterwards:

```bash
export REGISTRY=registry.example.com
./push.sh
```

## Starting the stack

Use Docker Compose to spin up the PostgreSQL, API and frontend services:

```bash
docker compose up --build
```

Docker Compose will automatically build the images (if not already built), create a `db-data` volume for PostgreSQL and start the three containers.  You should see logs indicating that the database is ready, migrations are applied and the API has started listening on port 8000.

## Verifying functionality

Open a new terminal or use a REST client such as `curl` or Postman to test the endpoints.  In the commands below, substitute `localhost` with your Docker host if necessary.

### Frontend

Navigate to http://localhost:18080 in your browser.  You should see a welcome message similar to:

```
Welcome, Dieter Beckers!
API Container ID: 123456789abc
```

The name and container ID are fetched asynchronously from the API.  If either value fails to load, check the API container logs (`docker compose logs api`).

> **Note**: The Apache frontend proxies `/api` requests to `db-api.db-stack.svc.cluster.local` — a Kubernetes-internal DNS name. This address does not resolve in Docker Compose. The JavaScript `fetch('/api/name')` call hits Apache, which tries to proxy it to the K8s cluster and fails. For Docker Compose testing, use the API endpoints directly on port `18000` as shown below.

### API endpoints

* **Get the current name**:

  ```bash
  curl -s http://localhost:18000/api/name | jq
  # { "name": "Dieter Beckers" }
  ```

* **Get the container ID**:

  ```bash
  curl -s http://localhost:18000/api/container-id | jq
  # { "container_id": "abcd1234ef56", "pod_name": "db-api", "hostname": "db-api" }
  ```

  The `container_id` field contains a truncated identifier derived from `/proc/self/cgroup`.  When running under Docker Compose, the `pod_name` and `hostname` values come from environment variables and may both be `db-api`.

* **Health and readiness probes**:

  ```bash
  curl -s http://localhost:18000/healthz
  # { "status": "ok" }

  curl -s http://localhost:18000/readyz
  # { "status": "ok" }
  ```

  The readiness probe executes a simple SQL query to verify that the database connection is alive.

* **Metrics**:

  ```bash
  curl -s http://localhost:18000/metrics | head
  # HELP db_api_requests_total Total API requests
  # TYPE db_api_requests_total counter
  db_api_requests_total{endpoint="/api/name",method="GET"} 1.0
  db_api_requests_total{endpoint="/api/container-id",method="GET"} 1.0
  # ...
  ```

  The API exposes Prometheus metrics at `/metrics`.  You can point a Prometheus instance at this endpoint or view the raw exposition format as shown.

### Updating the name

Use the convenience script provided in `scripts/update_name.sh` to change the name stored in the database.  You must set the database connection environment variables so that `psql` knows where to connect.

```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=demo
export DB_USER=demo
export DB_PASSWORD=demo
./scripts/update_name.sh "Alice"
```

The script updates the row in the `person` table.  Refresh http://localhost:18000/api/name and verify that the JSON response shows the new name.

### Testing automatic layout refresh

The frontend polls `version.txt` every 15 seconds.  To demonstrate automatic layout refresh:

1. Open http://localhost:18080 in a browser tab.
2. On your host machine, edit `frontend/static/version.txt` and change the version number (e.g. from `1` to `2`).
3. Rebuild and restart the frontend container:

   ```bash
   docker compose build frontend
   docker compose up -d frontend
   ```

Within 15 seconds, the page in your browser should reload automatically and reflect any changes you made to `index.html` or associated static files.

## Cleaning up

Stop the stack and remove the containers and volume with:

```bash
docker compose down -v
```

This will remove the containers and the `db-data` volume.  If you wish to preserve the database across runs, omit the `-v` flag.