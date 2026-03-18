# frontend — Apache Static Frontend

## Purpose

The `frontend` component is a static web server based on Apache HTTPD. It serves a single-page HTML/JavaScript application that displays a greeting with the user's name and the current API container ID, both fetched live from the FastAPI backend.

## What this component does

- Serves `index.html` from Apache HTTPD on port 8080
- The JavaScript page fetches `/api/name` and `/api/container-id` on load and updates the DOM
- Polls `version.txt` every 15 seconds; if the version string changes, the page auto-reloads — this implements the "automatic layout refresh" requirement
- In Kubernetes, Apache proxies `/api` requests to the internal `db-api` service (not used in production ingress path, but available as a fallback)

## Key files

| File | Purpose |
|------|---------|
| `Dockerfile` | Based on `httpd:2.4-alpine`; copies config and static files; creates non-root `appuser` (UID 1001) |
| `apache/httpd.conf` | Minimal Apache config: loads only required modules, listens on port 8080, proxies `/api` to `db-api.db-stack.svc.cluster.local`, disables directory listing |
| `src/index.html` | Single HTML page with inline JavaScript; fetches name and container ID, runs version polling loop |
| `static/version.txt` | Plain-text version string (default: `1`); increment to trigger a client-side page reload |

## How the auto-refresh works

The JavaScript in `index.html` calls `checkVersion()` every 15 seconds. It fetches `/version.txt` with a cache-busting query string, compares it to the previously seen value, and calls `location.reload()` if it has changed. To trigger a reload across all browser sessions, rebuild the image with a different `version.txt` content and redeploy the frontend.

## Container details

- **Base image**: `httpd:2.4-alpine`
- **Published image**: `ghcr.io/dabeastnet/db-frontend:v3`
- **Listening port**: `8080`
- **Run as**: `appuser` UID/GID 1001
- **Apache PID file**: `/tmp/httpd.pid` (writable by non-root user)
- **Logs**: stdout/stderr via `/proc/self/fd/1` and `/proc/self/fd/2`

## Apache proxy configuration

The `httpd.conf` defines a reverse proxy for the API:

```apache
ProxyPass        "/api"  "http://db-api.db-stack.svc.cluster.local:80/api"
ProxyPassReverse "/api"  "http://db-api.db-stack.svc.cluster.local:80/api"
```

This only resolves inside the Kubernetes cluster. In Docker Compose, the JavaScript makes direct `fetch` calls to `/api/...` which are proxied by Apache — however, the Apache proxy target is the Kubernetes DNS name and will not resolve in Docker Compose. The frontend still works in Docker Compose because the browser's JavaScript calls go to the Docker Compose network-reachable API directly (port 8000 is published at host level). The Apache proxy is a cluster-internal convenience and not used by browsers directly.

## Building locally

```bash
docker build -t db-frontend:latest ./frontend
```

Or from the repo root:

```bash
./build.sh
```

## Running locally

```bash
docker compose up --build
# Access at http://localhost:8080
```

See `LOCAL_TESTING.md` for full testing steps.

## Updating the layout

To trigger an automatic page reload across all connected browsers:

1. Edit `frontend/static/version.txt` (e.g. change `1` to `2`)
2. Rebuild the image: `docker compose build frontend`
3. Restart the container: `docker compose up -d frontend`

Within 15 seconds, any open browser tabs will detect the new version and reload.

## Relationship to other components

- **`api`** — The frontend JavaScript fetches data from the API at runtime. The Apache proxy config routes `/api` server-side, but browsers resolve the API through the nginx ingress.
- **`k8s/frontend/`** — Kubernetes Deployment and ClusterIP Service manifests.
- **`k8s/ingress/ingress.yaml`** — The nginx ingress routes `/` to the `db-frontend` service and `/api` to the `db-api` service; this is the path used in production.

## Resource limits (Kubernetes)

- Requests: `50m` CPU / `64Mi` memory
- Limits: `200m` CPU / `256Mi` memory
