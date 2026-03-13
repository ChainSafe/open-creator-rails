#!/bin/bash

# Default Anvil arguments
export RPC_URL="http://127.0.0.1:8545"
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo "Waiting for Anvil to start..."
while ! cast chain-id --rpc-url $RPC_URL > /dev/null 2>&1; do
  sleep 1
done

echo "Anvil is up! Sowing local deployments..."

echo "1. Deploying Test Token..."
./script/deployTestToken.sh

echo "2. Deploying Registry (80% Creator / 20% Registry)..."
./script/deployRegistry.sh 80 20

echo "3. Creating Demo Assets..."
TOKEN_ADDR=$(jq -r '.["31337"]' packages/config/src/deployments/token_addresses.json)

# Create 5 distinct assets with different prices and IDs for User 0 (Deployer)
for i in {1..5}; do
  asset_id="local_asset_$i"
  price=$((i * 2)) # Prices: 2, 4, 6, 8, 10 tokens/sec
  echo "  Creating Asset $asset_id (Price: $price)"
  ./script/createAsset.sh 0 "$asset_id" $price $TOKEN_ADDR 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 > /dev/null
done

echo "4. Distributing Test Tokens to Subscribers..."
# Mint 50,000 test tokens to Anvil account(1) to be a subscriber
./script/mintTestToken.sh 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 50000000000000000000000 > /dev/null
# Mint 50,000 test tokens to Anvil account(2) to be a subscriber
./script/mintTestToken.sh 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC 50000000000000000000000 > /dev/null

echo "5. Generating Subscriptions..."
# Anvil private keys for Account 1 and 2
SUB1_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
SUB2_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

# Subscriber 1 Subscribes to Asset 1 and 2
echo "  Subscriber 1: Subscribing to local_asset_1 for 1 hour"
./script/subscribe.sh 0 "local_asset_1" 7200 $SUB1_PK > /dev/null
echo "  Subscriber 1: Subscribing to local_asset_2 for 2 hours"
./script/subscribe.sh 0 "local_asset_2" 28800 $SUB1_PK > /dev/null

# Subscriber 2 Subscribes to Asset 3 and 1
echo "  Subscriber 2: Subscribing to local_asset_3 for 5 hours"
./script/subscribe.sh 0 "local_asset_3" 108000 $SUB2_PK > /dev/null
echo "  Subscriber 2: Subscribing to local_asset_1 for 10 hours"
./script/subscribe.sh 0 "local_asset_1" 72000 $SUB2_PK > /dev/null

# Let Subscriber 1 "Top Up" their asset 1 subscription
echo "  Subscriber 1: Topping up local_asset_1 for an additional hour"
./script/subscribe.sh 0 "local_asset_1" 7200 $SUB1_PK > /dev/null

echo "Local seeding complete! ✨ Generated 5 assets and 5 active subscriptions with top-ups."
