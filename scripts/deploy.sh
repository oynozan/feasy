#!/usr/bin/env bash
# Deploys SystemMath, the savings sleeve and the vault linked to it on Mezo testnet
# DEPLOYER becomes owner, KEEPER the keeper and GUARDIAN the guardian
# OUT_FILE picks the env file, UNLOCK_PERIOD shortens a test copy's unlock, VOTER=0x0 skips the sleeve
# VAULT_KEEPER names another keeper, such as the deployer while the Action still keeps the old vault
source "$(dirname "$0")/env.sh"
mkdir -p "$ROOT/deployments"
OUT_FILE="${OUT_FILE:-$ROOT/deployments/testnet-v8.env}"
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
    # The code is there but no hash came back, the block is then found from the code itself
    [ "$(cast codesize "$ADDR" -r "$RPC")" -gt 0 ] && { echo "no hash for $1 at $ADDR" >&2; return 0; }
    echo "$1 did not deploy at $ADDR" >&2
    echo "$out" >&2
    return 1
}

# The first block with code at an address, a binary search over the archive node
created_at() {
    local lo=$(($(cast block-number -r "$RPC") - 20000)) hi mid
    hi="$(cast block-number -r "$RPC")"
    while [ $((hi - lo)) -gt 1 ]; do
        mid=$(((lo + hi) / 2))
        if [ "$(cast codesize "$1" -B "$mid" -r "$RPC")" -gt 0 ]; then hi=$mid; else lo=$mid; fi
    done
    echo "$hi"
}

# REUSE_SYSTEM_MATH picks up a library an earlier, interrupted run already deployed
if [ -n "${REUSE_SYSTEM_MATH:-}" ]; then
    SYSTEM_MATH="$REUSE_SYSTEM_MATH"
else
    create src/SystemMath.sol:SystemMath
    SYSTEM_MATH="$ADDR"
fi
LIB="src/SystemMath.sol:SystemMath:$SYSTEM_MATH"
# The vault comes right after its savings sleeve, so the sleeve is built with that address
PREDICTED="$(cast compute-address "$DEPLOYER_ADDR" \
    --nonce "$(($(cast nonce "$DEPLOYER_ADDR" -r "$RPC") + 1))" | awk '{print $NF}')"
SAVINGS_ARGS=("$PREDICTED" "$SMUSD" "$BTC" "$BORROWER_OPS" "$VOTER" "$ROUTER" "$POOL_FACTORY")
create src/SavingsSleeve.sol:SavingsSleeve --libraries "$LIB" --constructor-args "${SAVINGS_ARGS[@]}"
SAVINGS_SLEEVE="$ADDR"
ARGS=("$BTC" "$BORROWER_OPS" "$HINT_HELPERS" "$SMUSD" "$ROUTER" "$POOL_FACTORY" "${VAULT_KEEPER:-$KEEPER_ADDR}"
    "$GUARDIAN_ADDR" "${UNLOCK_PERIOD:-604800}" "$VOTER" "$SAVINGS_SLEEVE" "Feasy BTC" "fBTC")
create src/Vault.sol:Vault --libraries "$LIB" --constructor-args "${ARGS[@]}"
VAULT="$ADDR"
[ "$VAULT" = "$PREDICTED" ] || { echo "vault landed at $VAULT, the sleeve expects $PREDICTED" >&2; exit 1; }
QUEUE="$(cast call "$VAULT" 'queue()(address)' -r "$RPC")"
SLEEVE="$(cast call "$VAULT" 'sleeve()(address)' -r "$RPC")"
BLOCK="$([ -n "$HASH" ] && cast receipt "$HASH" blockNumber -r "$RPC" || created_at "$VAULT")"
VAULT_HASH="$HASH"
# The booster reads the vault's sleeve and Mezo Earn, so it needs a vault with a voter
BOOSTER=0x0000000000000000000000000000000000000000
if [ "$VOTER" != 0x0000000000000000000000000000000000000000 ]; then
    create src/Booster.sol:Booster --libraries "$LIB" --constructor-args "$VAULT"
    BOOSTER="$ADDR"
fi
printf 'VAULT=%s\nQUEUE=%s\nSLEEVE=%s\nSAVINGS_SLEEVE=%s\nBOOSTER=%s\nSYSTEM_MATH=%s\nVAULT_BLOCK=%s\n' \
    "$VAULT" "$QUEUE" "$SLEEVE" "$SAVINGS_SLEEVE" "$BOOSTER" "$SYSTEM_MATH" "$BLOCK" > "$OUT_FILE"
echo "- Vault deployed $EXPLORER/address/$VAULT (queue $QUEUE, sleeve $SLEEVE, savings sleeve" \
    "$SAVINGS_SLEEVE, booster $BOOSTER, SystemMath $SYSTEM_MATH, block $BLOCK)" \
    "tx $EXPLORER/tx/$VAULT_HASH" | tee -a "$LOG"

forge verify-contract "$SYSTEM_MATH" src/SystemMath.sol:SystemMath --chain-id 31611 --verifier sourcify \
    || echo "SystemMath verification failed, retry later with the same command"
forge verify-contract "$VAULT" src/Vault.sol:Vault --chain-id 31611 --verifier sourcify --libraries "$LIB" \
    --constructor-args "$(cast abi-encode \
    'c(address,address,address,address,address,address,address,address,uint256,address,address,string,string)' \
    "${ARGS[@]}")" || echo "vault verification failed, retry later with the same command"
forge verify-contract "$SAVINGS_SLEEVE" src/SavingsSleeve.sol:SavingsSleeve --chain-id 31611 \
    --verifier sourcify --libraries "$LIB" --constructor-args "$(cast abi-encode \
    'c(address,address,address,address,address,address,address)' "${SAVINGS_ARGS[@]}")" \
    || echo "savings sleeve verification failed, retry later with the same command"
[ "$BOOSTER" != 0x0000000000000000000000000000000000000000 ] && { forge verify-contract "$BOOSTER" \
    src/Booster.sol:Booster --chain-id 31611 --verifier sourcify --libraries "$LIB" \
    --constructor-args "$(cast abi-encode 'c(address)' "$VAULT")" \
    || echo "booster verification failed, retry later with the same command"; }
# Linking puts the library into every contract's metadata, so the children need it too
forge verify-contract "$QUEUE" src/RedeemQueue.sol:RedeemQueue --chain-id 31611 --verifier sourcify \
    --libraries "$LIB" --constructor-args "$(cast abi-encode 'c(address)' "$BTC")" \
    || echo "queue verification failed, retry later with the same command"
[ "$VOTER" = 0x0000000000000000000000000000000000000000 ] && exit 0
forge verify-contract "$SLEEVE" src/VeSleeve.sol:VeSleeve --chain-id 31611 --verifier sourcify \
    --libraries "$LIB" --constructor-args \
    "$(cast abi-encode 'c(address,address,address,address)' "$VOTER" "$BTC" "$MUSD" "$SMUSD")" \
    || echo "sleeve verification failed, retry later with the same command"
