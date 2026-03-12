if [ -f .env ]; then
    source .env
fi

function get_deployments_file() {
    chain_id=$(cast chain-id --rpc-url $RPC_URL)

    file_name="registries_$chain_id.json"

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

function get_token_address() {
    chain_id=$(cast chain-id --rpc-url $RPC_URL)
    file_name="token_addresses.json"

    result=$(jq -r ".[\"$chain_id\"]" "$file_name")
    echo $result
}