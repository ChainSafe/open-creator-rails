#!/bin/bash

source ./scripts/utils.sh

registry_index=$1
asset_id=$(cast keccak "$2")
subscriber_id=$3    
subscriber_private_key=$4

registry_address=$(get_address $registry_index)

asset_address=$(cast call $registry_address "getAsset(bytes32)(address)" $asset_id --rpc-url $RPC_URL --from $(get_wallet_address 0))

signed_cancel=$(forge script scripts/Utils.s.sol:UtilsScript --sig "signCancel(string,address,uint256)" "$subscriber_id" $asset_address $subscriber_private_key --rpc-url $RPC_URL --private-key $(get_private_key 0) --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

signature=$(echo $signed_cancel | jq -r '.returns.signature.value')
subscriber=$(echo $signed_cancel | jq -r '.returns.subscriber.value')

result=$(cast send $asset_address "cancelSubscription(string,bytes)" "$subscriber_id" $signature --rpc-url $RPC_URL --private-key $subscriber_private_key --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

subscription=$(cast call $asset_address "getSubscriptionExpiration(bytes32)(uint256)" $subscriber --rpc-url $RPC_URL --from $(get_wallet_address 0) --json)
subscription_date=$(date -d @$(echo "$subscription" | jq -r '.[0]'))

echo "Asset Registry: $registry_address
Asset Address: $asset_address
Asset ID: $2
Subscriber ID: $subscriber_id
Subscriber: $subscriber
Subscription Expiration: $subscription_date
Transaction Hash: $transaction_hash"
