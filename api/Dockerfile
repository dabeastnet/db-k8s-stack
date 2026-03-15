FROM python:3.11-slim AS runtime

LABEL maintainer="db-k8s-stack builder"

ENV PYTHONUNBUFFERED=1
WORKDIR /app
ENV PYTHONPATH=/app
# Install system dependencies for psycopg2 and health checks
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libpq-dev postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy application code and Alembic migrations
COPY app/ /app/app/
COPY alembic.ini /app/
COPY migrations/ /app/migrations/

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create an unprivileged user to run the app
RUN groupadd -r appgroup --gid 1001 && \
    useradd -r -g appgroup --uid 1001 appuser && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8000

# Set default command to run the API. The entrypoint script will
# handle migrations and then exec into this command.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]