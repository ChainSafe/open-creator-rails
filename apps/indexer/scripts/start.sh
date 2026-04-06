#!/bin/sh
set -eu

# =============================================================================
# Ponder Entrypoint — Supports API and Worker roles
# =============================================================================
#
# PONDER_ROLE (required):
#   "api"    — Runs `ponder serve` (HTTP only, no indexing).
#              Reads from the views schema. Always up, zero downtime.
#
#   "worker" — Runs `ponder start` (indexing + HTTP).
#              Blue-green: indexes into a unique schema, auto-swaps views on ready.
#              Refresh: resumes on a stable schema (crash recovery).
#
# Environment Variables:
#   PONDER_ROLE            — "api" or "worker" (default: "worker")
#   DEPLOYMENT_MODE        — "blue-green" or "refresh" (default: "blue-green", worker only)
#   DEPLOY_TAG             — Git tag (set by CI), sanitized into a Postgres schema name
#   VIEWS_SCHEMA           — Stable schema for DB views (default: "ocr_indexer")
#   STABLE_SCHEMA          — Schema for refresh mode (default: "ocr_indexer_live")
#   RAILWAY_DEPLOYMENT_ID  — Fallback schema in blue-green mode (provided by Railway)
#   DATABASE_URL           — Postgres connection string (required)
# =============================================================================

PONDER_ROLE="${PONDER_ROLE:-worker}"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-blue-green}"
VIEWS_SCHEMA="${VIEWS_SCHEMA:-ocr_indexer}"
STABLE_SCHEMA="${STABLE_SCHEMA:-ocr_indexer_live}"

# Sanitize a tag like "indexer@v1.2.3" → "indexer_v1_2_3" for Postgres schema name
sanitize_schema_name() {
  echo "$1" | sed 's/[^a-zA-Z0-9_]/_/g' | tr '[:upper:]' '[:lower:]'
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── API Mode ───────────────────────────────────────────────────────────────
if [ "$PONDER_ROLE" = "api" ]; then
  echo "  Ponder API Server"
  echo "  Views Schema: ${VIEWS_SCHEMA}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  exec pnpm serve --schema "$VIEWS_SCHEMA"

# ─── Worker Mode ────────────────────────────────────────────────────────────
elif [ "$PONDER_ROLE" = "worker" ]; then
  echo "  Ponder Worker"
  echo "  Mode: ${DEPLOYMENT_MODE}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Schema priority: DEPLOY_TAG (from CI) > RAILWAY_DEPLOYMENT_ID > timestamp.
  # In refresh mode, DEPLOY_TAG is intentionally not updated by CI so the schema
  # name stays the same — Ponder recognises it as the same app and resumes.
  # STABLE_SCHEMA (ocr_indexer_live) is the promoted views destination, never
  # the worker's own schema.
  if [ -n "${DEPLOY_TAG:-}" ]; then
    SCHEMA="$(sanitize_schema_name "$DEPLOY_TAG")"
  elif [ -n "${RAILWAY_DEPLOYMENT_ID:-}" ]; then
    SCHEMA="$RAILWAY_DEPLOYMENT_ID"
  else
    SCHEMA="local_$(date +%s)"
  fi

  if [ "$DEPLOYMENT_MODE" = "blue-green" ]; then
    echo "  Schema:       ${SCHEMA}"
    echo "  Views Schema: ${VIEWS_SCHEMA}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    exec pnpm start --schema "$SCHEMA" --views-schema "$VIEWS_SCHEMA"

  elif [ "$DEPLOYMENT_MODE" = "refresh" ]; then
    echo "  Schema:       ${SCHEMA}"
    echo "  Views Schema: ${VIEWS_SCHEMA}"
    echo "  (crash recovery / resume)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    exec pnpm start --schema "$SCHEMA" --views-schema "$VIEWS_SCHEMA"

  else
    echo "ERROR: Unknown DEPLOYMENT_MODE '${DEPLOYMENT_MODE}'"
    echo "       Expected 'blue-green' or 'refresh'"
    exit 1
  fi

else
  echo "ERROR: Unknown PONDER_ROLE '${PONDER_ROLE}'"
  echo "       Expected 'api' or 'worker'"
  exit 1
fi
