#!/usr/bin/env bash
# Deploys SystemMath and the vault linked to it on Mezo testnet
# DEPLOYER becomes owner, KEEPER the keeper and GUARDIAN the guardian
# OUT_FILE picks the env file, UNLOCK_PERIOD shortens a test copy's unlock, VOTER=0x0 skips the sleeve
source "$(dirname "$0")/env.sh"
mkdir -p "$ROOT/deployments"
OUT_FILE="${OUT_FILE:-$ROOT/deployments/testnet-v7.env}"
# Resolved before the build moves into contracts, so a relative path means the caller's directory
OUT_FILE="$(cd "$(dirname "$OUT_FILE")" && pwd)/$(basename "$OUT_FILE")"
cd "$ROOT/contracts"

# Sets ADDR and HASH, waiting for the code since the RPC sometimes drops forge's receipt poll
create() {
    ADDR="$(cast compute-address "$DEPLOYER_ADDR" --nonce "$(cast nonce "$DEPLOYER_ADDR" -r "$RPC")" \
        | awk '{print $NF}')"
    local out
    out="$(forge create --broadcast -r "$RPC" --private-key "$DEPLOYER_PK" "$@" 2>&1 || true)"
    HASH="$(echo "$out" | sed -n 's/.*Transaction hash: *\(0x[0-9a-fA-F]*\).*/\1/p')"
    for _ in $(seq 1 24); do
        [ "$(cast codesize "$ADDR" -r "$RPC")" -gt 0 ] && [ -n "$HASH" ] && return 0
        [ -z "$HASH" ] && HASH="$(curl -s -A "curl/8.9.1" \
            "https://api.explorer.test.mezo.org/api/v2/addresses/$ADDR" | jq -r '.creation_tx_hash // empty')"
        sleep 5
    done
    echo "$1 did not deploy at $ADDR" >&2
    echo "$out" >&2
    return 1
}

ARGS=("$BTC" "$BORROWER_OPS" "$HINT_HELPERS" "$SMUSD" "$ROUTER" "$POOL_FACTORY" "$KEEPER_ADDR"
    "$GUARDIAN_ADDR" "${UNLOCK_PERIOD:-604800}" "$VOTER" "Feasy BTC" "fBTC")
create src/SystemMath.sol:SystemMath
SYSTEM_MATH="$ADDR"
LIB="src/SystemMath.sol:SystemMath:$SYSTEM_MATH"
create src/Vault.sol:Vault --libraries "$LIB" --constructor-args "${ARGS[@]}"
VAULT="$ADDR"
QUEUE="$(cast call "$VAULT" 'queue()(address)' -r "$RPC")"
SLEEVE="$(cast call "$VAULT" 'sleeve()(address)' -r "$RPC")"
BLOCK="$(cast receipt "$HASH" blockNumber -r "$RPC")"
printf 'VAULT=%s\nQUEUE=%s\nSLEEVE=%s\nSYSTEM_MATH=%s\nVAULT_BLOCK=%s\n' \
    "$VAULT" "$QUEUE" "$SLEEVE" "$SYSTEM_MATH" "$BLOCK" > "$OUT_FILE"
echo "- Vault deployed $EXPLORER/address/$VAULT (queue $QUEUE, sleeve $SLEEVE, SystemMath $SYSTEM_MATH," \
    "block $BLOCK) tx $EXPLORER/tx/$HASH" | tee -a "$LOG"

forge verify-contract "$SYSTEM_MATH" src/SystemMath.sol:SystemMath --chain-id 31611 --verifier sourcify \
    || echo "SystemMath verification failed, retry later with the same command"
forge verify-contract "$VAULT" src/Vault.sol:Vault --chain-id 31611 --verifier sourcify --libraries "$LIB" \
    --constructor-args "$(cast abi-encode \
    'c(address,address,address,address,address,address,address,address,uint256,address,string,string)' \
    "${ARGS[@]}")" || echo "vault verification failed, retry later with the same command"
# Linking puts the library into every contract's metadata, so the children need it too
forge verify-contract "$QUEUE" src/RedeemQueue.sol:RedeemQueue --chain-id 31611 --verifier sourcify \
    --libraries "$LIB" --constructor-args "$(cast abi-encode 'c(address)' "$BTC")" \
    || echo "queue verification failed, retry later with the same command"
[ "$VOTER" = 0x0000000000000000000000000000000000000000 ] && exit 0
forge verify-contract "$SLEEVE" src/VeSleeve.sol:VeSleeve --chain-id 31611 --verifier sourcify \
    --libraries "$LIB" --constructor-args \
    "$(cast abi-encode 'c(address,address,address,address)' "$VOTER" "$BTC" "$MUSD" "$SMUSD")" \
    || echo "sleeve verification failed, retry later with the same command"
