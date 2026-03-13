import { onchainTable, index } from "ponder";

// --- Entities (Mutable State) ---

export const AssetEntity = onchainTable("asset_entity", (t) => ({
  id: t.text().primaryKey(),    // Asset Contract Address
  assetId: t.text().notNull(),  // Registry ID
  registryAddress: t.text().notNull(),
  owner: t.text().notNull(),
}), (table) => ({
  ownerIdx: index().on(table.owner),
  registryAddressIdx: index().on(table.registryAddress),
  assetIdIdx: index().on(table.assetId),
}));

export const AssetIdToAddress = onchainTable("asset_id_to_address", (t) => ({
  id: t.text().primaryKey(), // assetId (bytes32 hex)
  assetAddress: t.text().notNull(),
}));

export const Subscription = onchainTable("subscription", (t) => ({
  id: t.text().primaryKey(),    // Composite: `${asset}_${user}`
  assetId: t.text().notNull(),  // Links to AssetEntity.id (Renamed from assetId to match Envio)
  user: t.text().notNull(),
  startTime: t.bigint().notNull(),
  endTime: t.bigint().notNull(),
  nonce: t.bigint().notNull(),
  isActive: t.boolean().notNull(),
}), (table) => ({
  assetIdIdx: index().on(table.assetId),
  userIdx: index().on(table.user),
}));

// --- Events (Immutable History) ---
// Note: Ponder doesn't enforce "History" tables but they are useful for analytics

export const AssetRegistry_AssetCreated = onchainTable("asset_registry_asset_created", (t) => ({
  id: t.text().primaryKey(),
  assetId: t.text().notNull(),
  asset: t.text().notNull(),
  subscriptionPrice: t.bigint().notNull(),
  tokenAddress: t.text().notNull(),
  owner: t.text().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  assetIdx: index().on(table.asset),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_OwnershipTransferred = onchainTable("asset_registry_ownership_transferred", (t) => ({
  id: t.text().primaryKey(),
  previousOwner: t.text().notNull(),
  newOwner: t.text().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  previousOwnerIdx: index().on(table.previousOwner),
  newOwnerIdx: index().on(table.newOwner),
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_CreatorFeeShareUpdated = onchainTable("asset_registry_creator_fee_share_updated", (t) => ({
  id: t.text().primaryKey(),
  newCreatorFeeShare: t.bigint().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  registryAddressIdx: index().on(table.registryAddress),
}));

export const AssetRegistry_RegistryFeeShareUpdated = onchainTable("asset_registry_registry_fee_share_updated", (t) => ({
  id: t.text().primaryKey(),
  newRegistryFeeShare: t.bigint().notNull(),
  registryAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  registryAddressIdx: index().on(table.registryAddress),
}));

export const Asset_SubscriptionAdded = onchainTable("asset_subscription_added", (t) => ({
  id: t.text().primaryKey(),
  user: t.text().notNull(),
  startTime: t.bigint().notNull(),
  endTime: t.bigint().notNull(),
  nonce: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  userIdx: index().on(table.user),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionPriceUpdated = onchainTable("asset_subscription_price_updated", (t) => ({
  id: t.text().primaryKey(),
  newSubscriptionPrice: t.bigint().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_SubscriptionRevoked = onchainTable("asset_subscription_revoked", (t) => ({
  id: t.text().primaryKey(),
  user: t.text().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  userIdx: index().on(table.user),
  assetAddressIdx: index().on(table.assetAddress),
}));

export const Asset_OwnershipTransferred = onchainTable("asset_ownership_transferred", (t) => ({
  id: t.text().primaryKey(),
  previousOwner: t.text().notNull(),
  newOwner: t.text().notNull(),
  assetAddress: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
}), (table) => ({
  previousOwnerIdx: index().on(table.previousOwner),
  newOwnerIdx: index().on(table.newOwner),
  assetAddressIdx: index().on(table.assetAddress),
}));
