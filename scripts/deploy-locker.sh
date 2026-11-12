#!/usr/bin/env bash
# Deploys BtcLocker on Mezo testnet, which deploys its MezoLocker, the deployer is owner and guardian
# TREASURY takes the protocol fee and is the deployer when unset, the ladder votes for Mezo's sMUSD gauge
# The locker keeps its own log beside the vault's
LOG="${LOG:-$(cd "$(dirname "$0")/.." && pwd)/deployments/testnet-locker-log.md}"
source "$(dirname "$0")/env.sh"
OUT_FILE="${OUT_FILE:-$ROOT/deployments/testnet-locker.env}"
OUT_FILE="$(cd "$(dirname "$OUT_FILE")" && pwd)/$(basename "$OUT_FILE")"
TREASURY="${TREASURY:-$DEPLOYER_ADDR}"
cd "$ROOT/contracts"

ADDR="$(cast compute-address "$DEPLOYER_ADDR" --nonce "$(cast nonce "$DEPLOYER_ADDR" -r "$RPC")" | awk '{print $NF}')"
OUT="$(forge create --broadcast -r "$RPC" --private-key "$DEPLOYER_PK" src/BtcLocker.sol:BtcLocker \
    --constructor-args "$VOTER" "$BTC" "$MUSD" "$SMUSD" "$TREASURY" 2>&1 || true)"
HASH="$(echo "$OUT" | sed -n 's/.*Transaction hash: *\(0x[0-9a-fA-F]*\).*/\1/p')"
# The RPC sometimes drops forge's receipt poll, so the code itself is the proof
for _ in $(seq 1 24); do
    [ "$(cast codesize "$ADDR" -r "$RPC")" -gt 0 ] && break
    sleep 5
done
[ "$(cast codesize "$ADDR" -r "$RPC")" -gt 0 ] || { echo "BtcLocker did not deploy at $ADDR" >&2; echo "$OUT" >&2; exit 1; }
[ -z "$HASH" ] && HASH="$(curl -s -A "curl/8.9.1" \
    "https://api.explorer.test.mezo.org/api/v2/addresses/$ADDR" | jq -r '.creation_tx_hash // empty')"
BLOCK="$(cast receipt "$HASH" blockNumber -r "$RPC" 2>/dev/null || curl -s -A "curl/8.9.1" \
    "https://api.explorer.test.mezo.org/api/v2/transactions/$HASH" | jq -r '.block_number')"
MEZO_LOCKER="$(cast call "$ADDR" 'mezoLocker()(address)' -r "$RPC")"

printf 'LOCKER=%s\nMEZO_LOCKER=%s\nLOCKER_BLOCK=%s\nTREASURY=%s\n' "$ADDR" "$MEZO_LOCKER" "$BLOCK" "$TREASURY" \
    > "$OUT_FILE"
echo "- Liquid locker deployed: BtcLocker (fveBTC) $EXPLORER/address/$ADDR, MezoLocker (fveMEZO)" \
    "$EXPLORER/address/$MEZO_LOCKER, block $BLOCK, tx $EXPLORER/tx/$HASH" | tee -a "$LOG"
