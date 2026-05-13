# Execution Flows

This document walks through the major execution flows in `AssetRegistry` and `Asset`, including the off-chain signatures required before on-chain calls.

---

## Table of Contents

1. [Actors & Concepts](#actors--concepts)
2. [createAsset](#createasset)
3. [subscribe](#subscribe)
   - [New Subscription](#new-subscription)
   - [Extend Existing Subscription](#extend-existing-subscription)
   - [Renew Subscription (New Nonce)](#renew-subscription-new-nonce)
4. [cancelSubscription](#cancelsubscription)
5. [revokeSubscription](#revokesubscription)
6. [unrevokeSubscription](#unrevokesubscription)
7. [claimCreatorFee (single subscriber)](#claimcreatorfeesingle-subscriber)
8. [claimCreatorFee (batch)](#claimcreatorfeebatch)
9. [claimRegistryFee](#claimregistryfee)

---

## Actors & Concepts

| Actor | Description |
|---|---|
| **Registry Owner** | Deployer/admin of `AssetRegistry`; can create assets and claim registry fees |
| **Creator** | Owner of a specific `Asset` contract; receives the creator share of subscription revenue |
| **Payer** | EOA whose ERC20 tokens fund a subscription |
| **Subscriber** | Off-chain identity represented as `keccak256(abi.encode(subscriberId, subscriberAddress))` |
| **AssetRegistry** | Central registry that deploys `Asset` contracts and routes calls |
| **Asset** | Per-creator contract that holds subscriptions and accrued fees |
| **ERC20 (Permit)** | Payment token that supports EIP-2612 `permit` (gasless approval) |

**Subscriber ID derivation:**
```
subscriberBytes32 = keccak256(abi.encode(subscriberIdString, subscriberAddress))
```
This ties an off-chain identity string to a specific Ethereum address.

**Fee split:** every subscription payment is split between Registry Owner and Creator:
```
registryShare = value × registryFeeShare / 100
creatorShare = value - registryShare
```
The split percentage is snapshotted into each `Subscription` record at subscribe time.

---

## createAsset

The Registry Owner registers a new creator asset. The call deploys a fresh `Asset` contract and records its address in the registry.

```mermaid
sequenceDiagram
    actor RO as Registry Owner
    participant AR as AssetRegistry
    participant A as Asset (new)

    RO->>AR: createAsset(assetId, subscriptionPrice,<br/>subscriptionDuration, tokenAddress, creatorAddress)
    AR->>AR: revert if assetId already registered
    AR->>A: new Asset(assetId, price, duration, token, creator)
    A-->>AR: deployed at address
    AR->>AR: assets[assetId] = address(asset)
    AR-->>RO: emit AssetCreated(assetId, assetAddress, …)
    AR-->>RO: return assetAddress
```

**Key validations in `Asset` constructor:**
- `_owner != address(0)` — creator address must be set
- `_tokenAddress != address(0)` — payment token must be set
- `_subscriptionDuration > 0` — period length must be non-zero
- `msg.sender` (the registry) is stored as `REGISTRY_ADDRESS` — only the registry can call `onlyRegistry` functions

---

## subscribe

Subscribing always requires an **off-chain EIP-2612 permit signature** from the payer. This lets the `Asset` contract pull payment tokens without a prior on-chain `approve` transaction.

### Off-chain permit signature (required before every subscribe call)

The payer signs an EIP-2612 permit off-chain:

```
domain:  { name, version, chainId, verifyingContract: tokenAddress }
message: { owner: payerAddress, spender: assetAddress,
           value: count × subscriptionPrice, nonce: tokenNonce, deadline }
```

This produces `(v, r, s)` which are passed directly to `subscribe`.

---

### New Subscription

```mermaid
sequenceDiagram
    actor P as Payer
    participant ERC20 as ERC20 Token
    participant AR as AssetRegistry
    participant A as Asset

    Note over P: 1. Build permit payload off-chain
    P->>P: sign EIP-2612 permit(spender=Asset, value=count×price, deadline)

    Note over P: 2. Submit on-chain
    P->>AR: subscribe(assetId, subscriber, payer, spender,<br/>count, deadline, v, r, s)
    AR->>AR: onlyUnrevoked — revert if subscriber revoked
    AR->>A: subscribe(subscriber, payer, spender, count, deadline, v, r, s)
    A->>A: onlyUnrevoked — revert if subscriber revoked
    A->>A: validatePermit — revert if spender ≠ address(this)
    A->>ERC20: permit(payer, asset, value, deadline, v, r, s)
    ERC20-->>A: approval recorded
    A->>ERC20: safeTransferFrom(payer, asset, value)
    ERC20-->>A: tokens transferred

    A->>AR: getRegistryFeeShare()
    AR-->>A: registryFeeShare %

    A->>A: subscriber not in set → new subscription
    A->>A: store Subscription{startTime, endTime,<br/>price, feeShare, payer}
    A->>A: subscribers.add(subscriber)
    A-->>AR: emit SubscriptionAdded(subscriber, startTime, endTime, …)
    AR-->>P: return endTime
```

---

### Extend Existing Subscription

Triggered when the subscriber already exists **and** all conditions match: same payer, same subscription price, same registry fee share, and the current `endTime` is greater than `block.timestamp` (subscription is still active and contiguous).

```mermaid
sequenceDiagram
    actor P as Payer
    participant ERC20 as ERC20 Token
    participant AR as AssetRegistry
    participant A as Asset

    Note over P: Same permit signing step as above
    P->>P: sign EIP-2612 permit(spender=Asset, value=count×price, deadline)

    P->>AR: subscribe(assetId, subscriber, payer, …)
    AR->>AR: onlyUnrevoked — revert if subscriber revoked
    AR->>A: subscribe(subscriber, payer, …)
    A->>A: onlyUnrevoked — revert if subscriber revoked
    A->>ERC20: permit + safeTransferFrom (payment pulled)

    A->>A: subscriber already in set
    A->>A: currentEndTime > now (block.timestamp)
    A->>A: payer/price/feeShare unchanged?  YES
    A->>A: subscriptions[id].endTime += duration  (in-place update, nonce unchanged)
    A-->>AR: emit SubscriptionExtended(subscriber, newEndTime)
    AR-->>P: return newEndTime
```

> **No nonce increment** — the existing subscription record is extended in place.

---

### Renew Subscription (New Nonce)

Triggered when the subscriber already exists but conditions differ (different payer, updated price, or updated registry fee share), or when the subscription has already expired (gap in coverage).

```mermaid
sequenceDiagram
    actor P as Payer
    participant ERC20 as ERC20 Token
    participant AR as AssetRegistry
    participant A as Asset

    Note over P: Same permit signing step
    P->>P: sign EIP-2612 permit(spender=Asset, value=count×newPrice, deadline)

    P->>AR: subscribe(assetId, subscriber, payer, …)
    AR->>AR: onlyUnrevoked — revert if subscriber revoked
    AR->>A: subscribe(…)
    A->>A: onlyUnrevoked — revert if subscriber revoked
    A->>ERC20: permit + safeTransferFrom

    A->>A: subscriber already in set
    A->>A: conditions differ OR expired gap
    A->>A: nonces[subscriber]++ → new nonce
    A->>A: id = keccak256(subscriber, newNonce)
    A->>A: store new Subscription{startTime, endTime, price, feeShare, payer}
    A-->>AR: emit SubscriptionRenewed(subscriber, startTime, endTime, newNonce, …)
    AR-->>P: return endTime
```

> The old subscription record remains intact under its original nonce and is used to calculate claimable fees up to the renewal point.

---

## cancelSubscription

A subscriber cancels their own subscription. Because the `subscriber` bytes32 is derived from an off-chain string identity, the caller must prove they know the pre-image by providing an **ECDSA self-signature**.

### Off-chain signature required

```
hash = keccak256(abi.encodePacked(chainId, assetAddress, subscriberBytes32))
ethSignedHash = "\x19Ethereum Signed Message:\n32" + hash
signature = sign(ethSignedHash)   ← signed by msg.sender (the subscriber address)
```

```mermaid
sequenceDiagram
    actor S as Subscriber (msg.sender)
    participant ERC20 as ERC20 Token
    participant A as Asset

    Note over S: 1. Derive subscriber identity off-chain
    S->>S: subscriberBytes32 = keccak256(abi.encode(subscriberId, msg.sender))

    Note over S: 2. Sign cancellation proof off-chain
    S->>S: hash = keccak256(abi.encodePacked(chainId, assetAddress, subscriberBytes32))
    S->>S: signature = sign(toEthSignedMessageHash(hash))

    Note over S: 3. Submit on-chain
    S->>A: cancelSubscription(subscriberId, signature)
    A->>A: onlyUnrevokedSubscriberId — revert if subscriber revoked
    A->>A: re-derive subscriberBytes32 = keccak256(subscriberId, msg.sender)
    A->>A: re-derive hash = keccak256(chainId, address(this), subscriber)
    A->>A: signer = ECDSA.recover(ethSignedHash, signature)
    A->>A: revert InvalidSignature if signer ≠ msg.sender

    A->>A: _removeSubscription(subscriber, isCancellation=true, isRevocation=false)
    Note over A: Iterate from newest to oldest nonce
    loop for each active / future subscription
        A->>A: count = refundable whole periods
        A->>ERC20: safeTransfer(payer, count × price)
    end
    A->>A: if all records deleted → remove subscriber, reset nonces
    A-->>S: emit SubscriptionCancelled(subscriber, nonce, endTime)
```

**Refund logic inside `_removeSubscription` (cancellation):**
- Future (not-yet-started) subscription records → full refund for all periods
- Active subscription → refund for all **remaining whole periods** (partial current period is non-refundable)
- Expired subscriptions → no refund; loop breaks early

---

## revokeSubscription

The **creator (asset owner)** forcibly ends a subscriber's access. Unlike cancellation, revocation refunds all remaining time including partial-period dust, and **permanently bans** the subscriber from resubscribing until the owner calls `unrevokeSubscription`.

```mermaid
sequenceDiagram
    actor C as Creator (onlyOwner)
    participant ERC20 as ERC20 Token
    participant A as Asset

    C->>A: revokeSubscription(subscriber)
    A->>A: onlyOwner check
    A->>A: revert SubscriptionAlreadyRevoked if already revoked

    A->>A: _removeSubscription(subscriber, isCancellation=false, isRevocation=true)
    loop for each active / future subscription
        A->>A: endTime = block.timestamp (cut off immediately)
        A->>A: returnable = total paid − (elapsed periods + dust)
        A->>ERC20: safeTransfer(payer, returnable)
    end
    A->>A: revokedSubscribers.add(subscriber)

    A-->>C: emit SubscriptionRevoked(subscriber, nonce, endTime)
```

**Revocation refund logic (differs from cancellation):**
- Active subscription → the `endTime` is set to `block.timestamp`; the payer receives a full refund of unspent time, including partial-period dust (proportional to the fractional period elapsed)
- Future (not-yet-started) subscription records → full refund for all periods (same as cancellation)
- The subscriber is added to the `revokedSubscribers` set regardless; they cannot call `subscribe` or `cancelSubscription` until unrevoked

---

## unrevokeSubscription

The **creator (asset owner)** lifts a permanent revocation, allowing the subscriber to resubscribe.

```mermaid
sequenceDiagram
    actor C as Creator (onlyOwner)
    participant A as Asset

    C->>A: unrevokeSubscription(subscriber)
    A->>A: onlyOwner check
    A->>A: revert SubscriptionNotRevoked if not currently revoked
    A->>A: revokedSubscribers.remove(subscriber)
    A-->>C: emit SubscriptionUnrevoked(subscriber)
```

> After unrevoking, the subscriber may call `subscribe` again. Their prior subscription history (nonces, claim cursors) is preserved.

---

## claimCreatorFee — Single Subscriber

The creator pulls their accumulated share for one subscriber. The claimable amount covers all **fully completed subscription periods** since the last claim.

```mermaid
sequenceDiagram
    actor C as Creator (onlyOwner)
    participant ERC20 as ERC20 Token
    participant A as Asset

    C->>A: claimCreatorFee(subscriber)
    A->>A: onlyOwner + nonReentrant check

    A->>A: _claimable(subscriber, creatorClaimedAtTimestamp,<br/>creatorClaimedAtNonce, isOwner=true, timestamp=now)
    Note over A: Iterate nonces from last claimed nonce<br/>Sum (fee - registryFee) for each fully-passed period

    A->>A: creatorClaimedAtTimestamps[subscriber] = newTimestamp
    A->>A: creatorClaimedAtNonces[subscriber] = newNonce

    alt creatorFee > 0
        A->>ERC20: safeTransfer(owner, creatorFee)
    end

    A-->>C: emit CreatorFeeClaimed(subscriber, amount, claimedAtTimestamp, claimedAtNonce)
    A-->>C: return creatorFee
```

---

## claimCreatorFee — Batch

The creator claims across multiple subscribers in a single transaction.

```mermaid
sequenceDiagram
    actor C as Creator (onlyOwner)
    participant ERC20 as ERC20 Token
    participant A as Asset

    C->>A: claimCreatorFee(subscribers[])
    A->>A: onlyOwner + nonReentrant check
    A->>A: snapshot timestamp = block.timestamp

    loop for each subscriber in array
        A->>A: skip if subscriber not in set
        A->>A: _claimable(subscriber, …, isOwner=true, timestamp)
        A->>A: skip if claimedAmount == 0
        A->>A: update creatorClaimedAtTimestamps / Nonces
        A->>A: totalClaimedAmount += claimedAmount
        A-->>C: emit CreatorFeeClaimed(subscriber, amount, …)
    end

    alt totalClaimedAmount > 0
        A->>ERC20: safeTransfer(owner, totalClaimedAmount)
    end

    A-->>C: emit CreatorFeeClaimedBatch(subscribers[], totalClaimedAmount)
    A-->>C: return totalClaimedAmount
```

---

## claimRegistryFee

The **Registry Owner** claims the registry's share via `AssetRegistry`, which is the only caller authorised to invoke `onlyRegistry` functions on `Asset`.

### Single subscriber

```mermaid
sequenceDiagram
    actor RO as Registry Owner (onlyOwner)
    participant ERC20 as ERC20 Token
    participant AR as AssetRegistry
    participant A as Asset

    RO->>AR: claimRegistryFee(assetId, subscriber)
    AR->>AR: onlyOwner check
    AR->>A: claimRegistryFee(subscriber)
    A->>A: onlyRegistry check (msg.sender == REGISTRY_ADDRESS)

    A->>A: _claimable(subscriber, registryClaimedAtTimestamp,<br/>registryClaimedAtNonce, isRegistry=true, timestamp=now)
    Note over A: Sum registryFee for each fully-passed period

    A->>A: registryClaimedAtTimestamps[subscriber] = newTimestamp
    A->>A: registryClaimedAtNonces[subscriber] = newNonce

    alt claimedAmount > 0
        A->>AR: getOwner()
        AR-->>A: registryOwnerAddress
        A->>ERC20: safeTransfer(registryOwner, claimedAmount)
    end

    A-->>AR: return (claimedAmount, claimedAtTimestamp, claimedAtNonce)
    AR-->>RO: emit RegistryFeeClaimed(assetId, subscriber, amount, …)
    AR-->>RO: return claimedAmount
```

### Batch

```mermaid
sequenceDiagram
    actor RO as Registry Owner (onlyOwner)
    participant ERC20 as ERC20 Token
    participant AR as AssetRegistry
    participant A as Asset

    RO->>AR: claimRegistryFee(assetId, subscribers[])
    AR->>AR: onlyOwner check
    AR->>A: claimRegistryFee(subscribers[])
    A->>A: onlyRegistry check
    A->>A: snapshot timestamp = block.timestamp

    loop for each subscriber in array
        A->>A: skip if subscriber not in set
        A->>A: _claimable(subscriber, …, isRegistry=true, timestamp)
        A->>A: skip if claimedAmount == 0
        A->>A: update registryClaimedAtTimestamps / Nonces
        A->>A: totalClaimedAmount += claimedAmount
        A->>AR: emitRegistryFeeClaimedEvent(assetId, subscriber, amount, …)
        AR-->>A: emit RegistryFeeClaimed(…)
    end

    alt totalClaimedAmount > 0
        A->>AR: getOwner()
        AR-->>A: registryOwnerAddress
        A->>ERC20: safeTransfer(registryOwner, totalClaimedAmount)
    end

    A-->>AR: return totalClaimedAmount
    AR-->>RO: emit RegistryFeeClaimedBatch(assetId, subscribers[], totalClaimedAmount)
    AR-->>RO: return totalClaimedAmount
```

> `emitRegistryFeeClaimedEvent` is a callback from `Asset` back into `AssetRegistry`. The registry verifies `msg.sender == assets[assetId]` before emitting the event, preventing spoofed log entries.

---

## Fee Accrual & Claimability

The `_claimable` internal function is the heart of both claim flows. It never double-counts and handles nonce rollovers:

```
for nonce = lastClaimedNonce → currentNonce:
    startTime         = max(subscription.startTime, claimedAtTimestamp)
    endTime           = min(subscription.endTime,   block.timestamp)
    claimableDuration = endTime - startTime
    count             = claimableDuration / SUBSCRIPTION_DURATION   // whole periods
    fee               = count × subscription.subscriptionPrice

    // dust: partial period at the very end of a fully-elapsed subscription
    if endTime == subscription.endTime:
        dustDuration = claimableDuration - (count × SUBSCRIPTION_DURATION)
        dust         = (dustDuration × subscription.subscriptionPrice) / SUBSCRIPTION_DURATION
        fee         += dust

    claimable += (isOwner ? fee - registryFee : registryFee)
    claimedAtTimestamp = startTime + count × SUBSCRIPTION_DURATION
```

Key properties:
- **Whole-period granularity for active subscriptions** — sub-period time is not distributed while a subscription is still running
- **Dust distribution at subscription end** — once a subscription has fully elapsed (`endTime <= block.timestamp`), any partial period that was paid for but not yet distributed is included in the next claim, ensuring no tokens are permanently locked in the contract
- **Snapshot prices** — each `Subscription` record carries the price and fee share that were active at subscribe time; retroactive price changes do not affect already-paid subscriptions
- **Independent cursors** — creator and registry each maintain their own `claimedAtTimestamp`/`claimedAtNonce`, so one party claiming does not affect the other's position
