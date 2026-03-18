# frontend — Apache Static Frontend

## Purpose

The `frontend` component is a static web server built on Apache HTTPD. It serves a single-page HTML/JavaScript application that displays a greeting with the user's name and the current API container ID, both fetched live from the FastAPI backend. It also implements the automatic layout refresh requirement by polling a version file.

## Directory structure

```
frontend/
├── Dockerfile                  Container image definition
├── apache/
│   └── httpd.conf              Custom Apache configuration (minimal modules, non-root port)
├── src/
│   └── index.html              Single-page app with inline JavaScript
└── static/
    └── version.txt             Version string for triggering automatic page reload (default: "1")
```

## How it works

### Page load

When a browser opens the page, `index.html` runs two `async` fetch calls in parallel:

1. `GET /api/name` → updates the `<span id="user">` element with the name from the database
2. `GET /api/container-id` → updates `<span id="containerId">` with the container ID

Both elements show `Loading…` while the fetches are in-flight and `Unavailable` if they fail.

### Automatic layout refresh

After initial load, the JavaScript calls `checkVersion()` and then repeats it every 15 seconds:

```javascript
async function checkVersion() {
    const res = await fetch('/version.txt?_t=' + new Date().getTime());
    const versionText = (await res.text()).trim();
    if (window.currentVersion && window.currentVersion !== versionText) {
        location.reload();
        return;
    }
    window.currentVersion = versionText;
}
```

The cache-busting query string (`?_t=<timestamp>`) prevents the browser from returning a cached copy. If the version string changes between polls, the page reloads immediately. This satisfies the "automatic layout refresh when the page changes" requirement.

To trigger a reload: update `frontend/static/version.txt`, rebuild the image, and redeploy the container.

## Apache configuration (`apache/httpd.conf`)

Key settings:

| Setting | Value | Reason |
|---------|-------|--------|
| `Listen` | `8080` | Non-root users cannot bind to ports below 1024 |
| `PidFile` | `/tmp/httpd.pid` | Writable by non-root user |
| `ServerName` | `localhost` | Suppresses "could not determine FQDN" warning |
| `Options -Indexes` | enabled | Disables directory listing |
| `ErrorLog` | `/proc/self/fd/2` | Logs to container stderr |
| `CustomLog` | `/proc/self/fd/1` | Logs to container stdout |

Loaded modules (minimal set): `mpm_event`, `authn_core`, `authz_core`, `access_compat`, `alias`, `dir`, `log_config`, `mime`, `unixd`, `proxy`, `proxy_http`.

The Apache reverse proxy configuration forwards `/api` requests to the internal Kubernetes DNS name:

```apache
ProxyPreserveHost On
ProxyPass        "/api"  "http://db-api.db-stack.svc.cluster.local:80/api"
ProxyPassReverse "/api"  "http://db-api.db-stack.svc.cluster.local:80/api"
ProxyPass        "/api/" "http://db-api.db-stack.svc.cluster.local:80/api/"
ProxyPassReverse "/api/" "http://db-api.db-stack.svc.cluster.local:80/api/"
```

> **Note**: This proxy target only resolves inside the Kubernetes cluster. In Docker Compose, the browser's JavaScript makes `fetch` calls directly to `/api/...`, which Apache proxies — but the Kubernetes DNS name does not exist in Docker Compose. In practice, when running with Docker Compose and accessing the frontend from a browser on the host, the JavaScript `fetch('/api/name')` hits the Apache server, which tries to proxy it to the K8s DNS and fails. **For Docker Compose testing, the API endpoints should be tested directly on port 18000.** The full proxy path works only inside the Kubernetes cluster or when accessed through the nginx ingress.

## Dockerfile walkthrough

```dockerfile
FROM httpd:2.4-alpine

COPY apache/httpd.conf /usr/local/apache2/conf/httpd.conf
COPY src/ /usr/local/apache2/htdocs/
COPY static/version.txt /usr/local/apache2/htdocs/version.txt

# Create non-root user and transfer ownership
RUN addgroup -g 1001 appgroup && adduser -D -u 1001 -G appgroup appuser
RUN mkdir -p /usr/local/apache2/logs /tmp/apache2
RUN chown -R appuser:appgroup \
    /usr/local/apache2/htdocs \
    /usr/local/apache2/conf \
    /usr/local/apache2/logs \
    /tmp/apache2

USER 1001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s \
    CMD wget -qO- http://localhost:8080/ || exit 1
```

Key points:
- `httpd:2.4-alpine` keeps the image small and reduces attack surface
- All relevant directories are owned by `appuser` (UID 1001) so Apache can write its PID file and logs
- A Docker `HEALTHCHECK` is defined (used in Docker Compose; Kubernetes uses its own probes)

## Container details

| Property | Value |
|----------|-------|
| Base image | `httpd:2.4-alpine` |
| Published image | `ghcr.io/dabeastnet/db-frontend:v3` |
| Listening port | `8080` |
| Run as | UID 1001 (`appuser`) |
| Docker Compose host port | `18080` |

## Kubernetes resources (`k8s/frontend/`)

### Deployment (`k8s/frontend/deployment.yaml`)

- **Replicas**: 1
- **Security context**: `runAsUser: 1001`, `runAsGroup: 1001`, `fsGroup: 1001`
- **Readiness probe**: `GET /` on port `http` — initial delay 10 s, period 10 s
- **Liveness probe**: `GET /` on port `http` — initial delay 20 s, period 20 s

**Resource limits**:

| | CPU | Memory |
|-|-----|--------|
| Requests | 50m | 64Mi |
| Limits | 200m | 256Mi |

### Service (`k8s/frontend/service.yaml`)

ClusterIP service `db-frontend` in `db-stack` namespace. Port 80 → container port 8080. The nginx ingress routes path `/` (with host `project.beckersd.com`) to this service.

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
# Browser: http://localhost:18080
```

Note: in Docker Compose, verify the API separately on http://localhost:18000 because the Apache proxy target (`db-api.db-stack.svc.cluster.local`) does not resolve outside the Kubernetes cluster.

## Updating the layout / triggering auto-reload

1. Make changes to `frontend/src/index.html` (or any static file)
2. Increment the version string in `frontend/static/version.txt` (e.g. `1` → `2`)
3. Rebuild and redeploy:

   **Docker Compose**:
   ```bash
   docker compose build frontend
   docker compose up -d frontend
   ```

   **Kubernetes** (after pushing the new image):
   ```bash
   kubectl rollout restart deployment db-frontend -n db-stack
   ```

Within 15 seconds all open browser tabs will detect the new version and reload automatically.

## Relationship to other components

| Component | Relationship |
|-----------|-------------|
| `api/` | JavaScript fetches `/api/name` and `/api/container-id` from the API at runtime |
| `k8s/frontend/` | Kubernetes Deployment and Service manifests |
| `k8s/ingress/ingress.yaml` | nginx ingress routes `/` (Host: `project.beckersd.com`) to `db-frontend:80` |
| `docker-compose.yml` | Builds and runs the frontend image on host port 18080 |
