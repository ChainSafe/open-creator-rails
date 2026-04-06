# Indexer API

The indexer API exposes indexed blockchain data from the Open Creator Rails contracts via **GraphQL** and **SQL** endpoints. It is powered by [Ponder](https://ponder.sh) and runs as a dedicated read-only node decoupled from the indexing worker.

## Endpoints

| Network | Base URL |
|---|---|
| Sepolia (testnet) | `https://indexer-api-production-c33d.up.railway.app` |

| Endpoint | Description |
|---|---|
| `GET /` | GraphQL playground (browser UI) |
| `POST /graphql` | GraphQL API |
| `GET /sql/*` | Direct SQL queries via Ponder's SQL endpoint |
| `GET /ready` | Health check — returns `200` when API is live |

---

## GraphQL API

### Explorer

Open the GraphQL playground in your browser:

```
https://indexer-api-production-c33d.up.railway.app/
```

### Making requests

```bash
curl -X POST https://indexer-api-production-c33d.up.railway.app/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ assetEntitys { items { id address owner } } }"}'
```

---

### Available query fields

Ponder generates both a singular (fetch by ID) and a plural (list) field for each table.

| Singular | Plural (list) | Description |
|---|---|---|
| `assetEntity` | `assetEntitys` | Asset contract state |
| `subscription` | `subscriptions` | Subscription state per asset–subscriber |
| `assetRegistry_AssetCreated` | `assetRegistry_AssetCreateds` | Asset creation events |
| `assetRegistry_OwnershipTransferred` | `assetRegistry_OwnershipTransferreds` | Registry ownership transfer events |
| `assetRegistry_RegistryFeeShareUpdated` | `assetRegistry_RegistryFeeShareUpdateds` | Registry fee share update events |
| `assetRegistry_RegistryFeeClaimedBatch` | `assetRegistry_RegistryFeeClaimedBatchs` | Registry fee claim batch events |
| `asset_SubscriptionAdded` | `asset_SubscriptionAddeds` | New subscription events |
| `asset_SubscriptionExtended` | `asset_SubscriptionExtendeds` | Subscription extension events |
| `asset_SubscriptionRevoked` | `asset_SubscriptionRevokeds` | Subscription revocation events |
| `asset_SubscriptionCancelled` | `asset_SubscriptionCancelleds` | Subscription cancellation events |
| `asset_SubscriptionPriceUpdated` | `asset_SubscriptionPriceUpdateds` | Subscription price update events |
| `asset_CreatorFeeClaimed` | `asset_CreatorFeeClaimeds` | Creator fee claim events |
| `asset_OwnershipTransferred` | `asset_OwnershipTransferreds` | Asset ownership transfer events |
| `_meta` | — | Indexer metadata (last indexed block, etc.) |

---

## Data Model

### Entities (mutable state)

#### `assetEntity`

Current state of each asset contract created through the registry.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Primary key — `{chainId}_{assetAddress}` |
| `chainId` | `Int` | Chain ID (e.g. `11155111` for Sepolia) |
| `assetId` | `String` | Registry-assigned asset ID |
| `address` | `String` | Asset contract address |
| `registryAddress` | `String` | AssetRegistry contract that created it |
| `owner` | `String` | Current owner address |

**Example query — fetch all assets by owner:**
```graphql
{
  assetEntitys(where: { owner: "0xYourAddress" }) {
    items {
      id
      assetId
      address
      chainId
    }
  }
}
```

---

#### `subscription`

Current subscription state per asset–subscriber pair. One row per unique `(asset, subscriber)` — not per nonce. Preserves the original `startTime` across mid-subscription term changes.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Primary key — `{assetEntity.id}_{subscriber}` |
| `chainId` | `Int` | Chain ID |
| `assetId` | `String` | Links to `assetEntity.id` |
| `subscriber` | `String` | `bytes32` subscriber identity hash |
| `payer` | `String` | Address that paid (latest nonce) |
| `startTime` | `BigInt` | Unix timestamp — original start of unbroken subscription |
| `endTime` | `BigInt` | Unix timestamp — current expiry |
| `nonce` | `BigInt` | Latest on-chain nonce (increments when terms change) |
| `isActive` | `Boolean` | `false` when revoked or cancelled |

**Example query — check if a subscriber has an active subscription:**
```graphql
{
  subscriptions(where: { subscriber: "0x...", isActive: true }) {
    items {
      assetId
      startTime
      endTime
      payer
    }
  }
}
```

**Example query — all active subscriptions for an asset:**
```graphql
{
  subscriptions(where: { assetId: "{chainId}_{assetAddress}", isActive: true }) {
    items {
      subscriber
      payer
      startTime
      endTime
    }
  }
}
```

---

### Event history (immutable)

All event tables follow the same ID format: `{chainId}-{txHash}-{logIndex}`.

#### `assetRegistry_AssetCreated`

Emitted when a new Asset contract is deployed through the registry.

| Field | Type |
|---|---|
| `assetId` | `String` |
| `asset` | `String` — asset contract address |
| `subscriptionPrice` | `BigInt` |
| `tokenAddress` | `String` — payment token |
| `owner` | `String` |
| `registryAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `asset_SubscriptionAdded`

Emitted when a new subscription is purchased.

| Field | Type |
|---|---|
| `subscriber` | `String` |
| `payer` | `String` |
| `startTime` | `BigInt` |
| `endTime` | `BigInt` |
| `nonce` | `BigInt` |
| `assetAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `asset_SubscriptionExtended`

Emitted when an existing subscription's end time is extended.

| Field | Type |
|---|---|
| `subscriber` | `String` |
| `endTime` | `BigInt` — new expiry |
| `assetAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `asset_SubscriptionRevoked` / `asset_SubscriptionCancelled`

Emitted when a subscription ends early (revoked by owner, or cancelled by subscriber).

| Field | Type |
|---|---|
| `subscriber` | `String` |
| `assetAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `asset_SubscriptionPriceUpdated`

| Field | Type |
|---|---|
| `newSubscriptionPrice` | `BigInt` |
| `assetAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `asset_CreatorFeeClaimed`

| Field | Type |
|---|---|
| `subscriber` | `String` |
| `amount` | `BigInt` |
| `assetAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `assetRegistry_RegistryFeeClaimedBatch`

| Field | Type |
|---|---|
| `assetId` | `String` |
| `totalAmount` | `BigInt` |
| `registryAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

#### `assetRegistry_RegistryFeeShareUpdated`

| Field | Type |
|---|---|
| `newRegistryFeeShare` | `BigInt` |
| `registryAddress` | `String` |
| `blockNumber` | `BigInt` |
| `blockTimestamp` | `BigInt` |

---

## SQL endpoint

The `/sql` endpoint allows direct SQL queries against the indexed data. Useful for analytics and complex joins.

```bash
curl "https://indexer-api-production-c33d.up.railway.app/sql/SELECT%20*%20FROM%20ocr_indexer.subscription%20WHERE%20is_active%20%3D%20true%20LIMIT%2010"
```

Table names follow the pattern `ocr_indexer.<table_name>` where table names are the snake_case equivalents of the schema definitions (e.g. `asset_entity`, `subscription`, `asset_subscription_added`).

---

## Pagination

All GraphQL list queries support cursor-based pagination:

```graphql
{
  subscriptions(limit: 20, after: "cursor_from_previous_response") {
    items { ... }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

---

## Notes

- All `BigInt` values are returned as strings to avoid JavaScript integer overflow
- All addresses are lowercase hex strings
- `blockTimestamp` is a Unix timestamp in seconds
- The API serves from a stable views schema — it remains available during indexer redeploys (zero downtime)
- Ponder pluralises list fields by appending `s` to the table name (e.g. `assetEntitys`, `asset_SubscriptionAddeds`)
