#!/bin/bash

if [ -f .env ]; then
    source .env
fi

# Parse flags
FORCE_DEPLOY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

CONTRACT_NAME=$1
CONSTRUCTOR_TYPES=${2:-""}

if [ -z "$CONSTRUCTOR_TYPES" ]; then
    shift 1
else
    shift 2
fi

DEPLOYMENTS_FILE="deployments.json"

if [ -f "$DEPLOYMENTS_FILE" ] && [ "$FORCE_DEPLOY" = false ]; then
    DEPLOYED_ADDRESS=$(jq -r --arg name "$CONTRACT_NAME" '.[$name]' "$DEPLOYMENTS_FILE")
    if [ ! -z "$DEPLOYED_ADDRESS" ]; then
        # Rebuild the contract to get the latest bytecode
        BUILD_OUTPUT=$(forge build 2>&1)
        if [ $? -ne 0 ]; then
            echo "$BUILD_OUTPUT" >&2
            exit 1
        fi
        # Get bytecode
        BYTECODE=$(jq -r '.deployedBytecode.object' "out/${CONTRACT_NAME}.sol/${CONTRACT_NAME}.json")
        # Get deployed bytecode
        DEPLOYED_BYTECODE=$(cast code $DEPLOYED_ADDRESS --rpc-url $RPC_URL)

        # Compare bytecodes
        if [ "$BYTECODE" == "$DEPLOYED_BYTECODE" ]; then
            echo "$DEPLOYED_ADDRESS"
            exit 0
        fi
    fi
fi

OUTPUT=$(forge script script/Deploy.s.sol:DeployScript "src/$CONTRACT_NAME.sol:$CONTRACT_NAME" $(cast abi-encode "constructor($CONSTRUCTOR_TYPES)" $@) --sig "deploy(string,bytes)" --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY)
EXIT_CODE=$?

# Check if deploy.sh failed
if [ $EXIT_CODE -ne 0 ]; then
    exit $EXIT_CODE
fi

DEPLOYED_ADDRESS=$(echo "$OUTPUT" | awk '/deployedAddress: address/ {print $3}')

# Check if we successfully extracted an address
if [ -z "$DEPLOYED_ADDRESS" ]; then
    echo "Error: Failed to extract deployedAddress" >&2
    exit 1
fi

# Create DEPLOYMENTS_FILE if it doesn't exist
if [ ! -f "$DEPLOYMENTS_FILE" ]; then
    echo "{}" > "$DEPLOYMENTS_FILE"
fi

# Update deployments.json with the contract name and address
jq --arg name "$CONTRACT_NAME" --arg address "$DEPLOYED_ADDRESS" '. + {($name): $address}' "$DEPLOYMENTS_FILE" > "${DEPLOYMENTS_FILE}.tmp" && mv "${DEPLOYMENTS_FILE}.tmp" "$DEPLOYMENTS_FILE"

# Print/return the deployed address
echo "$DEPLOYED_ADDRESS"