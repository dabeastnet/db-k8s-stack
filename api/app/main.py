"""
FastAPI application exposing endpoints for the db‑k8s‑stack.

This API provides endpoints to retrieve a user's name from a PostgreSQL
database and to reveal the running container's identifier. It also
exposes health, readiness, and metrics endpoints for Kubernetes and
Prometheus integration.
"""

import os
import logging
from typing import Generator

from fastapi import FastAPI, Depends, HTTPException
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session
from sqlalchemy import text
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import re

from .db import SessionLocal
from .models import Person

# Configure structured logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
logger = logging.getLogger(__name__)


def get_db() -> Generator[Session, None, None]:
    """Yield a database session and ensure it is closed afterwards."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


app = FastAPI(title="db‑k8s‑stack API", version="1.0.0")

# Prometheus metric: count of requests per endpoint and method
REQUEST_COUNT = Counter(
    'db_api_requests_total',
    'Total API requests',
    ['endpoint', 'method']
)


@app.get("/api/name", response_class=JSONResponse)
def get_name(db: Session = Depends(get_db)) -> JSONResponse:
    """Return the current name stored in PostgreSQL."""
    REQUEST_COUNT.labels(endpoint='/api/name', method='GET').inc()
    person = db.query(Person).first()
    if person:
        return JSONResponse(content={"name": person.name})
    return JSONResponse(content={"name": "Unknown"})


# @app.get("/api/container-id", response_class=JSONResponse)
# def get_container_id() -> JSONResponse:
#     """Return the container ID and contextual pod/host information."""
#     REQUEST_COUNT.labels(endpoint='/api/container-id', method='GET').inc()
#     container_id = "unknown"
#     try:
#         # Parse the cgroup file to extract the Docker or containerd ID
#         with open("/proc/self/cgroup", "r") as f:
#             for line in f:
#                 parts = line.strip().split(":")
#                 if len(parts) == 3 and parts[1] in {"cpu", "pids", "memory"}:
#                     fields = parts[2].split("/")
#                     # Last field should contain container ID or pod UIDs
#                     if fields:
#                         container_id = fields[-1][:12]
#                         break
#     except Exception as exc:
#         logger.warning("Failed to parse container ID: %s", exc)
#     return JSONResponse(
#         content={
#             "container_id": container_id,
#             "pod_name": os.getenv("POD_NAME", ""),
#             "hostname": os.getenv("HOSTNAME", "")
#         }
#     )
@app.get("/api/container-id", response_class=JSONResponse)
def get_container_id() -> JSONResponse:
    REQUEST_COUNT.labels(endpoint="/api/container-id", method="GET").inc()
    container_id = "unknown"

    try:
        with open("/proc/self/cgroup", "r") as f:
            content = f.read()

        patterns = [
            r"cri-containerd-([a-f0-9]{64})\.scope",
            r"containerd[-:/]([a-f0-9]{64})",
            r"\b([a-f0-9]{64})\b",
        ]

        for pattern in patterns:
            match = re.search(pattern, content)
            if match:
                container_id = match.group(1)[:12]
                break

    except Exception as exc:
        logger.warning("Failed to parse container ID: %s", exc)

    return JSONResponse(
        content={
            "container_id": container_id,
            "pod_name": os.getenv("POD_NAME", ""),
            "hostname": os.getenv("HOSTNAME", "")
        }
    )

@app.get("/healthz", response_class=JSONResponse)
def healthz() -> JSONResponse:
    """Liveness probe endpoint."""
    return JSONResponse(content={"status": "ok"})


@app.get("/readyz", response_class=JSONResponse)
def readyz(db: Session = Depends(get_db)) -> JSONResponse:
    """Readiness probe endpoint that checks database connectivity."""
    try:
        db.execute(text("SELECT 1"))
        return JSONResponse(content={"status": "ok"})
    except Exception as exc:
        logger.error("Readiness check failed: %s", exc)
        raise HTTPException(status_code=503, detail="Database not ready")


@app.get("/metrics")
def metrics() -> Response:
    """Expose Prometheus metrics."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)