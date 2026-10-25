#!/usr/bin/env bash
# Mezo testnet addresses and shared helpers, sourced by the other scripts
# STAGING=1 points everything at the private MUSD copy from staging/ instead of Mezo's live system
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# CI passes keys as environment variables instead of a .env file
set -a
[ -f "$ROOT/.env" ] && source "$ROOT/.env"
set +a

RPC="${RPC_URL:-https://rpc.test.mezo.org}"
EXPLORER=https://explorer.test.mezo.org

BTC=0x7b7C000000000000000000000000000000000000
ROUTER=0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9
POOL_FACTORY=0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A

if [ -n "${STAGING:-}" ]; then
    source "$ROOT/deployments/staging.env"
    MUSD=$STAGING_MUSD
    BORROWER_OPS=$STAGING_BORROWER_OPS
    TROVE_MANAGER=$STAGING_TROVE_MANAGER
    PRICE_FEED=$STAGING_PRICE_FEED
    HINT_HELPERS=$STAGING_HINT_HELPERS
    SORTED_TROVES=$STAGING_SORTED_TROVES
    PCV=$STAGING_PCV
    SMUSD=$STAGING_SMUSD
    # Mezo's voter has no gauge for the staging sMUSD copy, so staging vaults run without a sleeve
    VOTER=0x0000000000000000000000000000000000000000
    VAULT_FILE="$ROOT/deployments/staging-vault.env"
    LOG="${LOG:-$ROOT/deployments/staging-log.md}"
else
    MUSD=0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
    BORROWER_OPS=0xCdF7028ceAB81fA0C6971208e83fa7872994beE5
    TROVE_MANAGER=0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0
    PRICE_FEED=0x86bCF0841622a5dAC14A313a15f96A95421b9366
    HINT_HELPERS=0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6
    SORTED_TROVES=0x722E4D24FD6Ff8b0AC679450F3D91294607268fA
    PCV=0x4dDD70f4C603b6089c07875Be02fEdFD626b80Af
    SMUSD=0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16
    VOTER=0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D
    VAULT_FILE="$ROOT/deployments/testnet.env"
    LOG="${LOG:-$ROOT/deployments/testnet-log.md}"
fi
# A VAULT set by the caller wins, so an older deployment can still be driven
[ -z "${VAULT:-}" ] && [ -f "$VAULT_FILE" ] && source "$VAULT_FILE"
# Upkeep signs with the keeper key on the live vault, staging vaults keep the deployer as keeper
[ -z "${STAGING:-}" ] && KEEPER_KEY="${KEEPER_PK:-$DEPLOYER_PK}" || KEEPER_KEY="$DEPLOYER_PK"

# send <private key> <to> <signature> [args...] [cast flags], logs the explorer link
# Mezo's gas estimate can undershoot precompile calls, and it bills max(used, limit / 2), so pad by half
send() {
    local pk="$1"
    shift
    local hash receipt status estimate label="$2"
    # A plain value transfer has no signature to show
    [[ "$label" == *"("* ]] || label="transfer to $1"
    estimate="$(cast estimate --from "$(cast wallet address --private-key "$pk")" -r "$RPC" "$@")"
    # Mezo blocks hold 10M gas, so a padded limit above that would never be mined
    local limit=$((estimate * ${GAS_PCT:-150} / 100))
    [ "$limit" -gt "${GAS_CAP:-9500000}" ] && limit="${GAS_CAP:-9500000}"
    hash="$(cast send --async --private-key "$pk" -r "$RPC" --gas-limit "$limit" "$@" | tr -d '\r')"
    # The public RPC sometimes drops a receipt poll, so ask again rather than lose a sent transaction
    for _ in $(seq 1 12); do
        receipt="$(cast receipt "$hash" -r "$RPC" --json 2>/dev/null)" && break
        sleep 5
    done
    status="$(echo "$receipt" | jq -r .status | tr -d '\r')"
    echo "- \`$label\` $EXPLORER/tx/$hash (status $status, gas $(($(echo "$receipt" | jq -r .gasUsed | tr -d '\r'))), block $(($(echo "$receipt" | jq -r .blockNumber | tr -d '\r'))))" | tee -a "$LOG"
    [ "$status" = "0x1" ]
}

num() {
    cast call "$@" -r "$RPC" | cut -d' ' -f1
}

fmt() {
    cast from-wei "$1"
}
