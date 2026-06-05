## Open Creator Rails

Open Creator Rails is a minimal, verifiable on-chain primitive for managing access to game resources using expiration-based entitlements. The system maps `[subject, resourceId] → expirationTime` to enable creator monetization use cases like an "on-chain Patreon."

## Related Projects

| Repository | Description |
|------------|-------------|
| [open-creator-rails.indexer](https://github.com/ChainSafe/open-creator-rails.indexer) | Indexer |
| [open-creator-rails.sdk](https://github.com/ChainSafe/open-creator-rails.sdk) | TypeScript SDK |
| [open-creator-rails.unity](https://github.com/ChainSafe/open-creator-rails.unity) | Unity Game Engine SDK |
| [open-creator-rails.demo](https://github.com/ChainSafe/open-creator-rails.demo) | Web Demo |

---

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- [jq](https://jqlang.org/) (optional) — for script usage (e.g. `get_address` in `script/utils.sh` reads `registries_<chain_id>.json` via jq)

### Setup

1. **Clone the repository and install dependencies**

   ```bash
   git clone <repo-url>
   cd open-creator-rails
   forge install
   ```

2. **Environment variables**

   Create a `.env` or a `.env.local` file in the project root with the following variables:

   | Variable   | Description |
   |------------|-------------|
   | `MNEMONIC` | BIP-39 mnemonic phrase used to derive all wallets via an index. |
   | `RPC_URL`  | JSON-RPC URL of the network (e.g. `https://sepolia.infura.io/v3/YOUR_KEY` for Sepolia, or `http://127.0.0.1:8545` for local Anvil). |
   | `COOLDOWN` | (**Optional**) Seconds to pause between RPC-heavy script steps (see `cooldown` in `scripts/utils.sh`). Defaults to `0` if unset. On testnet/mainnet, set a positive value, preferably equal to average block time (e.g. `export COOLDOWN=12`), to reduce RPC rate-limit errors. |

   **For testnet / mainnet** — create `.env`:

   ```bash
   export MNEMONIC='your twelve word mnemonic phrase here ...'
   export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
   ```

   **For local development** — create `.env.local` instead:

   ```bash
   export MNEMONIC='test test test test test test test test test test test junk'
   export RPC_URL=http://127.0.0.1:8545
   ```

   > **Note:** All scripts optionally accept an environment file (`.env` or `.env.local`) as their first argument (e.g. `./scripts/subscribe.sh .env.local ...`). If `.env.local` is passed, Anvil is automatically started before the script runs. Alternatively, source the env file manually in your shell before running any script: `source .env` or `source .env.local`.

3. **Build**

   ```bash
   forge build
   ```

4. **Run tests**

   ```bash
   forge test
   ```

---

## Usage

### Deploying Registries

Deploy an AssetRegistry with the specified registry fee share:

```bash
./scripts/deployRegistry.sh [env_file] <registry_fee_share> <registry_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_fee_share` | Percentage of subscription payments allocated to the registry. Must be 0–100. The creator receives the remainder (`100 - registry_fee_share`). |
| `registry_owner_private_key` | Private key of the registry owner; used to deploy the contract and send transactions. |

Example:

```bash
./scripts/deployRegistry.sh .env.local 20 0x1b97...
```

Deployments are recorded in `deployments/registries_<chain_id>.json`, where `chain_id` is the chain ID of the network from `RPC_URL` (e.g. `registries_11155111.json` for Sepolia, `registries_84532.json` for Base Sepolia). The file is an array of registry objects with `address`, `registryFeeShare`, `owner`, and `assets`.

### Creating Assets

Create an asset in a registry (registry owner only):

```bash
./scripts/createAsset.sh [env_file] <registry_index> <asset_id> <subscription_price> <subscription_duration> <token_address> <owner> <registry_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json` (e.g. `0` for the first registry). |
| `asset_id` | Human-readable identifier for the asset. The script hashes it with keccak256 to get the bytes32 used on-chain. |
| `subscription_price` | Price for one subscription period, in the token’s smallest unit. Must be a non-zero multiple of 100 to ensure integer precision when splitting fees between the registry and creator (`fee × registryFeeShare / 100`). Total payment for `n` periods is `n * subscription_price` (see `getSubscriptionPrice`). |
| `subscription_duration` | Length of one subscription period in seconds (non-zero). Subscriptions are always whole multiples of this duration. |
| `token_address` | Address of the ERC20 contract used for subscription payments. Must implement ERC-2612 (Permits), as subscription payments use gasless permit approvals. |
| `owner` | Creator/owner address of the asset; receives the creator share of subscription fees. |
| `registry_owner_private_key` | Private key of the registry owner; used to authorize the `createAsset` transaction. |

Example:

```bash
./scripts/createAsset.sh .env.local 0 "default_asset_id" 4 3600 0x1234... 0xabcd... 0x1b97...
```

The token address must implement ERC-2612 / IERC20Permit, as subscription payments use gasless permit approvals.

New assets are appended to the `assets` array of the corresponding registry in `deployments/registries_<chain_id>.json`. Each asset entry includes `address`, `assetId`, `assetIdHash`, `subscriptionPrice`, `subscriptionDuration`, `tokenAddress`, and `owner`.

### Subscribe

Subscribe to an asset using ERC-2612 permit (gasless approval). The payer signs the permit and pays with tokens; the subscription is associated with a **subscriber** identity (a `bytes32` hash). The subscriber hash is computed as `keccak256(abi.encode(subscriber_id, subscriber_address))`, so only that `subscriber_address` can cancel by signing an off-chain message and calling `cancelSubscription` in one step (no on-chain commit or timestamp binding). The payer and the subscriber can be the same or different (e.g. “pay for someone else”). The **payer** is the address entitled to refunds if the subscription is later cancelled or revoked (unearned time is refunded to the payer).

```bash
./scripts/subscribe.sh [env_file] <registry_index> <asset_id> <subscriber_id> <subscriber_address> <count> <payer_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). The script hashes it with keccak256 for the on-chain call. |
| `subscriber_id` | Human-readable subscriber identity (e.g. user id, wallet-derived id). Combined with `subscriber_address` to derive the on-chain `bytes32` subscriber hash: `keccak256(abi.encode(subscriber_id, subscriber_address))`. |
| `subscriber_address` | Address of the subscriber; the only address permitted to call `cancelSubscription` for this identity. |
| `count` | Number of full subscription periods to buy (must be at least 1). The script queries `getSubscriptionPrice(count)` on the asset for the ERC-2612 permit `value` and passes `count` to `subscribe`. |
| `payer_private_key` | Private key of the token owner. Used only to sign the ERC-2612 permit (this address’s tokens are spent). The subscribe transaction is sent from the deployer wallet (mnemonic index 0). |

Example:

```bash
./scripts/subscribe.sh .env.local 0 "default_asset_id" "user_123" 0xabcd... 12 0x1b97...
```

### Cancel Subscription

Cancel a subscription as the subscriber. Unearned whole subscription periods are refunded to the original payer; partial periods are non-refundable. The subscriber signs an EIP-191 message off-chain and the script submits `cancelSubscription` in a single transaction — no on-chain commit step is required. Reverts if the subscriber has been permanently revoked by the asset owner.

```bash
./scripts/cancelSubscription.sh [env_file] <registry_index> <asset_id> <subscriber_id> <subscriber_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `subscriber_id` | Human-readable subscriber identity string used when subscribing. Combined with `msg.sender` (the subscriber's address) to derive the on-chain subscriber hash. |
| `subscriber_private_key` | Private key of the subscriber. Used both to sign the cancellation payload off-chain and to send the transaction on-chain (`msg.sender` must match the subscriber address). |

Example:

```bash
./scripts/cancelSubscription.sh .env.local 0 "default_asset_id" "user_123" 0x1b97...
```

### Revoke Subscription

Revoke a subscriber's subscription as the asset owner. Unlike cancellation, revocation refunds all remaining time to each original payer, including partial-period dust, and **permanently bans** the subscriber from resubscribing or cancelling until the owner calls `unrevokeSubscription`. Reverts if the subscriber is already revoked.

```bash
./scripts/revokeSubscription.sh [env_file] <registry_index> <asset_id> <subscriber> <asset_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `subscriber` | Pre-computed `bytes32` subscriber hash: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Compute it with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |

Example:

```bash
SUBSCRIBER=$(cast keccak "$(cast abi-encode "f(string,address)" "user_123" 0xabcd...)")
./scripts/revokeSubscription.sh .env.local 0 "default_asset_id" $SUBSCRIBER 0x1b97...
```

### Unrevoke Subscription

Lift a permanent revocation for a subscriber as the asset owner, allowing them to resubscribe and cancel again. Reverts if the subscriber is not currently revoked.

```bash
./scripts/unrevokeSubscription.sh [env_file] <registry_index> <asset_id> <subscriber> <asset_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `subscriber` | Pre-computed `bytes32` subscriber hash: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Compute it with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |

Example:

```bash
SUBSCRIBER=$(cast keccak "$(cast abi-encode "f(string,address)" "user_123" 0xabcd...)")
./scripts/unrevokeSubscription.sh .env.local 0 "default_asset_id" $SUBSCRIBER 0x1b97...
```

### Claim Creator Fee

Claim the accrued creator fee for a single subscriber (asset owner only). Accrual covers all completed subscription periods since the last claim; any partial-period dust is also claimable once the subscription has fully ended. Logs the claimed amount formatted with the token's symbol and decimals.

```bash
./scripts/claimCreatorFee.sh [env_file] <registry_index> <asset_id> <subscriber> <asset_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `subscriber` | Pre-computed `bytes32` subscriber hash: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Compute it with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |

Example:

```bash
SUBSCRIBER=$(cast keccak "$(cast abi-encode "f(string,address)" "user_123" 0xabcd...)")
./scripts/claimCreatorFee.sh .env.local 0 "default_asset_id" $SUBSCRIBER 0x1b97...
```

### Claim Creator Fee (Batch)

Claim accrued creator fees for multiple subscribers in a single transaction (asset owner only). Subscribers with no accrued fee are silently skipped. Logs the total claimed amount formatted with the token's symbol and decimals.

```bash
./scripts/claimCreatorFeeBatch.sh [env_file] <registry_index> <asset_id> <asset_owner_private_key> <subscriber_1> [<subscriber_2> ...]
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |
| `subscriber_1`, `subscriber_2`, … | One or more pre-computed `bytes32` subscriber hashes: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Each can be computed with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |

Example:

```bash
SUB_0=$(cast keccak "$(cast abi-encode "f(string,address)" "user_0" 0xaaaa...)")
SUB_1=$(cast keccak "$(cast abi-encode "f(string,address)" "user_1" 0xbbbb...)")
./scripts/claimCreatorFeeBatch.sh .env.local 0 "default_asset_id" 0x1b97... $SUB_0 $SUB_1
```

### Claim Registry Fee

Claim the accrued registry fee for a single subscriber (registry owner only). Logs the claimed amount formatted with the token's symbol and decimals.

```bash
./scripts/claimRegistryFee.sh [env_file] <registry_index> <asset_id> <subscriber> <registry_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `subscriber` | Pre-computed `bytes32` subscriber hash: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Compute it with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |
| `registry_owner_private_key` | Private key of the registry owner. Used to send the transaction. |

Example:

```bash
SUBSCRIBER=$(cast keccak "$(cast abi-encode "f(string,address)" "user_123" 0xabcd...)")
./scripts/claimRegistryFee.sh .env.local 0 "default_asset_id" $SUBSCRIBER 0x1b97...
```

### Claim Registry Fee (Batch)

Claim accrued registry fees for multiple subscribers in a single transaction (registry owner only). Subscribers with no accrued fee are silently skipped. Logs the total claimed amount formatted with the token's symbol and decimals.

```bash
./scripts/claimRegistryFeeBatch.sh [env_file] <registry_index> <asset_id> <registry_owner_private_key> <subscriber_1> [<subscriber_2> ...]
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `registry_owner_private_key` | Private key of the registry owner. Used to send the transaction. |
| `subscriber_1`, `subscriber_2`, … | One or more pre-computed `bytes32` subscriber hashes: `keccak256(abi.encode(subscriber_id, subscriber_address))`. Each can be computed with: `$(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")`. |

Example:

```bash
SUB_0=$(cast keccak "$(cast abi-encode "f(string,address)" "user_0" 0xaaaa...)")
SUB_1=$(cast keccak "$(cast abi-encode "f(string,address)" "user_1" 0xbbbb...)")
./scripts/claimRegistryFeeBatch.sh .env.local 0 "default_asset_id" 0x1b97... $SUB_0 $SUB_1
```

### Set Subscription Price

Update the subscription price for an asset (asset owner only):

```bash
./scripts/setSubscriptionPrice.sh [env_file] <registry_index> <asset_id> <new_subscription_price> <asset_owner_private_key>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `new_subscription_price` | New price per subscription period in the token's smallest unit. Must be a non-zero multiple of 100; reverts with `InvalidSubscriptionPrice` otherwise. |
| `asset_owner_private_key` | Private key of the asset owner. Used to send the transaction. |

Example:

```bash
./scripts/setSubscriptionPrice.sh .env.local 0 "default_asset_id" 200 0x1b97...
```

The script updates the `subscriptionPrice` for the asset in `deployments/registries_<chain_id>.json`.

### Transfer Asset Ownership

Transfer ownership of an asset to a new address (asset owner only). The asset owner is the address that can claim the creator fee share of subscription payments.

```bash
./scripts/transferAssetOwnership.sh [env_file] <registry_index> <asset_id> <asset_owner_private_key> <new_owner>
```

| Input | Description |
|-------|--------------|
| `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
| `registry_index` | Zero-based index of the registry in `deployments/registries_<chain_id>.json`. |
| `asset_id` | Human-readable asset identifier (same string used when creating the asset). |
| `asset_owner_private_key` | Private key of the current asset owner. Used to send the transaction. |
| `new_owner` | Address of the new owner; can claim creator share of subscription fees going forward. |

Example:

```bash
./scripts/transferAssetOwnership.sh .env.local 0 "default_asset_id" 0x1b97... 0xabcd...
```

The script updates the `owner` for the asset in `deployments/registries_<chain_id>.json`.

### Local Development

Use `seed.sh` to spin up a fully seeded local environment in one command. Pass the env file as the first argument; if `.env.local` is passed the script auto-starts Anvil before running the full seed sequence.

```bash
./scripts/seed.sh <env_file>
```

**Setup steps:**

1. Create `.env.local` with the standard Anvil test mnemonic:

   ```bash
   export MNEMONIC='test test test test test test test test test test test junk'
   export RPC_URL=http://127.0.0.1:8545
   ```

2. Run the seed script from the project root, passing `.env.local` as the argument:

   ```bash
   ./scripts/seed.sh .env.local
   ```

   This will:
   - Start Anvil in the background
   - Deploy a test ERC-2612 token
   - Deploy an Asset Registry with a 30% Registry Fee Share (Asset Registry Owners derived from the mnemonic at index 0)
   - Create three Assets with different prices and durations (Asset Owners derived from the mnemonic at indices 1 - 3)
   - Mint Test Tokens to six subscriber wallets (Subscribers derived from the mnemonic at indices 4 - 9)
   - Subscribe each wallet to one or more Assets

   Anvil remains running after seeding completes (kept alive by the script).

   > **Note:** To seed mainnet/testnet set up `.env` instead of `.env.local`:
   > ```bash
   > export MNEMONIC='your twelve word mnemonic phrase here ...'
   > export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
   > export COOLDOWN=5  # optional; helps avoid RPC rate limits
   > ```
   > Once you've made sure the account at index 0 of the mnemonic has some ETH for gas, run:
   > ```bash
   > ./scripts/seed.sh .env
   > ```
   > This will seed the specific chain with deployed contracts.
---

> ### Test Tokens
>
> Test tokens supporting ERC-2612 (permit) are already deployed for testing subscriptions. Addresses are listed in `deployments/token_addresses.json` keyed by chain ID (e.g. Sepolia `11155111`, Base Sepolia `84532`). Anyone can mint any amount for testing.
>
> **Deploy a test token** (records the address in `deployments/token_addresses.json` for the current chain):
>
> ```bash
> ./scripts/deployTestToken.sh [env_file]
> ```
>
> **Mint test tokens** to an address (uses the token in `deployments/token_addresses.json` for the current chain):
>
> ```bash
> ./scripts/mintTestToken.sh [env_file] <to> <amount>
> ```
>
> | Input | Description |
> |-------|--------------|
> | `env_file` | Path to an env file to source (e.g. `.env` or `.env.local`). If `.env.local` is passed, Anvil is auto-started. |
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
  - `uint256 _subscriptionPrice` : Price per subscription period for the asset. Must be a non-zero multiple of 100; reverts with `InvalidSubscriptionPrice` otherwise.
  - `uint256 _subscriptionDuration` : Fixed period length in seconds (non-zero). Subscriptions are whole multiples of this duration.
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

**isSubscriptionExpired** : Checks whether a subscriber's subscription for the given asset has expired.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity (e.g. keccak256 of a unique id).
- Returns:
  - `bool` : True if the subscriber's subscription has expired (or never existed).


---

**getSubscriptionExpiration** : Returns the subscription expiry timestamp for the given subscriber for the given asset.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity.
- Returns:
  - `uint256` : Expiry timestamp in seconds; 0 if no subscription.


---

**getSubscriptionPrice** : Returns the total price for a given number of subscription periods for the asset.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `uint256 _count` : Number of subscription periods.
- Returns:
  - `uint256` : Total price (`_count *` per-period price).


---

**isSubscriberRevoked** : Checks whether a subscriber has been permanently revoked for the given asset. Revoked subscribers cannot resubscribe or cancel until the asset owner unrevokes them.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity.
- Returns:
  - `bool` : True if the subscriber has been revoked.


---

**isSubscriptionActive** : Checks whether a subscriber has an active subscription for the given asset (not expired and not revoked).
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity.
- Returns:
  - `bool` : True if the subscriber's subscription is currently active.


---

**getSubscriptionDuration** : Returns the asset's fixed subscription period length in seconds.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
- Returns:
  - `uint256` : Duration of one period in seconds.


---

**getSubscriptionPriceAndDuration** : Returns total token cost and total time for a given number of periods.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `uint256 _count` : Number of subscription periods.
- Returns:
  - `uint256 price` : Total price for `_count` periods.
  - `uint256 duration` : Total subscription time in seconds (`_count *` period length).


---

**subscribe** : Subscribes a subscriber to the asset using ERC-2612 permit; forwards to the asset contract. The permit is signed by the payer; the subscription is attributed to `_subscriber` (payer and subscriber can differ). The payer is the refund beneficiary on cancel/revoke. The permit `value` must equal `getSubscriptionPrice(_count)`. For cancellation-compatible identity, `_subscriber` should be `keccak256(abi.encode(subscriberId, subscriberAddress))`, where `subscriberAddress` is the address that will call `cancelSubscription` and sign the cancellation payload. Reverts if the subscriber has been permanently revoked for the asset.
- Type: write
- Permission: `onlyUnrevoked(_assetId, _subscriber)`
> reverts if the subscriber has been permanently revoked for the asset
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Hash of the subscriber identity (who gets the access). Recommended canonical form: `keccak256(abi.encode(subscriberId, subscriberAddress))`.
  - `address _payer` : Payer; signs the permit and pays. Receives refunds on cancel/revoke. Can be the same or different from the subscriber (e.g. gifting).
  - `address _spender` : Must be the asset contract address for the permit.
  - `uint256 _count` : Number of full subscription periods to subscribe for (must be at least 1).
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
- Notes:
  - Emits `RegistryFeeClaimed(assetId, subscriber, amount, claimedAtTimestamp, claimedAtNonce)`.
  - `claimedAtTimestamp` and `claimedAtNonce` are sourced from the underlying asset claim cursor.


---

**claimRegistryFee** (batch) : Claims the registry fee for multiple subscribers in a single call. Subscribers with no accrued fee are silently skipped.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32[] _subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256 totalClaimedAmount` : Total amount of registry fee claimed across all subscribers.


---

**emitRegistryFeeClaimedEvent** : Emits `RegistryFeeClaimed` for a single subscriber claim cursor update. Intended for calls from the corresponding Asset contract.
- Type: write (event emission)
- Permission: `onlyAsset(_assetId)`
> reverts if `msg.sender` is not the Asset contract registered under `_assetId`; prevents any external caller from spoofing fee-claim log entries
- Parameters:
  - `bytes32 _assetId` : Asset identifier.
  - `bytes32 _subscriber` : Subscriber identity hash.
  - `uint256 claimedAmount` : Amount claimed for this subscriber.
  - `uint256 claimedAtTimestamp` : Timestamp used as upper claim bound.
  - `uint256 claimedAtNonce` : Subscription nonce reached while computing the claim.
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

**getSubscriptionPrice** : Returns the total price for a given number of subscription periods.
- Type: read
- Permission: none
- Parameters:
  - `uint256 count` : Number of subscription periods.
- Returns:
  - `uint256` : Total price (`count *` per-period price).


---

**getSubscriptionDuration** : Returns the fixed subscription period length in seconds.
- Type: read
- Permission: none
- Parameters: none
- Returns:
  - `uint256` : Duration of one period in seconds.


---

**getSubscriptionPriceAndDuration** : Returns total price and total duration for a given number of periods.
- Type: read
- Permission: none
- Parameters:
  - `uint256 count` : Number of subscription periods.
- Returns:
  - `uint256 price` : Total cost for `count` periods.
  - `uint256 duration` : Total time in seconds (`count *` period length).


---

**setSubscriptionPrice** : Sets the subscription price for the asset.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `uint256 newSubscriptionPrice` : New price per subscription period. Must be a non-zero multiple of 100; reverts with `InvalidSubscriptionPrice` otherwise.
- Returns: void


---

**getSubscriptionExpiration** : Returns a subscriber's subscription expiry timestamp.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to query.
- Returns:
  - `uint256` : Expiry timestamp in seconds; 0 if no subscription.


---

**isSubscriptionExpired** : Checks whether a subscriber's subscription has expired (expiry <= block.timestamp).
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to check.
- Returns:
  - `bool` : True if the subscriber's subscription has expired (or never existed).


---

**isSubscriberRevoked** : Checks whether a subscriber has been permanently revoked by the asset owner. Revoked subscribers cannot resubscribe or cancel until the owner calls `unrevokeSubscription`.
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to check.
- Returns:
  - `bool` : True if the subscriber has been revoked.


---

**isSubscriptionActive** : Checks whether a subscriber has an active subscription (not expired and not revoked).
- Type: read
- Permission: none
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity to check.
- Returns:
  - `bool` : True if the subscriber's subscription is currently active.


---

**subscribe** : Subscribes a subscriber using ERC-2612 permit: payer signs permit, then payment is pulled and subscription is attributed to the given subscriber. Payer and subscriber can differ (e.g. pay for someone else). The payer is the refund beneficiary on cancel/revoke. The permit `value` must equal `getSubscriptionPrice(count)`. For cancellation-compatible identity, `subscriber` should be `keccak256(abi.encode(subscriberId, subscriberAddress))`, where `subscriberAddress` is the address that will call `cancelSubscription` and sign the cancellation payload. Reverts if the subscriber has been permanently revoked.
- Type: write
- Permission: `onlyUnrevoked(subscriber)`
> reverts if the subscriber has been permanently revoked
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity (who gets the access). Recommended canonical form: `keccak256(abi.encode(subscriberId, subscriberAddress))`.
  - `address payer` : Payer; signs the permit and pays. Receives refunds on cancel/revoke.
  - `address spender` : Must be this asset contract for the permit to be accepted.
  - `uint256 count` : Number of full subscription periods to subscribe for (must be at least 1).
  - `uint256 deadline` : Permit signature expiry.
  - `uint8 v` : Signature recovery id.
  - `bytes32 r` : Signature r.
  - `bytes32 s` : Signature s.
- Returns:
  - `uint256` : Subscription expiry in Unix timestamp.


---

**claimCreatorFee** (single) : Claims the creator fee for a single subscriber. Accrual covers all completed subscription periods since the last claim. Additionally, when a subscription has fully ended, any partial-period time that was paid for but not yet distributed (dust) is also claimable.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity whose creator fee to claim.
- Returns:
  - `uint256 claimedAmount` : Amount of creator fee claimed.


---

**claimCreatorFee** (batch) : Claims the creator fee for multiple subscribers in a single call. Subscribers with no accrued fee or no subscription are silently skipped. Additionally, when a subscription has fully ended, any partial-period time that was paid for but not yet distributed (dust) is also claimable.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32[] subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256 totalClaimedAmount` : Total amount of creator fee claimed across all subscribers.


---

**claimRegistryFee** (single) : Claims the registry fee for a single subscriber. Callable only by the registry contract.
- Type: write
- Permission: `onlyRegistry`
- Parameters:
  - `bytes32 subscriber` : Hash of the subscriber identity whose registry fee to claim.
- Returns:
  - `uint256 claimedAmount` : Amount of registry fee claimed.
  - `uint256 claimedAtTimestamp` : Timestamp used as the upper claim bound for this call.
  - `uint256 claimedAtNonce` : Subscription nonce reached while computing the claim.


---

**claimRegistryFee** (batch) : Claims the registry fee for multiple subscribers in a single call. Callable only by the registry contract. Subscribers with no accrued fee or no subscription are silently skipped.
- Type: write
- Permission: `onlyRegistry`
- Parameters:
  - `bytes32[] subscribers` : Array of subscriber identity hashes to claim for.
- Returns:
  - `uint256 totalClaimedAmount` : Total amount of registry fee claimed across all subscribers.


---

**revokeSubscription** : Revokes a subscriber's subscription. Refunds all remaining time to each original payer, including any partial-period dust (unlike cancellation which only refunds whole remaining periods). Permanently marks the subscriber as revoked — they cannot resubscribe or cancel until the owner calls `unrevokeSubscription`. Reverts if the subscriber is already revoked.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 subscriber` : Subscriber whose subscription to revoke.
- Returns: void


---

**unrevokeSubscription** : Lifts a permanent revocation for a subscriber, allowing them to resubscribe. Reverts if the subscriber is not currently revoked.
- Type: write
- Permission: `onlyOwner`
- Parameters:
  - `bytes32 subscriber` : Subscriber whose revocation to lift.
- Returns: void


---

**cancelSubscription** : Cancels the caller's subscription after validating an EIP-191 signature from `msg.sender`. Unearned whole subscription periods are refunded to each original payer (partial periods are non-refundable). There is no separate on-chain commit step: the subscriber signs an off-chain message, then submits one transaction with that signature. Reverts if the subscriber has been permanently revoked.
- Type: write
- Permission: `onlyUnrevokedSubscriberId(subscriberId)`
> reverts if the subscriber derived from `keccak256(abi.encode(subscriberId, msg.sender))` has been permanently revoked; additionally, `msg.sender` must be the subscriber address (the recovered ECDSA signer must equal `msg.sender`).
- Parameters:
  - `string subscriberId` : Human-readable subscriber id used in the subscriber hash.
  - `bytes signature` : ECDSA signature by `msg.sender` over the Ethereum signed message hash of `keccak256(abi.encodePacked(chainid, assetAddress, subscriber))`, where `subscriber` is `keccak256(abi.encode(subscriberId, msg.sender))` and `assetAddress` is this asset contract.
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
  - `uint256 subscriptionPrice` : Price per subscription period for the asset.
  - `uint256 subscriptionDuration` : Fixed period length in seconds.
  - `address tokenAddress` : ERC20 (with permit) used for subscription payments.
  - `address indexed owner` : Creator/owner of the new asset.


---

**RegistryFeeShareUpdated** : Emitted when the registry fee share is updated.
- Contract: `AssetRegistry`
- Parameters:
  - `uint256 newRegistryFeeShare` : New registry fee share.


---

**RegistryFeeClaimed** : Emitted when registry fee for a single subscriber claim cursor is materialized.
- Contract: `AssetRegistry`
- Parameters:
  - `bytes32 indexed assetId` : Asset identifier for the claim.
  - `bytes32 indexed subscriber` : Subscriber whose registry fee was claimed.
  - `uint256 amount` : Amount of registry fee claimed.
  - `uint256 claimedAtTimestamp` : Timestamp used as the upper claim bound.
  - `uint256 claimedAtNonce` : Subscription nonce reached while computing the claim.


---

**RegistryFeeClaimedBatch** : Emitted when the registry fee is claimed for multiple subscribers in a single batch call. Emitted once per call regardless of how many subscribers had claimable fees.
- Contract: `AssetRegistry`
- Parameters:
  - `bytes32 indexed assetId` : Asset identifier for which fees were claimed.
  - `bytes32[] indexed subscribers` : Array of subscriber identities passed to the batch claim (note: as an indexed dynamic type, the topic is the keccak256 hash of the ABI-encoded array).
  - `uint256 totalAmount` : Total registry fee claimed across all subscribers in the batch.


---

### Asset

---

**SubscriptionAdded** : Emitted when the first subscription record is created for a subscriber.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber identity (hash).
  - `uint256 indexed startTime` : Subscription start time (Unix timestamp).
  - `uint256 indexed endTime` : Subscription expiry time (Unix timestamp).
  - `address payer` : Payer for this subscription (refund beneficiary on cancel/revoke).
  - `uint256 subscriptionPrice` : Per-period subscription price snapshot used for this subscription record.
  - `uint256 registryFeeShare` : Registry fee share snapshot (0-100) used for this subscription record.


---

**SubscriptionRenewed** : Emitted when a subscriber already has prior subscription history and a new subscription record is created (new nonce). This occurs when in-place extension is not possible (e.g. prior subscription expired, or payer/price/registry fee share differs from the current active record).
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber identity (hash).
  - `uint256 indexed startTime` : New subscription record start time (Unix timestamp).
  - `uint256 indexed endTime` : New subscription record expiry time (Unix timestamp).
  - `uint256 nonce` : New subscription nonce for this subscriber.
  - `address payer` : Payer for this subscription (refund beneficiary on cancel/revoke).
  - `uint256 subscriptionPrice` : Per-period subscription price snapshot used for this subscription record.
  - `uint256 registryFeeShare` : Registry fee share snapshot (0-100) used for this subscription record.


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
  - `uint256 indexed claimedAtTimestamp` : Timestamp used as the upper claim bound.
  - `uint256 indexed claimedAtNonce` : Subscription nonce reached while computing the claim.


---

**CreatorFeeClaimedBatch** : Emitted when creator fees are claimed for multiple subscribers in a single batch call. Emitted once per batch call regardless of how many subscribers had claimable fees.
- Contract: `Asset`
- Parameters:
  - `bytes32[] indexed subscribers` : Array of subscriber identities passed to the batch claim (note: as an indexed dynamic type, the topic is the keccak256 hash of the ABI-encoded array).
  - `uint256 totalAmount` : Total creator fee claimed across all subscribers in the batch.


---

**SubscriptionPriceUpdated** : Emitted when the subscription price is updated.
- Contract: `Asset`
- Parameters:
  - `uint256 newSubscriptionPrice` : New price per subscription period.


---

**SubscriptionRevoked** : Emitted when a subscriber's subscription is revoked by the asset owner. The subscriber is permanently added to the revoked set; they cannot resubscribe until `unrevokeSubscription` is called.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose subscription was revoked.
  - `uint256 indexed nonce` : Active nonce after revocation/removal processing.
  - `uint256 indexed endTime` : Effective end time after revocation (set to `block.timestamp`). Will be `0` when the subscriber is fully removed.


---

**SubscriptionUnrevoked** : Emitted when the asset owner lifts a permanent revocation for a subscriber.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber whose revocation was lifted.


---

**SubscriptionCancelled** : Emitted when a subscriber's subscription is cancelled through the subscriber-signed cancellation flow.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber hash `keccak256(abi.encode(subscriberId, subscriberAddress))` whose subscription was cancelled.
  - `uint256 indexed nonce` : Active nonce after cancellation/removal processing.
  - `uint256 indexed endTime` : Effective end time after cancellation. Will be `0` when the subscriber is fully removed.


---

**SubscriptionRemoved** : Emitted when all remaining subscription records for a subscriber are deleted and the subscriber is removed from tracking state.
- Contract: `Asset`
- Parameters:
  - `bytes32 indexed subscriber` : Subscriber identity (hash) that was fully removed.