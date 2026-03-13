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

To test with a local Anvil chain, update `ponder.config.ts` to point to your local RPC URL (usually `http://127.0.0.1:8545`) and ensure the contract addresses match your deployment.

## Prerequisites

- **Node.js**: v18+ (tested with v20).
- **pnpm**: v8 or newer.
- **PostgreSQL**: Required for production; Ponder uses Pglite (in-memory Postgres) for development by default, or you can configure `DATABASE_URL`.
