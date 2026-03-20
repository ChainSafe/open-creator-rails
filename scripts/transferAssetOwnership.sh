#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./scripts/utils.sh

registry_index=$1
asset_id=$(cast keccak $2)
asset_owner_private_key=$3
new_owner=$4

deployments_file=$(get_deployments_file)

asset_address=$(jq -r ".[$registry_index].assets[] | select(.assetIdHash == \"$asset_id\") | .address" "$deployments_file")

result=$(cast send $asset_address "transferOwnership(address)" $new_owner --rpc-url $RPC_URL --private-key $asset_owner_private_key --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

jq --argjson registryIndex "$registry_index" \
   --arg assetIdHash "$asset_id" \
   --arg newOwner "$new_owner" \
   '.[$registryIndex].assets |= map(if .assetIdHash == $assetIdHash then .owner = $newOwner else . end)' \
   "$deployments_file" > tmp.json && mv tmp.json "$deployments_file"

echo "Asset ID: $2
Details:
  Owner: $new_owner
  Transaction Hash: $transaction_hash"