#!/bin/bash

source ./scripts/utils.sh

source_environment $1
if [ $? -eq 0 ]; then
    shift 1
fi

registry_index=$1
asset_id=$(cast keccak "$2")
subscriber=$3
registry_owner_private_key=$4

registry_address=$(get_address $registry_index)

asset_address=$(cast call $registry_address "getAsset(bytes32)(address)" $asset_id --rpc-url $RPC_URL --from $(get_wallet_address 0))

token_address=$(cast call $asset_address "getTokenAddress()(address)" --rpc-url $RPC_URL --from $(get_wallet_address 0))
token_symbol=$(cast call $token_address "symbol()(string)" --rpc-url $RPC_URL | tr -d '"')
token_decimals=$(cast call $token_address "decimals()(uint8)" --rpc-url $RPC_URL)

result=$(cast send $registry_address "claimRegistryFee(bytes32,bytes32)" $asset_id $subscriber --rpc-url $RPC_URL --private-key $registry_owner_private_key --json)
EXIT_CODE=$?
cooldown

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi

transaction_hash=$(echo $result | jq -r '.transactionHash')

# RegistryFeeClaimed(bytes32 indexed assetId, bytes32 indexed subscriber, uint256 amount, uint256 claimedAtTimestamp, uint256 claimedAtNonce)
# amount is the first of three non-indexed fields — first 32 bytes (64 hex chars) of data
event_sig=$(cast keccak "RegistryFeeClaimed(bytes32,bytes32,uint256,uint256,uint256)")
log_data=$(echo $result | jq -r --arg sig "$event_sig" '.logs[] | select(.topics[0] == $sig) | .data')
amount_hex="0x${log_data:2:64}"
claimed_amount=$(cast --to-dec "$amount_hex")
claimed_formatted=$(awk "BEGIN { printf \"%g\", $claimed_amount / (10 ^ $token_decimals) }")

echo "Asset Registry: $registry_address
Asset ID: $2
Subscriber: $subscriber
Claimed: $claimed_formatted $token_symbol
Transaction Hash: $transaction_hash"
