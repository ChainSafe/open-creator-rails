# Gas Benchmarks

Foundry tests that measure gas scaling for execution paths with variable loops (1 → 10 → 100 → 1,000 → 10,000).

These tests live in `gas/` (not `test/`) so they are **not included in default `forge test`**. Run them with the `gas` profile:

```bash
FOUNDRY_PROFILE=gas forge test --isolate -vv
```

## What is measured

| Test group | Scaling axis | Target function |
|---|---|---|
| `test_gas_claimCreatorFee_nonceDepth_*` | Nonces per subscriber | `Asset.claimCreatorFee(bytes32)` → `_claimable` loop |
| `test_gas_claimRegistryFee_nonceDepth_*` | Nonces per subscriber | `Asset.claimRegistryFee(bytes32)` → `_claimable` loop |
| `test_gas_revokeSubscription_nonceDepth_*` | Stacked nonces | `Asset.revokeSubscription` → `_removeSubscription` loop |
| `test_gas_cancelSubscription_nonceDepth_*` | Stacked nonces | `Asset.cancelSubscription` → `_removeSubscription` loop |

**Nonce depth (claim):** each renewal happens after the previous subscription expires, producing one storage record per nonce.
```
vm.warp(endTime + 1);
```

**Stacked nonces (revoke/cancel):** price is bumped between subscribes so each call creates a new future record without extending the same nonce.
```
asset.setSubscriptionPrice(SUBSCRIPTION_PRICE + (i * 100));
```

## Quick start

Run all gas benchmarks (slow for 10k scale points):

```bash
FOUNDRY_PROFILE=gas forge test --isolate -vv
```

Run a single scale point (recommended while iterating):

```bash
FOUNDRY_PROFILE=gas forge test --match-test 'test_gas_claimCreatorFee_nonceDepth_1000\(\)' --isolate -vv
```

Verify which tests will run before executing:

```bash
FOUNDRY_PROFILE=gas forge test --match-test 'test_gas_claimCreatorFee_nonceDepth_1000\(\)' --list
```

### Matching a single test

`--match-test` uses a **regex** against the full function signature (including `()`), not just the name.

| Pattern | Matches |
|---|---|
| `test_gas_claimCreatorFee_nonceDepth_1` | `_1`, `_10`, `_100`, `_1000`, `_10000` (substring) |
| `test_gas_claimCreatorFee_nonceDepth_1\(\)` | only depth **1** |

Alternative using exclusion:

```bash
FOUNDRY_PROFILE=gas forge test \
  --match-test 'test_gas_claimCreatorFee_nonceDepth_1' \
  --no-match-test '10|100|1000|10000' \
  --isolate -vv
```

Run every test at one scale (e.g. all four paths at depth 100):

```bash
FOUNDRY_PROFILE=gas forge test --match-test 'nonceDepth_100\(\)' --isolate -vv
```

Use the **`gas`** profile for scale **10,000** (raises test `gas_limit` to 10B and memory to 4GB):

```bash
FOUNDRY_PROFILE=gas forge test --match-test 'test_gas_claimCreatorFee_nonceDepth_10000\(\)' --isolate -vv
```

The `gas` profile sets `test = "gas"` and a higher `gas_limit`. Scale **10,000** needs that raised limit because setup exceeds the default Foundry gas limit (~1.07B) in [foundry.toml](../foundry.toml).

## Reading results

### Console output

Each test logs two lines via `console2`:

```
Logs:
  scale: 1000
  gas: 12345678
```

Gas is the **measured call only** (setup/subscribe loops are excluded).

### Snapshot files

`vm.startSnapshotGas` writes JSON under `snapshots/gas/`, keyed by scale:

- [`snapshots/gas/claimCreatorFee_nonceDepth.json`](../snapshots/gas/claimCreatorFee_nonceDepth.json)
- [`snapshots/gas/claimRegistryFee_nonceDepth.json`](../snapshots/gas/claimRegistryFee_nonceDepth.json)
- [`snapshots/gas/revokeSubscription_nonceDepth.json`](../snapshots/gas/revokeSubscription_nonceDepth.json)
- [`snapshots/gas/cancelSubscription_nonceDepth.json`](../snapshots/gas/cancelSubscription_nonceDepth.json)

Example:

```json
{
  "1": "105204",
  "10": "235899",
  "100": "1344960"
}
```

Compare runs over time with `forge snapshot` (optional; separate from the JSON files above):

```bash
FOUNDRY_PROFILE=gas forge snapshot --isolate
FOUNDRY_PROFILE=gas forge snapshot --diff --isolate
```

Commit `.gas-snapshot` if you want CI to fail on regressions, look at [foundry-gas.yml](../.github/workflows/foundry-gas.yml).

## Why `--isolate` matters

Without `--isolate`, multiple calls in one test share warm storage and refund accounting inside a single transaction. **`--isolate` runs each top-level contract call as its own transaction**, which matches on-chain gas more closely.

Always use `--isolate` when interpreting these numbers.

## Deriving marginal cost

Run two adjacent scale points and subtract:

```
marginal_gas_per_nonce ≈ gas(depth=1000) - gas(depth=100) / (1000 - 100)
```

Plot `scale` vs `gas` to see where you cross a target block gas limit (e.g. 30M on Ethereum L1).

### Translating gas to ETH

```
cost (ETH) = gas_used × gas_price_gwei / 1_000_000_000
```

Example: `1,344,960` gas at `30 gwei` → `0.0403 ETH` (~$101 at $2,500/ETH).

## Limits of Foundry benchmarks

- No block gas limit is enforced in the EVM runner; 10k-scale numbers show **slope**, not whether a tx fits in one block.
- Refunds from `delete` in `_removeSubscription` are capped on mainnet (EIP-3529); `--isolate` models refunds per transaction more accurately than non-isolated tests.
- Compiler settings (`optimizer`, `via_ir`, `optimizer_runs`) affect absolute gas; compare runs with the same `foundry.toml` profile.

<!-- Begin: generated -->

<!-- End: generated -->
