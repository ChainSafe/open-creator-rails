#!/bin/bash

if [ -f .env ]; then
    source .env
fi

FILE_NAME=$1

SCRIPT_NAME="${FILE_NAME}Script"

SIGNATURE=$2

shift 2

OUTPUT=$(forge script script/$FILE_NAME.s.sol:$SCRIPT_NAME $@ --sig "$SIGNATURE" --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    exit $EXIT_CODE
fi

echo "$OUTPUT"