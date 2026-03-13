FROM node:22-alpine AS base

# 1. Install dependencies
FROM base AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && corepack prepare pnpm@latest --activate
RUN pnpm i --frozen-lockfile

# 2. Setup source code
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN corepack enable && corepack prepare pnpm@latest --activate
# Run codegen here to generate ponder-env.d.ts and others
RUN pnpm run codegen

# 3. Production runner
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 ponder

# --- FIX START ---
# Ensure the non-root user has ownership of the working directory
# keeping the structure simple by chowning the whole /app directory
# This allows Ponder to write .ponder/ cache or update files if needed
RUN chown -R ponder:nodejs /app
# --- FIX END ---

# Copy artifacts
COPY --from=builder --chown=ponder:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=ponder:nodejs /app/package.json ./package.json

# Copy source files (Required for ponder start)
COPY --from=builder --chown=ponder:nodejs /app/ponder.config.ts ./ponder.config.ts
COPY --from=builder --chown=ponder:nodejs /app/ponder.schema.ts ./ponder.schema.ts
COPY --from=builder --chown=ponder:nodejs /app/src ./src
COPY --from=builder --chown=ponder:nodejs /app/abis ./abis
# Also copy the generated type definition from codegen step
COPY --from=builder --chown=ponder:nodejs /app/ponder-env.d.ts ./ponder-env.d.ts

USER ponder

EXPOSE 42069

# Use npm run start which executes "ponder start"
CMD ["npm", "run", "start"]