#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./script/utils.sh

creator_fee_share=$1
registry_fee_share=$2

shift 2

result=$(./script/deploy.sh "AssetRegistry" $creator_fee_share $registry_fee_share)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

address=$(echo "$result" | jq -r '.deployedTo')

owner=$(cast call $address "owner()(address)" --rpc-url $RPC_URL --private-key $PRIVATE_KEY)

deployments_file=$(get_deployments_file)

# Add the new deployment to the deployments file
jq --arg address "$address" \
   --argjson creatorFeeShare "$creator_fee_share" \
   --argjson registryFeeShare "$registry_fee_share" \
   --arg owner "$owner" \
   '. += [{address: $address, creatorFeeShare: $creatorFeeShare, registryFeeShare: $registryFeeShare, owner: $owner, assets: []}]' \
   "$deployments_file" > tmp.json && mv tmp.json "$deployments_file"

echo "AssetRegistry: $address
Details:
  Owner: $owner
  Creator Fee Share: $creator_fee_share
  Registry Fee Share: $registry_fee_share"