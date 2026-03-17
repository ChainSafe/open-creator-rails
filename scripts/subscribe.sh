#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./scripts/utils.sh

registry_index=$1
asset_id=$(cast keccak "$2")
subscriber=$(cast keccak "$3")
value=$4
payer_private_key=$5

registry_address=$(get_address $registry_index)

# Asset address is the spender for the permit
spender=$(cast call $registry_address "getAsset(bytes32)(address)" $asset_id --rpc-url $RPC_URL --private-key $PRIVATE_KEY)

# 30 minutes
duration=1800

token_address=$(cast call $spender "getTokenAddress()(address)" --rpc-url $RPC_URL --private-key $PRIVATE_KEY)

signed_permit=$(forge script apps/contracts/script/Utils.s.sol:UtilsScript --sig "signPermit(uint256,address,uint256,address,uint256)" $value $spender $duration $token_address $payer_private_key --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

v=$(echo $signed_permit | jq -r '.returns.v.value')
r=$(echo $signed_permit | jq -r '.returns.r.value')
s=$(echo $signed_permit | jq -r '.returns.s.value')
deadline=$(echo $signed_permit | jq -r '.returns.deadline.value')
payer=$(echo $signed_permit | jq -r '.returns.owner.value')

result=$(cast send $registry_address "subscribe(bytes32,bytes32,address,address,uint256,uint256,uint8,bytes32,bytes32)" $asset_id $subscriber $payer $spender $value $deadline $v $r $s --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

subscription=$(cast call $registry_address "getSubscription(bytes32,bytes32)(uint256)" $asset_id $subscriber --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json)

# Convert subscription (Unix timestamp) to human readable date
subscription_date=$(date -d @$(echo $subscription | jq -r '.[0]'))

echo "Asset Registry: $registry_address
Asset ID: $2
Subscriber: $3
payer: $payer
Subscription: $subscription_date
Transaction Hash: $transaction_hash"