#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./scripts/utils.sh

registry_index=$1

asset_id=$(cast keccak "$2")
subscription_price=$3
token_address=$4
owner=$5

receipt=$(cast send $(get_address $registry_index) "createAsset(bytes32,uint256,address,address)" $asset_id $subscription_price $token_address $owner --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

address=$(echo "$receipt" | jq -r '.logs[0].address')

deployments_file=$(get_deployments_file)

# Add the new asset to the deployments file in assets array for the registry
jq --argjson registryIndex "$registry_index" \
   --arg address "$address" \
   --arg assetId "$2" \
   --arg assetIdHash "$asset_id" \
   --argjson subscriptionPrice "$subscription_price" \
   --arg tokenAddress "$token_address" \
   --arg owner "$owner" \
   '.[$registryIndex].assets += [{address: $address, assetId: $assetId, assetIdHash: $assetIdHash, subscriptionPrice: $subscriptionPrice, tokenAddress: $tokenAddress, owner: $owner}]' \
   "$deployments_file" > tmp.json && mv tmp.json "$deployments_file"

echo "Asset: $address
Details:
  Asset ID: $2
  Asset ID Hash: $asset_id
  Subscription Price: $subscription_price
  Token Address: $token_address
  Owner: $owner"