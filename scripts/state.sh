#!/usr/bin/env bash
# Prints the vault's live state on Mezo testnet
source "$(dirname "$0")/env.sh"

PRICE="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
TROVE="$(cast call "$VAULT" 'trove()((bool,uint256,uint256))' -r "$RPC")"
ACTIVE="$(echo "$TROVE" | tr -d '()' | cut -d, -f1)"
COLL="$(echo "$TROVE" | tr -d '()' | cut -d, -f2 | xargs | cut -d' ' -f1)"
DEBT="$(echo "$TROVE" | tr -d '()' | cut -d, -f3 | xargs | cut -d' ' -f1)"
ASSETS="$(num "$VAULT" 'totalAssets()(uint256)')"
SUPPLY="$(num "$VAULT" 'totalSupply()(uint256)')"
SAVINGS="$(num "$VAULT" 'savingsValue()(uint256)')"
IDLE_MUSD="$(num "$MUSD" 'balanceOf(address)(uint256)' "$VAULT")"
IDLE="$(cast balance "$VAULT" -r "$RPC")"
IDLE_TOKEN="$(num "$BTC" 'balanceOf(address)(uint256)' "$VAULT")"

echo "price        $(fmt "$PRICE") USD/BTC"
echo "idle BTC     $(fmt "$IDLE") (BTC token view $(fmt "$IDLE_TOKEN"))"
echo "trove        active=$ACTIVE coll=$(fmt "$COLL") debt=$(fmt "$DEBT")"
if [ "$DEBT" != "0" ]; then
    echo "ratio        $(python -c "print(round($COLL * $PRICE / $DEBT / 1e18, 4))")"
fi
echo "savings      $(fmt "$SAVINGS") MUSD, idle MUSD $(fmt "$IDLE_MUSD")"
echo "totalAssets  $(fmt "$ASSETS") BTC"
# The unlock and the queue exist from v6 on, older vaults skip these lines
if PROFIT="$(cast call "$VAULT" 'profit()(uint128,uint64,uint64)' -r "$RPC" 2>/dev/null)"; then
    END="$(echo "$PROFIT" | sed -n 3p | cut -d' ' -f1)"
    echo "unlocking    $(fmt "$(num "$VAULT" 'lockedProfit()(uint256)')") BTC until $(date -u -d "@$END" +%FT%TZ), pending $(fmt "$(num "$VAULT" 'pendingProfit()(uint256)')") BTC"
    QUEUE="$(cast call "$VAULT" 'queue()(address)' -r "$RPC")"
    STATE="$(cast call "$QUEUE" 'queueState()(uint256,uint256,uint256,uint256)' -r "$RPC" | cut -d' ' -f1 | tr '\n' ' ')"
    read -r QUEUED FILLED RESERVED REQUESTS <<< "$STATE"
    echo "queue        $QUEUE, $REQUESTS requests, $(python -c "print($QUEUED - $FILLED)") shares waiting, $(fmt "$RESERVED") BTC to claim"
    echo "borrowing    $(cast call "$VAULT" 'borrowingEnabled()(bool)' -r "$RPC"), guardian $(cast call "$VAULT" 'guardian()(address)' -r "$RPC")"
fi
# The veBTC sleeve exists from v7 on
SLEEVE="$(cast call "$VAULT" 'sleeve()(address)' -r "$RPC" 2>/dev/null || true)"
if [ -n "$SLEEVE" ] && [ "$SLEEVE" != 0x0000000000000000000000000000000000000000 ]; then
    echo "sleeve       $SLEEVE, $(fmt "$(num "$SLEEVE" 'principal()(uint256)')") BTC locked," \
        "$(num "$SLEEVE" 'sleeveBps()(uint16)') bps, $(num "$SLEEVE" 'lockWeeks()(uint8)') weeks," \
        "paused $(cast call "$SLEEVE" 'paused()(bool)' -r "$RPC"), live $(cast call "$SLEEVE" 'live()(bool)' -r "$RPC")"
    for i in 0 1 2 3; do
        RUNG="$(cast call "$SLEEVE" 'rungs(uint256)(uint256,uint128,uint64)' "$i" -r "$RPC" | cut -d' ' -f1 | tr '\n' ' ')"
        read -r ID AMOUNT END <<< "$RUNG"
        [ "$ID" = "0" ] && continue
        echo "rung $i       veBTC $ID, $(fmt "$AMOUNT") BTC until $(date -u -d "@$END" +%FT%TZ)"
    done
fi
if [ "$SUPPLY" != "0" ]; then
    echo "share price  $(python -c "print('%.12f' % ($ASSETS * 1e6 / $SUPPLY))") BTC per 1e18 shares"
fi
for who in ALICE BOB DEPLOYER; do
    addr_var="${who}_ADDR"
    shares="$(num "$VAULT" 'balanceOf(address)(uint256)' "${!addr_var}")"
    [ "$shares" = "0" ] && continue
    echo "$who        $(fmt "$(num "$VAULT" 'convertToAssets(uint256)(uint256)' "$shares")") BTC, max withdraw $(fmt "$(num "$VAULT" 'maxWithdraw(address)(uint256)' "${!addr_var}")")"
done
