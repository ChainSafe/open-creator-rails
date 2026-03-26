FROM node:22-alpine AS base

# =============================================================================
# Monorepo-aware Dockerfile for the Ponder indexer
# Build context must be the REPO ROOT (not apps/indexer) so that pnpm can
# resolve workspace:* dependencies like @open-creator-rails/config.
# =============================================================================

# 1. Install dependencies (from monorepo root)
FROM base AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy workspace root manifests
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# Copy package.json for each workspace package (needed for pnpm install)
COPY apps/indexer/package.json ./apps/indexer/package.json
COPY packages/config/package.json ./packages/config/package.json

RUN pnpm install --frozen-lockfile

# 2. Build / codegen
FROM base AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY --from=deps /app/ ./

# Copy full source for all packages the indexer depends on
COPY packages/config/ ./packages/config/
COPY apps/indexer/ ./apps/indexer/

# Run codegen to generate ponder-env.d.ts and types
RUN cd apps/indexer && pnpm run codegen

# 3. Production runner
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 ponder
RUN corepack enable && corepack prepare pnpm@latest --activate
RUN chown -R ponder:nodejs /app

# Copy the installed node_modules (includes hoisted deps + workspace links)
COPY --from=builder --chown=ponder:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=ponder:nodejs /app/package.json ./package.json
COPY --from=builder --chown=ponder:nodejs /app/pnpm-workspace.yaml ./pnpm-workspace.yaml

# Copy the config workspace package (runtime dependency)
COPY --from=builder --chown=ponder:nodejs /app/packages/config ./packages/config

# Copy the indexer workspace package
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/node_modules ./apps/indexer/node_modules
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/package.json ./apps/indexer/package.json
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/ponder.config.ts ./apps/indexer/ponder.config.ts
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/ponder.schema.ts ./apps/indexer/ponder.schema.ts
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/ponder-env.d.ts ./apps/indexer/ponder-env.d.ts
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/src ./apps/indexer/src
COPY --from=builder --chown=ponder:nodejs /app/apps/indexer/scripts ./apps/indexer/scripts

RUN chmod +x ./apps/indexer/scripts/start.sh

USER ponder
WORKDIR /app/apps/indexer

EXPOSE 42069

CMD ["./scripts/start.sh"]