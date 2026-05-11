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