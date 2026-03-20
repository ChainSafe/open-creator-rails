#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./scripts/utils.sh

registry_fee_share=$1

shift 1

result=$(./scripts/deploy.sh "AssetRegistry" $registry_fee_share)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

address=$(echo "$result" | jq -r '.deployedTo')

owner=$(cast call $address "owner()(address)" --rpc-url $RPC_URL --private-key $PRIVATE_KEY)

deployments_file=$(get_deployments_file)

# Add the new deployment to the deployments file
jq --arg address "$address" \
   --argjson registryFeeShare "$registry_fee_share" \
   --arg owner "$owner" \
   '. += [{address: $address, registryFeeShare: $registryFeeShare, owner: $owner, assets: []}]' \
   "$deployments_file" > tmp.json && mv tmp.json "$deployments_file"

echo "AssetRegistry: $address
Details:
  Owner: $owner
  Registry Fee Share: $registry_fee_share"