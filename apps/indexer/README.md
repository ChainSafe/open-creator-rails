# ocr-indexer-ponder

A [Ponder](https://ponder.sh) indexer for the OCR (Open Creator Rails) protocol.

This indexer tracks:

- **AssetRegistry**: deployment and configuration of `Asset` contracts.
- **Asset**: subscription-gated assets and their subscribers.

It exposes convenient entities to answer questions like:

- Which assets exist and who owns them?
- Which assets is a user subscribed to?
- Which users are subscribed to a given asset?

## Data model

The entities are defined in `ponder.schema.ts` and mirror the original Envio implementation.

- **`AssetEntity`**  
  One row per `Asset` contract.
  - `id`: asset contract address (lowercased).
  - `assetId`: bytes32 id in the registry.
  - `registryAddress`: address of the `AssetRegistry` that created it.
  - `owner`: current `Asset` owner (creator or transferee), always lowercased.

- **`Subscription`**  
  One row per `(asset, user)` pair, representing their **current contiguous active state**.
  - `id`: `${assetAddress}_${user}` (both lowercased).
  - `assetId`: foreign key to `AssetEntity.id`.
  - `user`: subscriber address (lowercased).
  - `startTime`: The initial start time of their unbroken subscription block (BigInt).
  - `endTime`: The final expiry timestamp of their subscription block (BigInt).
  - `nonce`: The latest subscription iteration counter for that user.
  - `isActive`: whether the subscription is currently active (forced false if revoked).

  > **Note on Subscription Time Tracking**: When a user tops up an actively running subscription, the smart contract seamlessly extends their access by setting the new event's `startTime` equal to the old `endTime`. The indexer handles this cleanly: it identifies if `existingSub.endTime === event.args.startTime` and conditionally stitches the time blocks together. This way, the mutable `Subscription` table always elegantly presents a user's *continuous* timeline of access (maintaining their ancient `startTime`), whereas the historical `Asset_SubscriptionAdded` log table tracks the isolated iterations individually via nonces.

- **Event entities**  
  These mirror contract events for history and debugging:
  - `AssetRegistry_AssetCreated`
  - `AssetRegistry_OwnershipTransferred`
  - `AssetRegistry_CreatorFeeShareUpdated`
  - `AssetRegistry_RegistryFeeShareUpdated`
  - `Asset_SubscriptionAdded`
  - `Asset_SubscriptionPriceUpdated`
  - `Asset_SubscriptionRevoked`
  - `Asset_OwnershipTransferred`

## GraphQL API

All GraphQL types and fields are automatically generated from `ponder.schema.ts`.
After running `pnpm dev`, open the Playground at `http://localhost:42069`.

> **⚠️ Addresses are lowercased.** All address fields (`id`, `owner`, `registryAddress`, `payer`, `asset`, etc.) are stored in **lowercase**. If you query with a checksummed (mixed-case) address you will get no results. Lowercase the address on the client before querying:
>
> ```ts
> const address = walletAddress.toLowerCase();
> ```

## Running the indexer

### Development

```bash
pnpm dev
```

This will:
- Start the Ponder development server.
- Automatically reload on file changes.
- Expose GraphQL at `http://localhost:42069`.

This runs the optimized production build.

### Helper Commands

- **`pnpm codegen`**: Regenerates the Ponder types from the schema and config.
- **`pnpm typecheck`**: Runs the TypeScript compiler to check for type errors.

## Configuration

The indexer is configured in `ponder.config.ts`. This file defines the networks, contracts, and ABI locations.

To change the network or contract addresses, edit `ponder.config.ts`.

## Local Development (Anvil)

The indexer uses the Ponder convention of `PONDER_RPC_URL_<chainId>` environment variables to decide which chains to index. To run against a local Anvil node, create an `.env.local` file inside the indexer directory:

```bash
# apps/indexer/.env.local

# Anvil's default JSON-RPC endpoint (chain ID 31337)
PONDER_RPC_URL_31337=http://127.0.0.1:8545
```

> Ponder automatically loads `.env.local` in dev mode — no extra configuration needed.

### Quick start

From the monorepo root:

```bash
pnpm setup        # first time only — build contracts + sync ABIs
pnpm dev:local    # starts Anvil, seeds contracts, and launches the indexer
```

`dev:local` starts Anvil, runs `seed-local.sh` (deploys registry, token, and sample assets), and launches the indexer concurrently. The RPC URL is passed inline so `.env.local` is not required for this path.

The GraphQL playground will be available at `http://localhost:42069`.

### Docker

The root `package.json` also provides Docker-based scripts that run the indexer with Postgres (useful for testing production-like setups):

```bash
pnpm indexer:docker        # build and start the stack (Postgres + worker + API)
pnpm indexer:docker:down   # stop all containers
pnpm indexer:docker:reset  # stop and remove volumes (full reset)
```

> The Docker Compose file lives at `apps/indexer/docker-compose.yaml`. It requires `PONDER_RPC_URL_11155111` to be set in your shell or in `apps/indexer/.env`.

### Environment variable reference

| Variable | Chain | Description |
|---|---|---|
| `PONDER_RPC_URL_31337` | Local (Anvil) | Anvil RPC URL. Set this to enable local chain indexing. |
| `PONDER_RPC_URL_11155111` | Sepolia | Sepolia RPC URL. Set this to enable Sepolia indexing. |
| `DATABASE_URL` | — | Postgres connection string. Only needed for production; dev mode uses PGlite (in-memory) by default. |

> **Tip:** You can set both `PONDER_RPC_URL_31337` and `PONDER_RPC_URL_11155111` at the same time to index multiple chains simultaneously.

## Prerequisites

- **Node.js**: v18+ (tested with v20).
- **pnpm**: v8 or newer.
- **PostgreSQL**: Required for production; Ponder uses Pglite (in-memory Postgres) for development by default, or you can configure `DATABASE_URL`.
