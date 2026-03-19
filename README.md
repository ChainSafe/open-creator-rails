## Open Creator Rails

Open Creator Rails is a minimal, verifiable on-chain primitive for managing access to game resources using expiration-based entitlements. The system maps `[subject, resourceId] → expirationTime` to enable creator monetization use cases like an "on-chain Patreon."

The runtime plans to include a subscription engine, core registry and issuer contracts, Unity SDK integration (with a Demo), x402 settlement adapter, payment rails extensibility framework, high-performance verifier and indexer, abstract wallet linkage, and a creator's console (MCP based).

See the initial [MVP Architecture and Design](docs/mvp-design-and-architecture.md) document for a detailed flow diagrams and architecture specifications. This is for the MVP (Minimum Viable Product) or core on-chan implementation and doesn't reflect the intended final product.

---

## Installation

### Prerequisites

- [Node.js](https://nodejs.org/) (v22+)
- [pnpm](https://pnpm.io/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- [jq](https://jqlang.org/) (optional) — for script usage (e.g. `get_address` in `./scripts/utils.sh` reads `packages/config/src/deployments/registries_<chain_id>.json` via jq)

### Setup

1. **Clone the repository and install dependencies**

   ```bash
   git clone <repo-url>
   cd open-creator-rails
   pnpm install
   ```

2. **Environment variables**

   Create a `.env` file in the project root. Scripts load it automatically when present.

   | Variable      | Description |
   |---------------|-------------|
   | `PRIVATE_KEY` | Private key used to deploy and send transactions (e.g. `0x...`). |
   | `RPC_URL`     | JSON-RPC URL of the network (e.g. `https://sepolia.infura.io/v3/YOUR_KEY` or `http://127.0.0.1:8545` for local). |

3. **Build Contracts & Sync ABIs**

   ```bash
   pnpm setup
   ```

   Or individually:

   ```bash
   pnpm contract:build
   pnpm -C packages/config sync
   ```

4. **Run Indexer (Local)**

   ```bash
   pnpm indexer:dev
   ```

5. **Run tests**

   ```bash
   pnpm test
   ```

---

## Usage

### Deploying Registries

Deploy an AssetRegistry with the specified registry fee share:

```bash
./scripts/deployRegistry.sh <registry_fee_share>
```

| Input | Description |
|-------|--------------|
| `registry_fee_share` | Percentage of subscription payments allocated to the registry. Must be 0–100. The creator receives the remainder (`100 - registry_fee_share`). |

Example:

```bash
./scripts/deployRegistry.sh 20
```

Deployments are recorded in `packages/config/src/deployments/registries_<chain_id>.json`, where `chain_id` is the chain ID of the network from `RPC_URL` (e.g. `registries_11155111.json` for Sepolia, `registries_84532.json` for Base Sepolia). The file is an array of registry objects with `address`, `registryFeeShare`, `owner`, and `assets`.

### Creating Assets

Create an asset in a registry (registry owner only):

```bash
./scripts/createAsset.sh <registry_index> <asset_id> <subscription_price> <token_address> <owner>
```

| Input | Description |
|-------|--------------|
| `registry_index` | Zero-based index of the registry in `packages/config/src/deployments/registries_<chain_id>.json` (e.g. `0` for the first registry). |
| `asset_id` | Human-readable identifier for the asset. The script hashes it with keccak256 to get the bytes32 used on-chain. |
| `subscription_price` | Price per subscription unit per second in the token's smallest unit. |
| `token_address` | Address of the ERC20 contract used for subscription payments. Must implement ERC-2612 (Permits), as subscription payments use gasless permit approvals. |
| `owner` | Creator/owner address of the asset; receives the creator share of subscription fees. |

Example:

```bash
./scripts/createAsset.sh 0 "default_asset_id" 4 0x1234... 0xabcd...
```

The token address must implement ERC-2612 / IERC20Permit, as subscription payments use gasless permit approvals.

New assets are appended to the `assets` array of the corresponding registry in `packages/config/src/deployments/registries_<chain_id>.json`. Each asset entry includes `address`, `assetId`, `assetIdHash`, `subscriptionPrice`, `tokenAddress`, and `owner`.

### Subscribe

Subscribe to an asset using ERC-2612 permit (gasless approval). The payer signs the permit and pays with tokens; the subscription is associated with a **subscriber** identity (a `bytes32` hash, e.g. `keccak256(abi.encodePacked(subscriber_id))`). The payer and the subscriber can be the same or different (e.g. "pay for someone else"). The **payer** is the address entitled to refunds if the subscription is later cancelled or revoked (unearned time is refunded to the payer).

```bash
./scripts/subscribe.sh <registry_index> <asset_id> <subscriber_id> <value> <payer_private_key>
```

| Input | Description |
|-------|--------------|
| `registry_index` | Zero-based index of the registry in `packages/config/src/deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). The script hashes it with keccak256 for the on-chain call. |
| `subscriber_id` | Human-readable subscriber identity (e.g. user id, wallet-derived id). The script hashes it with keccak256 to get the `bytes32` subscriber used on-chain. Access and subscription queries use this identity. |
| `value` | Payment amount in the token's smallest unit. Must be a multiple of the asset's subscription price; excess is rounded down. |
| `payer_private_key` | Private key of the token owner. Used only to sign the ERC-2612 permit (this address’s tokens are spent). The subscribe transaction is sent using `PRIVATE_KEY` from `.env`. |

Example:

```bash
./scripts/subscribe.sh 0 "default_asset_id" "user_123" 10368000 0x1b97...
```

### Set Subscription Price

Update the subscription price for an asset (asset owner only):

```bash
./scripts/setSubscriptionPrice.sh <registry_index> <asset_id> <new_subscription_price> <asset_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `registry_index` | Zero-based index of the registry in `packages/config/src/deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `new_subscription_price` | New price per subscription unit (e.g. per second) in the token's smallest unit. |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |

Example:

```bash
./scripts/setSubscriptionPrice.sh 0 "default_asset_id" 8 0x1b97...
```

The script updates the `subscriptionPrice` for the asset in `packages/config/src/deployments/registries_<chain_id>.json`.

### Transfer Asset Ownership

Transfer ownership of an asset to a new address (asset owner only). The asset owner is the address that can claim the creator fee share of subscription payments.

```bash
./scripts/transferAssetOwnership.sh <registry_index> <asset_id> <asset_owner_private_key> <new_owner>
```

| Input | Description |
|-------|--------------|
| `registry_index` | Zero-based index of the registry in `packages/config/src/deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `asset_owner_private_key` | Private key of the current asset owner. Used to send the transaction. |
| `new_owner` | Address of the new owner; can claim creator share of subscription fees going forward. |

Example:

```bash
./scripts/transferAssetOwnership.sh 0 "default_asset_id" 0x1b97... 0xabcd...
```

The script updates the `owner` for the asset in `packages/config/src/deployments/registries_<chain_id>.json`.

---

> ### Test Tokens
>
> Test tokens supporting ERC-2612 (permit) are already deployed for testing subscriptions. Addresses are listed in `packages/config/src/deployments/token_addresses.json` keyed by chain ID (e.g. Sepolia `11155111`, Base Sepolia `84532`). Anyone can mint any amount for testing.
>
> **Deploy a test token** (records the address in `packages/config/src/deployments/token_addresses.json` for the current chain):
>
> ```bash
> ./scripts/deployTestToken.sh
> ```
>
> **Mint test tokens** to an address (uses the token in `packages/config/src/deployments/token_addresses.json` for the current chain):
>
> ```bash
> ./scripts/mintTestToken.sh <to> <amount>
> ```
>
> | Input | Description |
> |-------|--------------|
> | `to` | Recipient address. |
> | `amount` | Amount to mint in the token's smallest unit. |

---

## RPC API Reference

All external functions for the registry and asset contracts, for use with JSON-RPC (e.g. `eth_call` for reads, `eth_sendTransaction` for writes).

### IAssetRegistry

---

**createAsset** : Deploys a new Asset contract and registers it under the given id.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 _assetId` : Unique identifier for the asset.
  - `uint256 _subscriptionPrice` : Price per subscription unit for the asset.
  - `address _tokenAddress` : ERC20 (with permit) used for subscription payments.
  - `address _owner` : Creator/owner of the new asset.
- Returns:
  - `address` : Address of the newly deployed Asset contract.


---

**viewAsset** : Checks whether an asset is registered for the given id.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier to check.
- Returns:
  - `bool` : True if an asset exists for the id.


---

**getAsset** : Returns the contract address of the asset for the given id. Throws if not found.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier to look up.
- Returns:
  - `address` : Address of the Asset contract.


---

**isSubscriptionActive** : Checks whether a subscriber has an active subscription for the given asset.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity (e.g. keccak256 of a unique id).
- Returns:
  - `bool` : True if the subscriber's subscription is active.


---

**getSubscription** : Returns the subscription expiry timestamp for the given subscriber for the given asset.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity.
- Returns:
  - `uint256` : Expiry timestamp in seconds; 0 if no subscription.


---

**getSubscriptionPrice** : Returns the subscription price for the given asset and duration.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `uint256 _duration` : Subscription duration in seconds.
- Returns:
  - `uint256` : Total price for the duration.


---

**subscribe** : Subscribes a subscriber to the asset using ERC-2612 permit; forwards to the asset contract. The permit is signed by the payer; the subscription is attributed to `_subscriber` (payer and subscriber can differ). The payer is the refund beneficiary on cancel/revoke.
- Type: write
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity (who gets the access).
  - `address _payer` : Payer; signs the permit and pays. Receives refunds on cancel/revoke. Can be the same or different from the subscriber (e.g. gifting).
  - `address _spender` : Must be the asset contract address for the permit.
  - `uint256 _value` : Permit allowance / payment amount.
  - `uint256 _deadline` : Permit signature expiry.
  - `uint8 _v` : Signature v.
  - `bytes32 _r` : Signature r.
  - `bytes32 _s` : Signature s.
- Returns:
  - `uint256` : Subscription expiry in Unix timestamp.


---

**getCreatorFeeShare** : Returns the creator fee share percentage. Computed as `100 - registryFeeShare`.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `uint256` : Creator fee share (0–100).


---

**getRegistryFeeShare** : Returns the registry fee share percentage.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `uint256` : Registry fee share (0–100).


---

**getFeeShares** : Returns the creator and registry fee shares. They always sum to 100.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `uint256 creatorFeeShare` : Creator fee share (0–100).
  - `uint256 registryFeeShare` : Registry fee share (0–100).


---

**updateRegistryFeeShare** : Updates the registry's share of subscription fees. The creator share is automatically `100 - _registryFeeShare`.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `uint256 _registryFeeShare` : New registry fee share percentage (0–100). Reverts if out of bounds.
- Returns: void


---

**getCreatorFee** : Returns the creator fee for a given payment value.
- Type: read
- Permission: none
- Parameters:
  - `uint256 _value` : Total payment value.
- Returns:
  - `uint256` : Creator fee amount.


---

**getRegistryFee** : Returns the registry fee for a given payment value.
- Type: read
- Permission: none
- Parameters:
  - `uint256 _value` : Total payment value.
- Returns:
  - `uint256` : Registry fee amount.


---

**getFees** : Returns the creator and registry fees for a given payment value.
- Type: read
- Permission: none
- Parameters:
  - `uint256 _value` : Total payment value.
- Returns:
  - `uint256 creatorFee` : Creator portion.
  - `uint256 registryFee` : Registry portion.


---

**claimRegistryFee** (single) : Claims the registry fee for a single subscriber.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity whose registry fee to claim.
- Returns:
  - `uint256` : Amount of registry fee claimed.


---

**claimRegistryFee** (batch) : Claims the registry fee for multiple subscribers in a single call. Subscribers with no accrued fee are silently skipped.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32[] _subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256` : Total amount of registry fee claimed across all subscribers.


---

**cancelSubscription** : Cancels a subscriber's subscription via the registry. Callable only by the registry owner. Unearned subscription value is refunded to the original payer.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity whose subscription to cancel.
- Returns: void


---

**emitRegistryFeeClaimed** : Emits a `RegistryFeeClaimed` event on behalf of an Asset contract. Callable only by the registered Asset contract for the given `_assetId` (used internally during batch fee claims).
- Type: write
- Permission: `onlyAsset`
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Subscriber identity for which the fee was claimed.
  - `uint256 _registryFee` : Amount of registry fee claimed.
- Returns: void


---

**getOwner** : Returns the owner of the registry (e.g. for receiving registry fees).
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `address` : Registry owner address.


---

### IAsset

---

**getAssetId** : Returns the unique identifier for this asset.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `bytes32` : Asset id.


---

**getRegistryAddress** : Returns the address of the registry that deployed this asset.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `address` : Registry address.


---

**getTokenAddress** : Returns the address of the token contract used for subscription payments.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `address` : Token contract address (ERC20 with permit).


---

**getSubscriptionPrice** : Returns the total price for a subscription of the given duration.
- Type: read
- Permission: none
- Parameters:
  - `uint256 duration` : Length of the subscription in seconds.
- Returns:
  - `uint256` : Total price for the duration.


---

**setSubscriptionPrice** : Sets the subscription price for the asset.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `uint256 newSubscriptionPrice` : New subscription price.
- Returns: void


---

**getSubscription** : Returns a subscriber's subscription expiry timestamp.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to query.
- Returns:
  - `uint256` : Expiry timestamp in seconds; 0 if no subscription.


---

**isSubscriptionActive** : Checks whether a subscriber has an active subscription (expiry > block.timestamp).
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to check.
- Returns:
  - `bool` : True if the subscriber's subscription is active.


---

**subscribe** : Subscribes a subscriber using ERC-2612 permit: payer signs permit, then payment is pulled and subscription is attributed to the given subscriber. Payer and subscriber can differ (e.g. pay for someone else). The payer is the refund beneficiary on cancel/revoke.
- Type: write
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity (who gets the access).
  - `address payer` : Payer; signs the permit and pays. Receives refunds on cancel/revoke.
  - `address spender` : Must be this asset contract for the permit to be accepted.
  - `uint256 value` : Permit allowance / payment amount (will be rounded down to subscription price units).
  - `uint256 deadline` : Permit signature expiry.
  - `uint8 v` : Signature recovery id.
  - `bytes32 r` : Signature r.
  - `bytes32 s` : Signature s.
- Returns:
  - `uint256` : Subscription expiry in Unix timestamp.


---

**claimCreatorFee** (single) : Claims the creator fee for a single subscriber.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity whose creator fee to claim.
- Returns:
  - `uint256` : Amount of creator fee claimed.


---

**claimCreatorFee** (batch) : Claims the creator fee for multiple subscribers in a single call. Subscribers with no accrued fee or no subscription are silently skipped.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32[] subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256` : Total amount of creator fee claimed across all subscribers.


---

**claimRegistryFee** (single) : Claims the registry fee for a single subscriber. Callable only by the registry contract.
- Type: write
- Permission: `onlyRegistry`
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity whose registry fee to claim.
- Returns:
  - `uint256` : Amount of registry fee claimed.


---

**claimRegistryFee** (batch) : Claims the registry fee for multiple subscribers in a single call. Callable only by the registry contract. Subscribers with no accrued fee or no subscription are silently skipped.
- Type: write
- Permission: `onlyRegistry`
- Parameters:
  - `bytes32[] subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256` : Total amount of registry fee claimed across all subscribers.


---

**revokeSubscription** : Revokes a subscriber's subscription. The payer of each subscription is entitled to a refund of the unearned portion (tokens are returned to the payer address).
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 subscriber` : Subscriber whose subscription to revoke.
- Returns: void


---

**cancelSubscription** : Cancels a subscriber's subscription. Callable only by the registry contract. The payer of each subscription is entitled to a refund of the unearned portion (tokens are returned to the payer address).
- Type: write
- Permission: `onlyRegistry`
- Parameters:
  - `bytes32 subscriber` : Subscriber whose subscription to cancel.
- Returns: void

---

## Event Schema

All events emitted by the registry and asset contracts. Use for indexing, logging, or listening via `eth_subscribe` (logs).

### AssetRegistry

---

**AssetCreated** : Emitted when a new Asset contract is deployed and registered.
- Contract: `AssetRegistry`
- Parameters:
  - `bytes32 indexed assetId` : Unique identifier for the asset.
  - `address indexed asset` : Address of the newly deployed Asset contract.
  - `uint256 subscriptionPrice` : Price per subscription unit for the asset.
  - `address tokenAddress` : ERC20 (with permit) used for subscription payments.
  - `address indexed owner` : Creator/owner of the new asset.


---

**RegistryFeeShareUpdated** : Emitted when the registry fee share is updated.
- Contract: `AssetRegistry`
- Parameters:
  - `uint256 newRegistryFeeShare` : New registry fee share.


---

**RegistryFeeClaimed** : Emitted when the registry fee for a subscriber is claimed.
- Contract: `AssetRegistry`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose registry fee was claimed.
  - `uint256 amount` : Amount of registry fee claimed.


---

### Asset

---

**SubscriptionAdded** : Emitted when a new subscription record is created for a subscriber (new nonce). This happens on the first subscription and whenever the payer, subscription price, or registry fee share differs from the active subscription. For renewals that extend an existing active subscription under the same terms, see `SubscriptionExtended`.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber identity (hash).
  - `uint256 indexed startTime` : Subscription start time (Unix timestamp).
  - `uint256 indexed endTime` : Subscription expiry time (Unix timestamp).
  - `uint256 nonce` : Subscription nonce (increments each time a new record is created for the subscriber).
  - `address payer` : Payer for this subscription (refund beneficiary on cancel/revoke).


---

**SubscriptionExtended** : Emitted when an active subscription is extended under the same terms (same payer, subscription price, and registry fee share). The existing subscription record's `endTime` is updated in place; no new nonce is created.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber identity (hash).
  - `uint256 indexed endTime` : Updated subscription expiry time (Unix timestamp).


---

**CreatorFeeClaimed** : Emitted when the creator fee for a subscriber is claimed.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose creator fee was claimed.
  - `uint256 amount` : Amount of creator fee claimed.


---

**SubscriptionPriceUpdated** : Emitted when the subscription price is updated.
- Contract: `Asset`
- Parameters:
  - `uint256 newSubscriptionPrice` : New subscription price per unit.


---

**SubscriptionRevoked** : Emitted when a subscriber's subscription is revoked by the asset owner.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose subscription was revoked.


---

**SubscriptionCancelled** : Emitted when a subscriber's subscription is cancelled (by the payer or asset owner).
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose subscription was cancelled.