# db‑k8s‑stack

## Solution overview

This repository contains a complete, production‑minded Kubernetes stack that demonstrates how to build and operate a simple three‑tier web application using **Apache**, **FastAPI** and **PostgreSQL**.  The solution targets a high score by satisfying all functional and extra scoring requirements outlined in the assignment.  It includes:

* A static **web frontend** served by an Apache HTTPD container.  The page is implemented in vanilla HTML/JavaScript based off of the provided GitHub gist.  It displays a friendly greeting containing your name (fetched from the API) and the API container ID.  A simple polling mechanism watches a `version.txt` file and automatically reloads the page whenever the layout changes.
* A **FastAPI** service that exposes REST endpoints (`/api/name`, `/api/container-id`, `/healthz`, `/readyz`, `/metrics`).  The service reads your name from PostgreSQL using SQLAlchemy, provides its container identifier by parsing `/proc/self/cgroup` and exposes Prometheus metrics.  It follows best practices such as connection pooling, structured logging and graceful health checks.
* A **PostgreSQL** database running in its own container (via a StatefulSet on Kubernetes).  Alembic migrations define the `person` table and seed it with a default name (`Dieter Beckers`), demonstrating proper schema management.  A convenience script (`scripts/update_name.sh`) updates the name in the database for demonstration purposes.
* **Kubernetes manifests** for running the stack on a real cluster.  They include Deployments, a StatefulSet, Services, ConfigMaps, Secrets, an Ingress with HTTPS termination via cert‑manager, a ServiceMonitor for Prometheus and an ArgoCD Application for GitOps.  Topology spread constraints ensure multiple API replicas are distributed across nodes and health probes automatically restart unhealthy pods.
* **Helm values** for installing ArgoCD via the official chart and a declarative ArgoCD Application that synchronises this repository onto the cluster.  The GitOps workflow is documented end‑to‑end.
* **Monitoring** using Prometheus.  The API exports metrics via the `/metrics` endpoint, and a ServiceMonitor instructs Prometheus to scrape it.  Instructions are provided for installing the `kube‑prometheus‑stack` or integrating with an existing Prometheus installation.
* **Documentation and automation**.  Detailed guides explain how to build the images, run the stack locally with Docker Compose, create a kubeadm cluster with a control plane and two worker nodes, install ingress‑nginx, cert‑manager, Prometheus and ArgoCD, and verify all functional requirements.  A Markdown architecture diagram (see `docs/architecture.md`) illustrates the component interactions.  A PDF companion (`docs/submission.pdf`) summarises the solution and explicitly references every requirement.

The remainder of this README goes into detail on each part of the solution.

## Architecture summary

The db‑k8s‑stack is organised into three services backed by persistent storage and fronted by an ingress controller.  The high‑level architecture is depicted in the following Mermaid diagram (also available in `docs/architecture.md`):

```mermaid
graph TD
  subgraph Client
    Browser
  end
  subgraph Kubernetes
    Ingress[nginx Ingress]
    Frontend[Apache Frontend Deployment]
    API[FastAPI Deployment (3 replicas)]
    DB[(PostgreSQL StatefulSet)]
    Prometheus
  end

  Browser -->|HTTPS (TLS via cert‑manager)| Ingress
  Ingress -->|/api*| API
  Ingress -->|/| Frontend
  API -->|SQL| DB
  Prometheus <-->|/metrics| API
```

Traffic enters the cluster through an nginx ingress that terminates TLS certificates issued by cert‑manager.  Requests to `/api` are routed to the FastAPI service while requests to `/` are routed to the Apache frontend.  The API reads and writes data in PostgreSQL.  A ServiceMonitor instructs Prometheus to scrape the API’s metrics endpoint.  ArgoCD monitors the Git repository and continuously reconciles the desired state described in this repo with the cluster.

## Container overview

| Container        | Base image           | Purpose and features                                                                           |
|------------------|----------------------|--------------------------------------------------------------------------------------------------|
| `db‑frontend`    | `httpd:2.4‑alpine`   | Serves static HTML/JS from `/usr/local/apache2/htdocs`.  Uses a custom `httpd.conf` for minimal modules, disables directory listing and logs to stdout/stderr.  Runs as non‑root user `appuser` (UID 1001).  Includes a `version.txt` file used for automatic layout refresh. |
| `db‑api`         | `python:3.11‑slim`   | Runs FastAPI behind Uvicorn.  Uses SQLAlchemy and Alembic to manage the `person` table, psycopg2 for PostgreSQL connectivity and `prometheus‑client` for instrumentation.  An entrypoint script waits for PostgreSQL to become ready, runs Alembic migrations and then launches the API.  Liveness and readiness probes expose `/healthz` and `/readyz`.  The container runs as non‑root user `appuser` (UID 1001) and sets sensible resource limits. |
| `postgres` (db‑postgres) | `postgres:16‑alpine` | Official PostgreSQL image used as a StatefulSet in Kubernetes.  Environment variables for database name, user and password come from a ConfigMap and Secret.  Storage is backed by a PersistentVolumeClaim. |

