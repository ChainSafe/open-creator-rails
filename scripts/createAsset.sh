#!/bin/bash

source ./scripts/utils.sh

source_environment $1
if [ $? -eq 0 ]; then
    shift 1
fi

registry_index=$1

asset_id=$(cast keccak "$2")
subscription_price=$3
subscription_duration=$4
token_address=$5
owner=$6
registry_owner_private_key=$7

receipt=$(cast send $(get_address $registry_index) "createAsset(bytes32,uint256,uint256,address,address)" $asset_id $subscription_price $subscription_duration $token_address $owner --rpc-url $RPC_URL --private-key $registry_owner_private_key --json)
EXIT_CODE=$?
cooldown

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
   --argjson subscriptionDuration "$subscription_duration" \
   --arg tokenAddress "$token_address" \
   --arg owner "$owner" \
   '.[$registryIndex].assets += [{address: $address, assetId: $assetId, assetIdHash: $assetIdHash, subscriptionPrice: $subscriptionPrice, subscriptionDuration: $subscriptionDuration, tokenAddress: $tokenAddress, owner: $owner}]' \
   "$deployments_file" > tmp.json && mv tmp.json "$deployments_file"

echo "Asset: $address
Details:
  Asset ID: $2
  Asset ID Hash: $asset_id
  Subscription Price: $subscription_price
  Subscription Duration: $subscription_duration
  Token Address: $token_address
  Owner: $owner"
