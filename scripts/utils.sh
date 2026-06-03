target_dir="deployments"

function get_wallet_address() {
    echo $(cast wallet address --mnemonic "$MNEMONIC" --mnemonic-index $1)
}

function get_private_key() {
    echo $(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $1)
}

function get_deployments_file() {
    chain_id=$(cast chain-id --rpc-url $RPC_URL)
    
    # Point to the config package from the root folder
    mkdir -p $target_dir
    
    file_name="$target_dir/registries_$chain_id.json"

    if [ ! -f $file_name ]; then
        echo "[]" > $file_name
    fi

    echo $file_name
}

function get_address() {
    registry_index=$1
    asset_index=$2

    file_name=$(get_deployments_file)

    local path=".[$registry_index]"
    [ -n "$asset_index" ] && path+=".assets[$asset_index]"
    
    result=$(jq -r "$path.address" "$file_name")
    
    echo $result
}

function get_token_addresses_file() {
    mkdir -p $target_dir
    echo "$target_dir/token_addresses.json"
}

function get_token_address() {
    chain_id=$(cast chain-id --rpc-url $RPC_URL)
    
    file_name=$(get_token_addresses_file)

    result=$(jq -r ".[\"$chain_id\"]" "$file_name")
    echo $result
}

function source_environment() {
    if [ ! $SOURCE_SCRIPT ]; then
        
        environment=$1
    
        if [ -f "$environment" ]; then
            # shellcheck source=./.env.local
            source "$PROJECT_ROOT/$environment"

            if [ "$environment" == ".env.local" ]; then
                anvil &
                ANVIL_PID=$!
                until nc -z -w 1 127.0.0.1 8545; do :; done
            fi

            export SOURCE_SCRIPT=true

            return 0
        fi
    else
        return 1
    fi
}

function encode_subscriber() {
    subscriber_id=$1
    subscriber_address=$2

    echo $(cast keccak "$(cast abi-encode "f(string,address)" "$subscriber_id" "$subscriber_address")")
}

function cooldown() {
    sleep "${COOLDOWN:-0}"
}