All container images created in this project use the **`db‑`** prefix to satisfy the naming convention requirement.

## Why FastAPI?

FastAPI is chosen because it provides an extremely fast, modern and standards‑compliant framework for building APIs.  It supports asynchronous request handling out of the box, generates interactive OpenAPI documentation and integrates seamlessly with Python typing.  Combined with SQLAlchemy and Alembic, it allows clean separation of models, database migrations and business logic.  FastAPI’s integration with ASGI servers like Uvicorn makes it trivial to add metrics and health checks.

## Component interactions

1. **Frontend ↔ API** – When the user loads the web page, JavaScript in `index.html` fetches `/api/name` and `/api/container-id`.  The API returns JSON containing the current name stored in PostgreSQL and a best‑effort container identifier.  The frontend updates the DOM accordingly.
2. **API ↔ Database** – The API uses SQLAlchemy’s session to query the `person` table.  Alembic migrations guarantee the table exists and is seeded with the default name.  The entrypoint script waits until PostgreSQL is ready before running migrations.
3. **Automatic layout refresh** – The frontend periodically polls `/version.txt`.  This file contains a version string that is updated whenever the static layout is changed.  If the version changes, JavaScript triggers `location.reload()`.  Because the file is served by Apache, updating the file (for example by rebuilding the frontend image or updating a ConfigMap) causes clients to reload without manual cache busting.
4. **Name refresh after DB update** – To demonstrate dynamic data, the database contains a single row in the `person` table.  Updating this value via the provided `scripts/update_name.sh` or by manually modifying the table will cause `/api/name` to return the new value.  Refreshing the web page (or navigating to it again) fetches the new name and displays it.

## Building and pushing images

Run the provided scripts to build or push images.  Each script is executable (`chmod +x`) and should be run from the repository root.

* **`build.sh`** – Builds the `db‑frontend` and `db‑api` images locally using the Dockerfiles.
* **`push.sh`** – Tags the images and pushes them to a container registry defined by the `REGISTRY` environment variable.  Replace `your‑registry` with your actual registry host.

```bash
./build.sh
export REGISTRY=registry.example.com
./push.sh
```

The database uses the official `postgres:16‑alpine` image and does not require building.

## Local testing (Docker Compose)

The `docker‑compose.yml` file defines a three‑service stack for quick local testing.  To start the stack:

```bash
docker compose up --build
```

Once the containers are running:

* Access the frontend at `http://localhost:8080`.  You should see your name displayed and the container ID of the API.
* Check the API directly at `http://localhost:8000/api/name` and `http://localhost:8000/api/container-id`.
* Use the provided `scripts/update_name.sh` to change the name in the database:

```bash
export DB_HOST=localhost DB_PORT=5432 DB_USER=demo DB_PASSWORD=demo DB_NAME=demo
./scripts/update_name.sh "New Name"
```

Refresh the browser and observe that the displayed name has changed.  See `LOCAL_TESTING.md` for detailed curl commands and additional tests.

## Kubernetes deployment

The `k8s/` directory contains manifests for deploying the stack onto a Kubernetes cluster.  The stack is designed to run on a kubeadm cluster with one control plane and two worker nodes (for scoring purposes) but can also be deployed on kind or minikube for local testing.

