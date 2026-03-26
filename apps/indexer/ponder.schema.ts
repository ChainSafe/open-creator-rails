import { onchainTable, index } from "ponder";

// --- Entities (Mutable State) ---

export const AssetEntity = onchainTable("asset_entity", (t) => ({
  id: t.text().primaryKey(),    // Composite: `${chainId}_${assetAddress}`
  chainId: t.integer().notNull(),
  assetId: t.text().notNull(),  // Registry ID
  address: t.text().notNull(),
  registryAddress: t.text().notNull(),
  owner: t.text().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  ownerIdx: index().on(table.owner),
  registryAddressIdx: index().on(table.registryAddress),
  assetIdIdx: index().on(table.assetId),
}));

// Tracks the current state of a subscriber's subscription to an asset.
// One row per asset–subscriber pair (not per nonce). When terms change mid-subscription
// (price, payer, fee share), the contract creates a new nonce but the indexer preserves
// the original startTime to show unbroken continuity. payer and nonce always reflect
// the latest on-chain subscription record.
export const Subscription = onchainTable("subscription", (t) => ({
  id: t.text().primaryKey(),       // Composite: `${AssetEntity.id}_${subscriber}`
  chainId: t.integer().notNull(),
  assetId: t.text().notNull(),     // Links to AssetEntity.id
  subscriber: t.text().notNull(),  // bytes32 subscriber identity hash
  payer: t.text().notNull(),       // address that paid (latest nonce)
  startTime: t.bigint().notNull(), // original start of unbroken subscription continuity
  endTime: t.bigint().notNull(),   // current expiry (updated by SubscriptionAdded & SubscriptionExtended)
  nonce: t.bigint().notNull(),     // latest on-chain nonce (increments when terms change)
  isActive: t.boolean().notNull(), // false when revoked or cancelled
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  assetIdIdx: index().on(table.assetId),
  subscriberIdx: index().on(table.subscriber),
  payerIdx: index().on(table.payer),
}));

// --- Events (Immutable History) ---
// Note: Ponder doesn't enforce "History" tables but they are useful for analytics

export const AssetRegistry_AssetCreated = onchainTable("asset_registry_asset_created", (t) => ({
  id: t.text().primaryKey(),       // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  assetId: t.text().notNull(),
  asset: t.text().notNull(),
  subscriptionPrice: t.bigint().notNull(),
  tokenAddress: t.text().notNull(),
  owner: t.text().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  assetIdx: index().on(table.asset),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_OwnershipTransferred = onchainTable("asset_registry_ownership_transferred", (t) => ({
  id: t.text().primaryKey(),        // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  previousOwner: t.text().notNull(),
  newOwner: t.text().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  previousOwnerIdx: index().on(table.previousOwner),
  newOwnerIdx: index().on(table.newOwner),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_RegistryFeeShareUpdated = onchainTable("asset_registry_registry_fee_share_updated", (t) => ({
  id: t.text().primaryKey(),       // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  newRegistryFeeShare: t.bigint().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_RegistryFeeClaimedBatch = onchainTable("asset_registry_registry_fee_claimed_batch", (t) => ({
  id: t.text().primaryKey(),    // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  assetId: t.text().notNull(),
  totalAmount: t.bigint().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  assetIdIdx: index().on(table.assetId),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const Asset_SubscriptionAdded = onchainTable("asset_subscription_added", (t) => ({
  id: t.text().primaryKey(),   // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  subscriber: t.text().notNull(),
  payer: t.text().notNull(),
  startTime: t.bigint().notNull(),
  endTime: t.bigint().notNull(),
  nonce: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  subscriberIdx: index().on(table.subscriber),
  payerIdx: index().on(table.payer),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionExtended = onchainTable("asset_subscription_extended", (t) => ({
  id: t.text().primaryKey(),  // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  subscriber: t.text().notNull(),
  endTime: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  subscriberIdx: index().on(table.subscriber),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_CreatorFeeClaimed = onchainTable("asset_creator_fee_claimed", (t) => ({
  id: t.text().primaryKey(),   // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  subscriber: t.text().notNull(),
  amount: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  subscriberIdx: index().on(table.subscriber),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionPriceUpdated = onchainTable("asset_subscription_price_updated", (t) => ({
  id: t.text().primaryKey(),   // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  newSubscriptionPrice: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionRevoked = onchainTable("asset_subscription_revoked", (t) => ({
  id: t.text().primaryKey(),  // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  subscriber: t.text().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  subscriberIdx: index().on(table.subscriber),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionCancelled = onchainTable("asset_subscription_cancelled", (t) => ({
  id: t.text().primaryKey(),   // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  subscriber: t.text().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  subscriberIdx: index().on(table.subscriber),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_OwnershipTransferred = onchainTable("asset_ownership_transferred", (t) => ({
  id: t.text().primaryKey(),  // Composite: `${chainId}-${event.transaction.hash}-${event.log.logIndex}`
  chainId: t.integer().notNull(),
  previousOwner: t.text().notNull(),
  newOwner: t.text().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  chainIdIdx: index().on(table.chainId),
  previousOwnerIdx: index().on(table.previousOwner),
  newOwnerIdx: index().on(table.newOwner),
  assetAddressIdx: index().on(table.assetAddress),
}));
