#!/bin/bash

source ./scripts/utils.sh

source_environment $1
if [ $? -eq 0 ]; then
    shift 1
fi

token_address=$(get_token_address)

to=$1
amount=$2

result=$(cast send $token_address "mint(address,uint256)" $to $amount --rpc-url $RPC_URL --private-key $(get_private_key 0) --json)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

echo "Address: $token_address
To: $to
Amount: $amount
Transaction Hash: $transaction_hash"