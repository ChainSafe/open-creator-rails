#!/bin/bash

source ./scripts/utils.sh

source_environment $1
if [ $? -eq 0 ]; then
    shift 1
fi

registry_index=$1
asset_id=$(cast keccak "$2")
subscriber=$3
asset_owner_private_key=$4

registry_address=$(get_address $registry_index)

asset_address=$(cast call $registry_address "getAsset(bytes32)(address)" $asset_id --rpc-url $RPC_URL --from $(get_wallet_address 0))

result=$(cast send $asset_address "revokeSubscription(bytes32)" $subscriber --rpc-url $RPC_URL --private-key $asset_owner_private_key --json)
EXIT_CODE=$?
cooldown

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

subscription=$(cast call $asset_address "getSubscriptionExpiration(bytes32)(uint256)" $subscriber --rpc-url $RPC_URL --from $(get_wallet_address 0) --json)
subscription_date=$(date -d @$(echo "$subscription" | jq -r '.[0]'))
revoked=$(cast call $asset_address "isSubscriberRevoked(bytes32)(bool)" $subscriber --rpc-url $RPC_URL --from $(get_wallet_address 0) --json | jq -r '.[0]')

echo "Asset Address: $asset_address
Asset ID: $2
Subscriber: $subscriber
Subscription Expiration: $subscription_date
Revoked: $revoked
Transaction Hash: $transaction_hash"
