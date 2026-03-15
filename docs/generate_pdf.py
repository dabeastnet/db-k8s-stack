#!/usr/bin/env python3
"""
Generate a submission PDF summarising the db‑k8s‑stack solution.
This script uses the reportlab library to produce a short but complete PDF
that explicitly mentions every component requested in the assignment.

Run this script from the `docs` directory:

    python generate_pdf.py

It will create `submission.pdf` in the same directory.
"""

from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch


def write_multiline(c, text, x, y, max_width):
    """Utility function to draw multiline text with word wrapping."""
    from textwrap import wrap
    lines = []
    for paragraph in text.split("\n"):
        lines += wrap(paragraph, width=max_width)
        lines.append("")
    for line in lines:
        c.drawString(x, y, line)
        y -= 12  # line height
    return y


def main():
    c = canvas.Canvas("submission.pdf", pagesize=letter)
    width, height = letter
    margin = 0.5 * inch
    y = height - margin

    c.setFont("Helvetica-Bold", 16)
    c.drawString(margin, y, "db‑k8s‑stack: Submission Summary")
    y -= 24

    c.setFont("Helvetica", 10)
    intro = (
        "This document summarises the solution delivered for the three‑tier web application "
        "assignment.  The application consists of an Apache‑based web frontend, a FastAPI "
        "service and a PostgreSQL database, deployed onto Kubernetes with monitoring, TLS and "
        "GitOps.  Every requested component is explicitly mentioned below."
    )
    y = write_multiline(c, intro, margin, y, 95)

    sections = [
        ("Components", (
            "• Web frontend: An Apache HTTPD container (`db‑frontend`) serves static HTML/JS.  "
            "It uses a custom `httpd.conf`, runs as a non‑root user and polls `version.txt` "
            "to automatically refresh when the layout changes.\n"
            "• API service: A FastAPI application in the `db‑api` container exposes `/api/name`, "
            "`/api/container-id`, `/healthz`, `/readyz` and `/metrics`.  It uses SQLAlchemy and Alembic "
            "to interact with PostgreSQL and runs with structured logging, connection pooling and "
            "Prometheus instrumentation.\n"
            "• Database: A PostgreSQL instance (`db‑postgres`) stores a `person` table seeded with "
            "`Dieter Beckers`.  It runs in a StatefulSet backed by a PersistentVolumeClaim."
        )),
        ("Kubernetes", (
            "• Namespace: All resources live in the `db-stack` namespace.\n"
            "• Deployments: The API runs with three replicas and topology spread constraints to distribute "
            "pods across nodes.  The frontend runs with one replica.\n"
            "• StatefulSet: PostgreSQL runs as a StatefulSet with persistent storage.\n"
            "• Services: ClusterIP services expose the API and frontend internally.\n"
            "• Ingress: An nginx ingress routes `/api` to the API and `/` to the frontend.  TLS certificates "
            "are provisioned by cert‑manager using Let’s Encrypt.\n"
            "• Secrets/ConfigMaps: Database credentials are stored in Secrets; non‑sensitive settings "
            "reside in a ConfigMap.\n"
            "• Monitoring: A ServiceMonitor tells Prometheus to scrape `/metrics` from the API.\n"
            "• GitOps: An ArgoCD `Application` points to this repository and synchronises the `k8s/` directory."
        )),
        ("Security and best practices", (
            "• Minimal base images and non‑root users in all containers.\n"
            "• Resource requests/limits and health probes ensure stability and auto‑recovery.\n"
            "• Sensitive data stored in Kubernetes Secrets; configuration separated into ConfigMaps.\n"
            "• TLS termination with cert‑manager; internal services are not publicly exposed."
        )),
        ("Operations", (
            "• Local testing: Docker Compose spins up the three services for quick development.\n"
            "• Packaging: Scripts (`build.sh`, `push.sh`, `deploy-k8s.sh`, `test-local.sh`, etc.) automate "
            "building, pushing and deploying the stack.  A `package.sh` script produces `db-k8s-stack.zip`.\n"
            "• Kubeadm instructions: The README describes how to initialise a control plane, join two worker nodes, "
            "install ingress‑nginx, cert‑manager, Prometheus and ArgoCD, and deploy the application."
        )),
        ("GitOps workflow", (
            "Changes to the manifests are committed to Git and automatically applied by ArgoCD.  The "
            "sync policy enables pruning and self‑healing to enforce the declared state."
        )),
    ]

    for title, content in sections:
        y -= 18
        c.setFont("Helvetica-Bold", 12)
        c.drawString(margin, y, title)
        y -= 14
        c.setFont("Helvetica", 9)
        y = write_multiline(c, content, margin, y, 95)

    c.save()
    print("PDF generated: submission.pdf")


if __name__ == '__main__':
    main()