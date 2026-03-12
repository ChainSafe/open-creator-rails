#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./script/utils.sh

result=$(./script/deploy.sh "TestToken")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

address=$(echo "$result" | jq -r '.deployedTo')

chain_id=$(cast chain-id --rpc-url $RPC_URL)

file_name="token_addresses.json"

if [ ! -f $file_name ]; then
    echo "{}" > $file_name
fi

jq --arg chainId "$chain_id" \
   --arg address "$address" \
'.[$chainId] = $address' \
$file_name > tmp.json && mv tmp.json $file_name

echo "TestToken: $address
Chain ID: $chain_id"