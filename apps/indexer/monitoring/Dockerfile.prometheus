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
FROM prom/prometheus:latest
COPY prometheus.railway.yml /etc/prometheus/prometheus.yml