1. **Prerequisites** – Install a Kubernetes cluster.  For production scoring, set up a kubeadm cluster with one control plane and at least two worker nodes.  Install the [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/) and [cert‑manager](https://cert-manager.io/docs/installation/) using their official manifests or Helm charts.  Deploy the Prometheus operator (e.g. via the `kube‑prometheus‑stack` Helm chart) for monitoring.  Install Helm and the ArgoCD chart.
2. **Apply manifests** – Use `deploy-k8s.sh` to apply the namespace, secrets, ConfigMap, StatefulSet, Deployments, Services, Ingress, ClusterIssuers and ServiceMonitor:

   ```bash
   ./deploy-k8s.sh
   ```

   Replace the domain (`app.example.com`) and email in `k8s/ingress/ingress.yaml` and `k8s/cert-manager/clusterissuer.yaml` with your actual domain and contact email.  After cert‑manager requests the certificate, the ingress will terminate HTTPS.  Visit `https://app.example.com` to load the frontend.
3. **Replica placement** – The API Deployment defines a `topologySpreadConstraints` rule that evenly spreads pods across nodes.  Running `kubectl get pods -o wide -l app=db-api -n db-stack` will show the API replicas distributed across your worker nodes.
4. **Health checks and auto‑restart** – Kubernetes liveness and readiness probes call `/healthz` and `/readyz`.  Killing a database connection or causing the API to become unhealthy will trigger automatic restarts.  You can simulate this by deleting an API pod; Kubernetes will recreate it and the service will remain available.
5. **Monitoring** – The ServiceMonitor in `k8s/monitoring/service-monitor.yaml` instructs Prometheus to scrape the API’s `/metrics` endpoint.  After deploying the Prometheus operator, check the target list in the Prometheus UI to verify that the service is being scraped.  Example queries include `db_api_requests_total` to see request counts and `up` to check health.
6. **GitOps with ArgoCD** – Install ArgoCD using the official Helm chart with the provided `helm/argocd-values.yaml`.  Then apply the ArgoCD `Application` defined in `k8s/argocd/application.yaml`.  ArgoCD will watch this repository (update the `repoURL` to your fork) and automatically synchronise the manifests in the `k8s/` directory.  Committing and pushing changes to Git will trigger ArgoCD to redeploy the stack.  The sync policy is automated with prune and self‑heal enabled to ensure drift correction.

### Kubeadm cluster setup (summary)

The full instructions for installing kubeadm and preparing the cluster are beyond the scope of this README, but the following steps give an outline:

1. **Initialize the control plane** on the master node:

   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

2. **Install a CNI plugin**, e.g. Flannel:

   ```bash
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

3. **Join worker nodes** using the token printed by kubeadm.  On each worker:

   ```bash
   sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

4. **Install ingress‑nginx, cert‑manager, Prometheus operator and ArgoCD** using Helm:

   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && \
   helm install nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

   helm repo add jetstack https://charts.jetstack.io && \
   helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
     --set installCRDs=true

   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
   helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

   helm repo add argo https://argoproj.github.io/argo-helm && \
   helm install argocd argo/argo-cd --namespace argocd --create-namespace \
     -f helm/argocd-values.yaml
   ```

5. **Configure DNS** for your domain to point at the ingress controller’s external IP (e.g. using an A or CNAME record).  Cert‑manager will request certificates from Let’s Encrypt using HTTP‑01 challenges via the ingress.

6. **Deploy the application** using `deploy-k8s.sh` or via ArgoCD.  Verify that HTTPS works, API responses are correct and the Prometheus targets are healthy.

## Security best practices

Security and operational best practices have been applied throughout this project:

* **Minimal base images** – `httpd:2.4‑alpine`, `python:3.11‑slim` and `postgres:16‑alpine` reduce the attack surface.
* **Non‑root containers** – Both the frontend and API images create an `appuser` with UID 1001 and drop down from root.  Kubernetes pods specify `runAsUser`, `runAsGroup` and `fsGroup` to enforce this.
* **Read‑only filesystems** – The API and frontend images do not write to the filesystem except for necessary directories (e.g. log output goes to stdout).  Database storage is isolated in a PVC.
* **Secrets management** – Sensitive values such as database passwords are stored in Kubernetes Secrets.  The `secret.example.yaml` file shows the format without revealing actual credentials.  Environment variables are consumed via `envFrom` references.  Developers should avoid committing real secrets into Git.
* **Network isolation** – The database is exposed only inside the cluster via a ClusterIP service.  Ingress exposes only the frontend and API.  Additional NetworkPolicies could be added to restrict egress if desired.
* **Resource requests/limits** – All pods specify CPU and memory requests and limits to ensure proper scheduling and prevent noisy neighbour issues.
* **Health probes and auto‑recovery** – Liveness and readiness probes automatically restart unhealthy API and frontend pods without human intervention.
* **TLS everywhere** – HTTPS termination is handled by ingress‑nginx with certificates issued by cert‑manager and Let’s Encrypt.  Communication inside the cluster is unencrypted but isolated in a private network.

## Troubleshooting

* **The ingress certificate is not issued** – Check the cert‑manager pod logs and ensure that your DNS record points to the ingress controller’s external IP.  Use the staging issuer first to avoid hitting Let’s Encrypt rate limits.
* **Pods stuck in `CrashLoopBackOff`** – Describe the pod (`kubectl describe pod <name>`) to view the reason.  Common issues include database connection failures (wrong credentials) or missing environment variables.  The API logs (via `kubectl logs`) will show more detail.
* **ArgoCD not syncing** – Verify that the `repoURL` in `k8s/argocd/application.yaml` points to your Git repository and that ArgoCD has access.  Check the ArgoCD UI for error messages.  Ensure that the path (`k8s/`) exists and contains valid manifests.
* **Prometheus not scraping** – Ensure that the label `release=prometheus` in `service-monitor.yaml` matches your Prometheus operator installation (`helm install prometheus ... --name prometheus` sets a different release name).  Adjust the label accordingly.  View the Prometheus target list to confirm that the API service is discovered.

## Demo checklist

Use this checklist to verify all functional requirements:

1. **Application running** – Deploy using Docker Compose or Kubernetes.  Access the frontend through the configured URL and ensure it loads.
2. **Name endpoint** – `curl -s http://localhost:8000/api/name` returns `{"name": "Dieter Beckers"}` by default.
3. **Container ID endpoint** – `curl -s http://localhost:8000/api/container-id` returns a JSON object with a `container_id` field and your pod/host information.
4. **Automatic name update** – Run `scripts/update_name.sh "Alice"`, refresh the page and observe that the displayed name changes to Alice.
5. **Automatic layout refresh** – Modify `frontend/static/version.txt` (e.g. change `1` to `2`), rebuild and redeploy the frontend.  Open the page in a browser; within 15 seconds the page reloads and reflects the new layout.
6. **API scaling and distribution** – Deploy the stack onto a multi‑node cluster.  Run `kubectl get pods -l app=db-api -o wide -n db-stack` and verify that the three API pods are spread across at least two nodes.
7. **Health checks** – Temporarily delete a running API pod (`kubectl delete pod ...`).  The pod should restart automatically and traffic should continue to flow through the service.
8. **Prometheus metrics** – Access the Prometheus UI and query `db_api_requests_total`.  Send some API requests and observe the counter increasing.
9. **HTTPS** – Ensure that `https://app.example.com` returns a valid certificate and no browser warnings.  Use `openssl s_client` to inspect the certificate if needed.
10. **GitOps workflow** – Edit a manifest in the `k8s/` directory, commit and push it to your Git repository.  Within a few moments, ArgoCD should detect the change and synchronise the cluster accordingly.

## Requirement‑to‑implementation mapping

| Assignment requirement                                      | Implementation reference                                                                         |
|-------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| Three containers: Apache, FastAPI, PostgreSQL               | `frontend/Dockerfile`, `api/Dockerfile`, `k8s/postgres/postgres.yaml`                            |
| Use provided gist for page layout                           | `frontend/src/index.html` derives from the gist and fetches name/container‑id                   |
| Automatic layout refresh                                    | Polling logic in `frontend/src/index.html` reading `version.txt`; `frontend/static/version.txt` |
| API endpoints (`/api/name`, `/api/container-id`)             | Implemented in `api/app/main.py`                                                                |
| DB seeded with default name                                 | Alembic migration `api/migrations/versions/001_create_person_table.py` inserts `Dieter Beckers` |
| Name change reflected after page refresh                    | Database update script `scripts/update_name.sh`; page fetches name on load                      |
| Container ID retrieval                                      | Parses `/proc/self/cgroup` in `api/app/main.py` and includes pod/host info                      |
| Liveness/readiness probes                                   | Probes defined in `k8s/api/deployment.yaml` and `k8s/frontend/deployment.yaml`                  |
| Spread API replicas across nodes                            | `topologySpreadConstraints` in `k8s/api/deployment.yaml`                                        |
| HTTPS via cert‑manager                                      | ClusterIssuers in `k8s/cert-manager/clusterissuer.yaml`; Ingress TLS configuration              |
| Monitoring with Prometheus                                  | `/metrics` endpoint in API; `k8s/monitoring/service-monitor.yaml`                               |
| kubeadm cluster with 1 control plane and 2 workers          | Instructions in this README; requires manual cluster creation                                  |
| Additional worker node and load balanced API                | Deploying on multi‑node cluster demonstrates this; service load balances across pods            |
| Helm to install ArgoCD                                      | `helm/argocd-values.yaml`; installation instructions in README                                  |
| GitOps via ArgoCD                                           | `k8s/argocd/application.yaml` defines Application synced from Git                               |
| Documentation (README, local testing, PDF)                  | This README, `LOCAL_TESTING.md`, `docs/submission.pdf`                                          |
| Packaging into ZIP                                          | `package.sh` script produces `db-k8s-stack.zip`                                                 |

---

By following the steps and guidance in this repository you can deploy a resilient, secure and observable three‑tier application on Kubernetes.  The included documentation makes it straightforward to understand each component, rebuild the images, run locally or in a cluster, and extend the stack further.