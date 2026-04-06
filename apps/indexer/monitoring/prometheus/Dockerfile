# =============================================================================
# Prometheus — Railway deployment
#
# Bakes prometheus.railway.yml into the image so Railway doesn't need
# bind mounts. The config uses Railway private networking hostnames
# (<service>.railway.internal) instead of Docker socket discovery.
#
# Scraped services (configure names to match your Railway service names):
#   indexer-worker-blue  → port 42070  (may be inactive — scrape errors ignored)
#   indexer-worker-green → port 42070  (may be inactive — scrape errors ignored)
#   indexer-api          → port 42069
# =============================================================================
# Run as root so Railway's volume mount at /prometheus is writable.
# Railway mounts volumes owned by root; the default nobody user cannot
# write to them without this.
FROM prom/prometheus:latest
USER root
COPY prometheus.railway.yml /etc/prometheus/prometheus.yml
EXPOSE 9090
