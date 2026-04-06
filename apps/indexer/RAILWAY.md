# Railway Deployment Guide — Indexer & Monitoring

## Architecture

```
Railway Project
├── postgres               — shared Postgres database
├── indexer-worker-blue    — Ponder worker (blue slot)
├── indexer-worker-green   — Ponder worker (green slot)
├── indexer-api            — Ponder API / GraphQL serve node
├── prometheus             — scrapes metrics from workers + API
└── grafana                — dashboards (reads from Prometheus)
```

All services communicate via Railway private networking (`<service>.railway.internal`). No service needs a public URL except `indexer-api` (GraphQL endpoint) and `grafana` (dashboard UI).

---

## One-Time Setup

### 1. Create Railway services

Create the following **empty services** in your Railway project (names must match exactly):

| Service name | Public URL needed |
|---|---|
| `postgres` | No |
| `indexer-worker-blue` | Yes (for health-check polling during deploy) |
| `indexer-worker-green` | Yes (for health-check polling during deploy) |
| `indexer-api` | Yes (GraphQL endpoint) |
| `prometheus` | No |
| `grafana` | Yes (dashboard UI) |

### 2. Enable private networking

Railway project → **Settings → Networking** → enable private networking. This activates `.railway.internal` DNS between services.

### 3. Provision Postgres

Use Railway's native **Postgres plugin** or the empty `postgres` service. Copy the `DATABASE_URL` — you'll need it as an env var for the worker and API services.

### 4. Add volumes

| Service | Mount path | Purpose |
|---|---|---|
| `prometheus` | `/prometheus` | TSDB time-series data |
| `grafana` | `/var/lib/grafana` | SQLite DB, sessions, plugins |

Service → **Volumes** tab → **Add Volume** → set mount path.

> Grafana dashboards are baked into the image at `/etc/grafana/dashboards` and are unaffected by the `/var/lib/grafana` volume.

### 5. Set environment variables

**`indexer-worker-blue` and `indexer-worker-green`:**
```
PONDER_ROLE=worker
DATABASE_URL=<your-postgres-url>
PONDER_RPC_URL_11155111=<your-rpc-url>
DEPLOYMENT_MODE=blue-green
VIEWS_SCHEMA=ocr_indexer
STABLE_SCHEMA=ocr_indexer_live
PORT=42070
```

**`indexer-api`:**
```
PONDER_ROLE=api
DATABASE_URL=<your-postgres-url>
VIEWS_SCHEMA=ocr_indexer
PORT=42069
ACTIVE_SLOT=none          # managed automatically by deploy-indexer.yml
```

**`grafana`:**
```
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=<strong-password>
GF_USERS_ALLOW_SIGN_UP=false
GF_SERVER_ROOT_URL=https://<your-grafana-railway-url>
GF_PROMETHEUS_URL=http://prometheus.railway.internal:9090
```

### 6. Configure build settings

Dockerfile paths are defined in `railway.json` at the repo root. Railway resolves them automatically for the worker and API services.

For **prometheus** and **grafana**, each has its own `Dockerfile` in its subdirectory — Railway auto-detects it when deployed via `deploy-monitoring.yml`.

### 7. Add GitHub secrets

```
RAILWAY_API_TOKEN               — Railway API token (Settings → Tokens)
RAILWAY_PROJECT_ID              — Railway project UUID
RAILWAY_API_SERVICE_ID          — UUID for indexer-api service
RAILWAY_WORKER_BLUE_SERVICE_ID  — UUID for indexer-worker-blue service
RAILWAY_WORKER_GREEN_SERVICE_ID — UUID for indexer-worker-green service
RAILWAY_PROMETHEUS_SERVICE_ID   — UUID for prometheus service
RAILWAY_GRAFANA_SERVICE_ID      — UUID for grafana service
```

Service UUIDs are found under each service → **Settings** tab.

---

## Deployments

### Indexer (worker + API)

