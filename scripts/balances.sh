#!/usr/bin/env bash
# Prints BTC and MUSD balances of every wallet in .env on Mezo testnet
source "$(dirname "$0")/env.sh"
for var in $(grep -o '^[A-Z0-9_]*_ADDR' "$ROOT/.env"); do
    addr="${!var}"
    echo "${var%_ADDR} $addr BTC=$(cast balance "$addr" -r "$RPC" -e) MUSD=$(fmt "$(num "$MUSD" 'balanceOf(address)(uint256)' "$addr")")"
done
