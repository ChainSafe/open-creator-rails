#!/bin/bash

if [ -f .env ]; then
    source .env
fi

source ./script/utils.sh

contract_name=$1

shift 1

constructor_args=""

if [ $# -gt 0 ]; then
    constructor_args="--constructor-args $@"
fi

forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY apps/contracts/src/$contract_name.sol:$contract_name --broadcast --json $constructor_args
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    return $EXIT_CODE 2>/dev/null || exit $EXIT_CODE
fi