**Trigger:** push a tag matching `indexer@v*`

```bash
git tag indexer@v1.0.0
git push origin indexer@v1.0.0
```

Or trigger manually via **Actions → Deploy Indexer → Run workflow**.

**Mode detection** (automatic):

| Condition | Mode | What happens |
|---|---|---|
| `ponder.schema.ts` or `ponder.config.ts` changed | `blue-green` | New worker backfills into fresh schema, views swap on ready, old worker stopped |
| No schema changes | `refresh` | Active worker redeployed in place (fast, no downtime) |

**Blue-green flow:**
1. Inactive slot (blue or green) receives the new deployment
2. Worker backfills chain data into its own DB schema
3. Once `/ready` returns 200, Ponder auto-promotes the new schema to the views layer
4. CI updates `ACTIVE_SLOT` on the API service and stops the old worker
5. API redeploys to pick up new schema types — zero downtime throughout

**Timeout:** the workflow polls `/ready` for up to 2 hours to accommodate long backfills.

### Monitoring (Prometheus + Grafana)

**Trigger:** any push to `main` that changes files under `apps/indexer/monitoring/`

Or trigger manually via **Actions → Deploy Monitoring → Run workflow**.

Both services are deployed independently. Changes to dashboards, scrape config, or provisioning automatically redeploy only the monitoring stack.

---

## Local development

Run the full stack locally with Docker Compose:

```bash
# Set your RPC URL
export PONDER_RPC_URL_11155111=<your-rpc-url>

# Start everything
pnpm indexer:docker

# Tear down (keeps data)
pnpm indexer:docker:down

# Full reset (wipes all volumes)
pnpm indexer:docker:reset
```

Local service URLs:

| Service | URL |
|---|---|
| GraphQL API | http://localhost:42069 |
| Worker health | http://localhost:42070/ready |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (admin / admin) |

---

## Monitoring

Prometheus scrapes both worker slots at all times. The inactive slot produces scrape errors — this is expected and does not affect the active slot's metrics.

Scraped targets (Railway):

| Target | Internal address | Role label |
|---|---|---|
| `indexer-worker-blue` | `indexer-worker-blue.railway.internal:42070` | `worker` |
| `indexer-worker-green` | `indexer-worker-green.railway.internal:42070` | `worker` |
| `indexer-api` | `indexer-api.railway.internal:42069` | `api` |

The Grafana **Ponder Indexer** dashboard is provisioned automatically from `apps/indexer/monitoring/grafana/dashboards/ponder.json`. It covers:

- **Overview** — sync status, current block, chain head lag, node count, total events
- **Indexing** — latency, event rate, handler duration, RPC performance, DB operations
- **API** — request rate, latency p50/p95/p99
- **System Health** — errors, CPU, memory, GC, event loop, Postgres pool & queue

---

## File reference

```
apps/indexer/
├── Dockerfile                          — used by worker + API services
├── docker-compose.yaml                 — local development stack
└── monitoring/
    ├── prometheus/
    │   ├── Dockerfile                  — Railway: bakes prometheus.railway.yml
    │   ├── prometheus.yml              — local Docker scrape config (Docker SD)
    │   └── prometheus.railway.yml      — Railway scrape config (static targets)
    └── grafana/
        ├── Dockerfile                  — Railway: bakes provisioning + dashboards
        ├── provisioning/
        │   ├── datasources/
        │   │   └── prometheus.yml      — Prometheus datasource (uses $GF_PROMETHEUS_URL)
        │   └── dashboards/
        │       └── provider.yml        — points Grafana at /etc/grafana/dashboards
        └── dashboards/
            └── ponder.json             — Ponder Indexer dashboard definition

railway.json                            — Dockerfile paths for indexer services
.github/workflows/
├── deploy-indexer.yml                  — blue-green / refresh deploy for worker + API
└── deploy-monitoring.yml               — deploy for Prometheus + Grafana
```
