import { ponder } from "ponder:registry";
import {
  AssetEntity,
  Subscription,
  AssetRegistry_AssetCreated,
  AssetRegistry_OwnershipTransferred,
  AssetRegistry_RegistryFeeShareUpdated,
  AssetRegistry_RegistryFeeClaimedBatch,
  Asset_SubscriptionAdded,
  Asset_SubscriptionExtended,
  Asset_CreatorFeeClaimed,
  Asset_SubscriptionRevoked,
  Asset_SubscriptionCancelled,
  Asset_SubscriptionPriceUpdated,
  Asset_OwnershipTransferred
} from "../ponder.schema";
import { get } from "http";

// Helper function to generate robust IDs for event history rows
const getEventId = (event: any, chainId: number) => {
  return `${chainId}-${event.transaction.hash}-${event.log.logIndex}`;
};

// Helper function to generate Asset Entity IDs
const getAssetEntityId = (chainId: number, assetAddress: string) => {
  return `${chainId}_${assetAddress}`;
};

// Helper function to generate Subscription IDs
const getSubscriptionId = (chainId: number, assetAddress: string, subscriber: string) => {
  return `${chainId}_${assetAddress}_${subscriber}`;
}

// ============================================================================
// AssetRegistry Handlers
// ============================================================================

ponder.on("AssetRegistry:AssetCreated", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.args.asset.toLowerCase();
  const owner = event.args.owner.toLowerCase();
  const tokenAddress = event.args.tokenAddress.toLowerCase();

  const assetEntityId = getAssetEntityId(chainId, assetAddress);

  // 1. Create the persistent Asset Entity
  await context.db.insert(AssetEntity).values({
    id: assetEntityId,
    chainId: chainId,
    assetId: event.args.assetId,
    address: assetAddress,
    registryAddress: event.log.address,
    owner: owner,
  });

  // 2. Log immutable history
  await context.db.insert(AssetRegistry_AssetCreated).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    assetId: event.args.assetId,
    asset: assetAddress,
    subscriptionPrice: event.args.subscriptionPrice,
    tokenAddress: tokenAddress,
    owner: owner,
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("AssetRegistry:OwnershipTransferred", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  await context.db.insert(AssetRegistry_OwnershipTransferred).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    previousOwner: event.args.previousOwner.toLowerCase(),
    newOwner: event.args.newOwner.toLowerCase(),
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("AssetRegistry:RegistryFeeShareUpdated", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  await context.db.insert(AssetRegistry_RegistryFeeShareUpdated).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    newRegistryFeeShare: event.args.newRegistryFeeShare,
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("AssetRegistry:RegistryFeeClaimedBatch", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  await context.db.insert(AssetRegistry_RegistryFeeClaimedBatch).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    assetId: event.args.assetId,
    totalAmount: event.args.totalAmount,
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});


// ============================================================================
// Asset Handlers (Dynamic Contracts)
// ============================================================================

ponder.on("Asset:SubscriptionAdded", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.log.address.toLowerCase();
  const subscriber = event.args.subscriber;
  const payer = event.args.payer.toLowerCase();

  const assetEntityId = getAssetEntityId(chainId, assetAddress);
  const id = getSubscriptionId(chainId, assetAddress, subscriber);

  // Fetch existing subscription to preserve continuity of startTime
  const existingSub = await context.db.find(Subscription, { id });

  let computedStartTime = event.args.startTime;

  // When the contract creates a new nonce (terms changed mid-subscription),
  // it sets startTime = previous subscription's endTime, chaining them seamlessly.
  // We detect this and preserve the original startTime to show unbroken continuity.
  // Pure extensions (same terms) are handled by SubscriptionExtended instead.
  if (existingSub && existingSub.endTime === event.args.startTime) {
    computedStartTime = existingSub.startTime;
  }

  // 1. Upsert Subscription using correct Drizzle syntax
  await context.db.insert(Subscription).values({
    id: id,
    chainId: chainId,
    assetId: assetEntityId,
    subscriber: subscriber,
    payer: payer,
    startTime: event.args.startTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    isActive: true,
  }).onConflictDoUpdate({
    startTime: computedStartTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    payer: payer,
    isActive: true,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionAdded).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    subscriber: subscriber,
    payer: payer,
    startTime: event.args.startTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionExtended", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.log.address.toLowerCase();
  const subscriber = event.args.subscriber;

  // 1. Update State: extend the subscription end time
  await context.db.update(Subscription, { id: `${chainId}_${assetAddress}_${subscriber}` }).set({
    endTime: event.args.endTime,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionExtended).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    subscriber: subscriber,
    endTime: event.args.endTime,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:CreatorFeeClaimed", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  await context.db.insert(Asset_CreatorFeeClaimed).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    subscriber: event.args.subscriber,
    amount: event.args.amount,
    assetAddress: event.log.address.toLowerCase(),
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionRevoked", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.log.address.toLowerCase();
  const subscriber = event.args.subscriber;

  // 1. Update State: Mark as inactive
  await context.db.update(Subscription, { id: `${chainId}_${assetAddress}_${subscriber}` }).set({
    isActive: false,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionRevoked).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    subscriber: subscriber,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionCancelled", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.log.address.toLowerCase();
  const subscriber = event.args.subscriber;

  // 1. Update State: Mark as inactive
  await context.db.update(Subscription, { id: `${chainId}_${assetAddress}_${subscriber}` }).set({
    isActive: false,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionCancelled).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    subscriber: subscriber,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionPriceUpdated", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  await context.db.insert(Asset_SubscriptionPriceUpdated).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    newSubscriptionPrice: event.args.newSubscriptionPrice,
    assetAddress: event.log.address.toLowerCase(),
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:OwnershipTransferred", async ({ event, context }) => {
  const chainId = context.chain?.id as number;
  const assetAddress = event.log.address.toLowerCase();
  const newOwner = event.args.newOwner.toLowerCase();

  // 1. Update the mutable Asset Entity (if exists)
  try {
    await context.db.update(AssetEntity, { id: `${chainId}_${assetAddress}` }).set({
      owner: newOwner,
    });
  } catch (e: any) {
    // If the AssetEntity doesn't exist (e.g., event emitted in constructor before registry created it), skip update.
    // The AssetCreated event will set the correct initial state.
    if (!e.message?.includes('No existing record found')) {
      throw e;
    }
  }

  // 2. Log History
  await context.db.insert(Asset_OwnershipTransferred).values({
    id: getEventId(event, chainId),
    chainId: chainId,
    previousOwner: event.args.previousOwner.toLowerCase(),
    newOwner: newOwner,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});
