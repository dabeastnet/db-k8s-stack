FROM httpd:2.4-alpine

LABEL maintainer="db-k8s-stack builder"

# Copy custom Apache configuration
COPY apache/httpd.conf /usr/local/apache2/conf/httpd.conf

# Copy application source to document root
COPY src/ /usr/local/apache2/htdocs/
COPY static/version.txt /usr/local/apache2/htdocs/version.txt

# Create a non‑privileged user and group to run Apache
RUN addgroup -g 1001 appgroup \
    && adduser -D -u 1001 -G appgroup appuser \
    && mkdir -p /usr/local/apache2/logs /tmp/apache2 \
    && chown -R appuser:appgroup /usr/local/apache2/htdocs /usr/local/apache2/conf /usr/local/apache2/logs /tmp/apache2

USER 1001

# EXPOSE 80


# Health check: ensure Apache responds to HTTP requests
# HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
#   CMD wget -qO- http://localhost:80/ || exit 1

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://localhost:8080/ || exit 1

# The base image provides the default CMD to run httpd