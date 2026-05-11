#!/bin/bash

if [ -f .env.local ]; then
    source .env.local
    
    anvil &
    ANVIL_PID=$!
    
    cleanup() {
        kill "$ANVIL_PID" 2>/dev/null || true
    }

    trap cleanup EXIT
elif [ -f .env ]; then
    source .env
fi

source ./scripts/utils.sh

./scripts/deployTestToken.sh

token_address=$(get_token_address)

registry_fee_share=30
registry_owner_private_key=$(get_private_key 0)

./scripts/deployRegistry.sh $registry_fee_share $registry_owner_private_key

registry_index=0

asset_id_0="default_asset_id_0"
subscription_price_0=1
subscription_duration_0=1
owner_0=$(get_wallet_address 1)

./scripts/createAsset.sh $registry_index $asset_id_0 $subscription_price_0 $subscription_duration_0 $token_address $owner_0 $registry_owner_private_key

asset_id_1="default_asset_id_1"
subscription_price_1=$((10 ** 6)) # 10 TEST
subscription_duration_1=$((30 * 24 * 60 * 60)) # 30 days
owner_1=$(get_wallet_address 2)

./scripts/createAsset.sh $registry_index $asset_id_1 $subscription_price_1 $subscription_duration_1 $token_address $owner_1 $registry_owner_private_key

asset_id_2="default_asset_id_2"
subscription_price_2=$((2 * 10 ** 6)) # 20 TEST
subscription_duration_2=$((90 * 24 * 60 * 60)) # 90 days
owner_2=$(get_wallet_address 3)

./scripts/createAsset.sh $registry_index $asset_id_2 $subscription_price_2 $subscription_duration_2 $token_address $owner_2 $registry_owner_private_key

subscriber_address_0=$(get_wallet_address 4)
subscriber_address_1=$(get_wallet_address 5)
subscriber_address_2=$(get_wallet_address 6)
subscriber_address_3=$(get_wallet_address 7)
subscriber_address_4=$(get_wallet_address 8)
subscriber_address_5=$(get_wallet_address 9)

./scripts/mintTestToken.sh $subscriber_address_0 1000000000 # 1000 TEST
./scripts/mintTestToken.sh $subscriber_address_1 1000000000 # 1000 TEST
./scripts/mintTestToken.sh $subscriber_address_2 1000000000 # 1000 TEST
./scripts/mintTestToken.sh $subscriber_address_3 1000000000 # 1000 TEST
./scripts/mintTestToken.sh $subscriber_address_4 1000000000 # 1000 TEST
./scripts/mintTestToken.sh $subscriber_address_5 1000000000 # 1000 TEST

subscriber_private_key_0=$(get_private_key 4)
subscriber_private_key_1=$(get_private_key 5)
subscriber_private_key_2=$(get_private_key 6)
subscriber_private_key_3=$(get_private_key 7)
subscriber_private_key_4=$(get_private_key 8)
subscriber_private_key_5=$(get_private_key 9)

subscriber_id_0="default_subscriber_id_0"
subscriber_id_1="default_subscriber_id_1"
subscriber_id_2="default_subscriber_id_2"
subscriber_id_3="default_subscriber_id_3"
subscriber_id_4="default_subscriber_id_4"
subscriber_id_5="default_subscriber_id_5"

./scripts/subscribe.sh $registry_index $asset_id_0 $subscriber_id_0 $subscriber_address_0 600 $subscriber_private_key_0 # 10 Minutes
./scripts/subscribe.sh $registry_index $asset_id_0 $subscriber_id_1 $subscriber_address_1 86400 $subscriber_private_key_1 # 1 Day

./scripts/subscribe.sh $registry_index $asset_id_1 $subscriber_id_2 $subscriber_address_2 1 $subscriber_private_key_2 # 1 Month
./scripts/subscribe.sh $registry_index $asset_id_1 $subscriber_id_3 $subscriber_address_3 2 $subscriber_private_key_3 # 2 Months

./scripts/subscribe.sh $registry_index $asset_id_2 $subscriber_id_4 $subscriber_address_4 1 $subscriber_private_key_4 # 3 Months
./scripts/subscribe.sh $registry_index $asset_id_2 $subscriber_id_5 $subscriber_address_5 4 $subscriber_private_key_5 # 1 Year

# Keep Anvil Running (only if it was started by this script)
if [ -n "$ANVIL_PID" ]; then
    wait $ANVIL_PID
fi