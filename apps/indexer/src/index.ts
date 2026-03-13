import { ponder } from "ponder:registry";
import { 
  AssetEntity, 
  Subscription, 
  AssetRegistry_AssetCreated,
  AssetRegistry_OwnershipTransferred,
  AssetRegistry_CreatorFeeShareUpdated,
  AssetRegistry_RegistryFeeShareUpdated,
  Asset_SubscriptionAdded,
  Asset_SubscriptionRevoked,
  Asset_SubscriptionPriceUpdated,
  Asset_OwnershipTransferred
} from "../ponder.schema";

// Helper function to generate robust IDs if event.log.id is missing
const getEventId = (event: any) => {
  return `${event.transaction.hash}-${event.log.logIndex}`;
};

// ============================================================================
// AssetRegistry Handlers
// ============================================================================

ponder.on("AssetRegistry:AssetCreated", async ({ event, context }) => {
  const assetAddress = event.args.asset.toLowerCase();
  const owner = event.args.owner.toLowerCase();
  const tokenAddress = event.args.tokenAddress.toLowerCase();

  // 1. Create the persistent Asset Entity
  await context.db.insert(AssetEntity).values({
    id: assetAddress,
    assetId: event.args.assetId,
    registryAddress: event.log.address,
    owner: owner,
  });

  // 2. Log immutable history
  await context.db.insert(AssetRegistry_AssetCreated).values({
    id: getEventId(event),
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
  await context.db.insert(AssetRegistry_OwnershipTransferred).values({
    id: getEventId(event),
    previousOwner: event.args.previousOwner.toLowerCase(),
    newOwner: event.args.newOwner.toLowerCase(),
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("AssetRegistry:CreatorFeeShareUpdated", async ({ event, context }) => {
  await context.db.insert(AssetRegistry_CreatorFeeShareUpdated).values({
    id: getEventId(event),
    newCreatorFeeShare: event.args.newCreatorFeeShare,
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("AssetRegistry:RegistryFeeShareUpdated", async ({ event, context }) => {
  await context.db.insert(AssetRegistry_RegistryFeeShareUpdated).values({
    id: getEventId(event),
    newRegistryFeeShare: event.args.newRegistryFeeShare,
    registryAddress: event.log.address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});


// ============================================================================
// Asset Handlers (Dynamic Contracts)
// ============================================================================

ponder.on("Asset:SubscriptionAdded", async ({ event, context }) => {
  const assetAddress = event.log.address.toLowerCase(); 
  const user = event.args.user.toLowerCase();

  const id = `${assetAddress}_${user}`;
  
  // Fetch existing subscription to accurately conditionally update startTime
  const existingSub = await context.db.find(Subscription, { id });

  let computedStartTime = event.args.startTime;

  // If the user previously had a subscription, and they topped up while it was still active,
  // the contract rigidly sets the new event's startTime to equal the previous subscription's endTime.
  // We check for this exact match to safely preserve their original unbroken start time.
  if (existingSub && existingSub.endTime === event.args.startTime) {
    computedStartTime = existingSub.startTime;
  }

  // 1. Upsert Subscription using correct Drizzle syntax
  await context.db.insert(Subscription).values({
    id: id,
    assetId: assetAddress,
    user: user,
    startTime: event.args.startTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    isActive: true,
  }).onConflictDoUpdate({
    startTime: computedStartTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    isActive: true,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionAdded).values({
    id: getEventId(event),
    user: user,
    startTime: event.args.startTime,
    endTime: event.args.endTime,
    nonce: event.args.nonce,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionRevoked", async ({ event, context }) => {
  const assetAddress = event.log.address.toLowerCase();
  const user = event.args.user.toLowerCase();

  // 1. Update State: Mark as inactive
  await context.db.update(Subscription, { id: `${assetAddress}_${user}` }).set({
    isActive: false,
  });

  // 2. Log History
  await context.db.insert(Asset_SubscriptionRevoked).values({
    id: getEventId(event),
    user: user,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:SubscriptionPriceUpdated", async ({ event, context }) => {
  await context.db.insert(Asset_SubscriptionPriceUpdated).values({
    id: getEventId(event),
    newSubscriptionPrice: event.args.newSubscriptionPrice,
    assetAddress: event.log.address.toLowerCase(),
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});

ponder.on("Asset:OwnershipTransferred", async ({ event, context }) => {
  const assetAddress = event.log.address.toLowerCase();
  const newOwner = event.args.newOwner.toLowerCase();

  // 1. Update the mutable Asset Entity (if exists)
  try {
    await context.db.update(AssetEntity, { id: assetAddress }).set({
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
    id: getEventId(event),
    previousOwner: event.args.previousOwner.toLowerCase(),
    newOwner: newOwner,
    assetAddress: assetAddress,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
  });
});