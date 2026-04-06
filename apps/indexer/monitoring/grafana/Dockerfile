# =============================================================================
# Grafana — Railway deployment
#
# Bakes provisioning config and dashboards into the image.
#
# Provisioned automatically (no manual setup in UI needed):
#   - Datasource: Prometheus at http://prometheus.railway.internal:9090
#   - Dashboards: all JSON files from grafana/dashboards/
#
# Grafana env vars (set in Railway service settings):
#   GF_SECURITY_ADMIN_USER     — admin username
#   GF_SECURITY_ADMIN_PASSWORD — admin password (use a secret)
#   GF_SERVER_ROOT_URL         — your public Grafana Railway URL
#   GF_USERS_ALLOW_SIGN_UP     — false
# =============================================================================
# Run as root so Railway's volume mount at /var/lib/grafana is writable.
# Railway mounts volumes owned by root; the default grafana user (UID 472)
# cannot write to them without this.
FROM grafana/grafana:latest
USER root
COPY provisioning /etc/grafana/provisioning
COPY dashboards /etc/grafana/dashboards
