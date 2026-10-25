#!/usr/bin/env bash
# Market controls for the private MUSD copy, e.g. scripts/staging.sh price 790000
# Price and rate use the repo's own test hooks, every other action is a normal user call
export STAGING=1
source "$(dirname "$0")/env.sh"

big() {
    python -c "import sys; print(int(eval(sys.argv[1])))" "$1"
}

reserves() {
    cast call "$ROUTER" 'getReserves(address,address,bool,address)(uint256,uint256)' \
        "$MUSD" "$BTC" false "$POOL_FACTORY" -r "$RPC" | cut -d' ' -f1 | tr '\n' ' '
}

action="${1:?usage: staging.sh <action> [args]}"
shift
case "$action" in
    price)
        send "$DEPLOYER_PK" "$STAGING_AGGREGATOR" 'setPrice(uint256)' "$(cast to-wei "$1")"
        ;;
    rate)
        send "$DEPLOYER_PK" "$STAGING_RATE_MANAGER" 'setInterestRateForTesting(uint16)' "$1"
        ;;
    time)
        # MockAggregator's updatedAt in unix seconds, an old time makes PriceFeed revert as stale and 0 follows the block again
        send "$DEPLOYER_PK" "$STAGING_AGGREGATOR" 'setBlockTime(uint256)' "$1"
        ;;
    trove)
        # Deployer's own trove, the other borrower every MUSD system has, args BTC and MUSD
        hint="$(cast call "$HINT_HELPERS" 'getApproxHint(uint256,uint256,uint256)(address,uint256,uint256)' \
            "$(big "$(cast to-wei "$1") * 10**20 // ($(cast to-wei "$2") + 202 * 10**18)")" 15 1 -r "$RPC" | head -1)"
        send "$DEPLOYER_PK" "$BORROWER_OPS" 'openTrove(uint256,address,address)' "$(cast to-wei "$2")" "$hint" "$hint" \
            --value "$(cast to-wei "$1")"
        ;;
    pool)
        # MUSD/BTC volatile pool on the real Mezo DEX, seeded at the oracle price, arg BTC
        pool="$(cast call "$POOL_FACTORY" 'getPool(address,address,bool)(address)' "$MUSD" "$BTC" false -r "$RPC")"
        if [ "$pool" = 0x0000000000000000000000000000000000000000 ]; then
            send "$DEPLOYER_PK" "$POOL_FACTORY" 'createPool(address,address,bool)' "$MUSD" "$BTC" false
            pool="$(cast call "$POOL_FACTORY" 'getPool(address,address,bool)(address)' "$MUSD" "$BTC" false -r "$RPC")"
        fi
        price="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
        read -r _ rb <<< "$(reserves)"
        # A drained pool keeps dust reserves at an old price, a tiny donation and sync move them to the oracle
        if [ "$rb" -gt 0 ] && [ "$rb" -lt 1000000000 ]; then
            send "$DEPLOYER_PK" "$BTC" 'transfer(address,uint256)' "$pool" 10000000000
            send "$DEPLOYER_PK" "$MUSD" 'transfer(address,uint256)' "$pool" "$(big "10**10 * $price // 10**18")"
            send "$DEPLOYER_PK" "$pool" 'sync()'
        fi
        btc="$(cast to-wei "$1")"
        musd="$(big "$btc * $price // 10**18")"
        send "$DEPLOYER_PK" "$MUSD" 'approve(address,uint256)' "$ROUTER" "$musd"
        send "$DEPLOYER_PK" "$BTC" 'approve(address,uint256)' "$ROUTER" "$btc"
        send "$DEPLOYER_PK" "$ROUTER" \
            'addLiquidity(address,address,bool,uint256,uint256,uint256,uint256,address,uint256)' \
            "$MUSD" "$BTC" false "$musd" "$btc" 0 0 "$DEPLOYER_ADDR" "$(($(date +%s) + 3600))"
        ;;
    arb)
        # Trades the pool back to the oracle price the way an arbitrageur would
        read -r rm rb <<< "$(reserves)"
        price="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
        read -r side amount <<< "$(python -c "
from math import isqrt
rm, rb, p = $rm, $rb, $price
k = rm * rb
rb_new = isqrt(k * 10**18 // p)
if rb_new > rb:
    print('BTC', (rb_new - rb) * 1004 // 1000)
else:
    print('MUSD', (isqrt(k * p // 10**18) - rm) * 1004 // 1000)
")"
        [ "$amount" -le 0 ] 2>/dev/null && exit 0
        if [ "$side" = BTC ]; then from="$BTC"; to="$MUSD"; else from="$MUSD"; to="$BTC"; fi
        send "$DEPLOYER_PK" "$from" 'approve(address,uint256)' "$ROUTER" "$amount"
        send "$DEPLOYER_PK" "$ROUTER" \
            'swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)' \
            "$amount" 0 "[($from,$to,false,$POOL_FACTORY)]" "$DEPLOYER_ADDR" "$(($(date +%s) + 3600))"
        ;;
    redeem)
        # Redeems MUSD against the lowest-ratio troves, which is how any MUSD holder hits a trove
        amount="$(cast to-wei "$1")"
        price="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
        read -r first nicr _ <<< "$(cast call "$HINT_HELPERS" \
            'getRedemptionHints(uint256,uint256,uint256)(address,uint256,uint256)' "$amount" "$price" 0 -r "$RPC" \
            | cut -d' ' -f1 | tr '\n' ' ')"
        send "$DEPLOYER_PK" "$TROVE_MANAGER" \
            'redeemCollateral(uint256,address,address,address,uint256,uint256)' "$amount" "$first" "$first" "$first" "$nicr" 0
        ;;
    liquidate)
        send "$DEPLOYER_PK" "$TROVE_MANAGER" 'liquidate(address)' "$1"
        ;;
    borrow | repay)
        # Deployer's trove, zero hints are fine with a three trove list
        amount="$(cast to-wei "$1")"
        [ "$action" = borrow ] && up=true || up=false
        [ "$action" = repay ] && send "$DEPLOYER_PK" "$MUSD" 'approve(address,uint256)' "$BORROWER_OPS" "$amount"
        send "$DEPLOYER_PK" "$BORROWER_OPS" 'adjustTrove(uint256,uint256,bool,address,address)' 0 "$amount" "$up"             0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000
        ;;
    addcoll)
        send "$DEPLOYER_PK" "$BORROWER_OPS" 'addColl(address,address)'             0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --value "$(cast to-wei "$1")"
        ;;
    chunk)
        # Largest harvest the oracle bound lets through after an arb, 0.8% of the pool's MUSD side
        read -r rm _ <<< "$(reserves)"
        send "${1:-$DEPLOYER_PK}" "$VAULT" 'harvest(uint256)' "$(big "$rm * 8 // 1000")"
        ;;
    refuses)
        # refuses '<what>' WHO '<signature>' [args], PASS when the vault rejects the call
        what="$1" who="${2}_ADDR"
        shift 2
        if out="$(cast call --from "${!who}" "$VAULT" "$@" -r "$RPC" 2>&1)"; then
            echo "- FAIL: $what (call succeeded with $out)" | tee -a "$LOG"
        else
            echo "- PASS: $what (reverted: $(echo "$out" | grep -oE 'revert[^"]*|custom error [^,]*|execution reverted[^"]*' | head -1))" | tee -a "$LOG"
        fi
        ;;
    yield)
        # Pays MUSD to every sMUSD holder through the real receiveProtocolYield, as PCV does
        amount="$(cast to-wei "$1")"
        send "$DEPLOYER_PK" "$MUSD" 'approve(address,uint256)' "$SMUSD" "$amount"
        send "$DEPLOYER_PK" "$SMUSD" 'receiveProtocolYield(uint256)' "$amount"
        ;;
    expect)
        # expect '<python expression over the snapshot>' '<what it proves>', appends PASS or FAIL to the log
        # Every read is pinned to one block, and a stale oracle falls back to the vault's last price
        blk="$(cast block-number -r "$RPC")"
        at=(-b "$blk")
        stale=False
        price="$(num "$PRICE_FEED" 'fetchPrice()(uint256)' "${at[@]}" 2>/dev/null)" \
            || { stale=True; price="$(num "$VAULT" 'lastPrice()(uint256)' "${at[@]}")"; }
        trove="$(cast call "$VAULT" 'trove()((bool,uint256,uint256))' "${at[@]}" -r "$RPC" | tr -d '()' | sed 's/\[[^]]*\]//g')"
        supply="$(num "$VAULT" 'totalSupply()(uint256)' "${at[@]}")"
        snapshot="dict(price=$price/1e18, active=$(echo "$trove" | cut -d, -f1 | xargs | sed 's/true/True/;s/false/False/'),
            coll=$(echo "$trove" | cut -d, -f2 | xargs)/1e18, debt=$(echo "$trove" | cut -d, -f3 | xargs)/1e18,
            held=($(num "$VAULT" 'savingsValue()(uint256)' "${at[@]}")+$(num "$MUSD" 'balanceOf(address)(uint256)' "$VAULT" "${at[@]}"))/1e18,
            idle=$(cast balance "$VAULT" -B "$blk" -r "$RPC")/1e18, total=$(num "$VAULT" 'totalAssets()(uint256)' "${at[@]}")/1e18,
            surplus=$(num "$STAGING_TROVE_MANAGER" 'collSurplusPool()(address)' | xargs -I{} cast call {} 'getCollateral(address)(uint256)' "$VAULT" "${at[@]}" -r "$RPC" | cut -d' ' -f1)/1e18,
            supply=$supply/1e24, cap=$(num "$TROVE_MANAGER" 'getTroveMaxBorrowingCapacity(address)(uint256)' "$VAULT" "${at[@]}")/1e18,
            recovery=$(cast call "$TROVE_MANAGER" 'checkRecoveryMode(uint256)(bool)' "$price" "${at[@]}" -r "$RPC" | sed 's/true/True/;s/false/False/'),
            alice=$(num "$VAULT" 'maxWithdraw(address)(uint256)' "$ALICE_ADDR" "${at[@]}")/1e18,
            bob=$(num "$VAULT" 'maxWithdraw(address)(uint256)' "$BOB_ADDR" "${at[@]}")/1e18)"
        snapshot="${snapshot%)}, status=$(cast call "$TROVE_MANAGER" 'getTroveStatus(address)(uint8)' "$VAULT" "${at[@]}" -r "$RPC"),
            rate=$(cast call "$TROVE_MANAGER" 'getTroveInterestRate(address)(uint16)' "$VAULT" "${at[@]}" -r "$RPC"),
            tcr=$(num "$TROVE_MANAGER" 'getTCR(uint256)(uint256)' "$price" "${at[@]}")/1e18)"
        # v6 adds the profit lock and the queue, an older vault has no queue and skips them
        if queue="$(cast call "$VAULT" 'queue()(address)' "${at[@]}" -r "$RPC" 2>/dev/null)"; then
            snapshot="${snapshot%)}, block=$blk, stale=$stale,
                recorded=$(num "$VAULT" 'recorded()(uint256)' "${at[@]}")/1e18,
                locked=$(num "$VAULT" 'lockedProfit()(uint256)' "${at[@]}")/1e18,
                gain=$(num "$VAULT" 'pendingProfit()(uint256)' "${at[@]}")/1e18,
                pps=$(num "$VAULT" 'convertToAssets(uint256)(uint256)' 1000000000000000000000000 "${at[@]}"),
                queued=$(num "$queue" 'pending()(uint256)' "${at[@]}")/1e24,
                reserved=$(num "$queue" 'reserved()(uint256)' "${at[@]}")/1e18,
                borrowing=$(cast call "$VAULT" 'borrowingEnabled()(bool)' "${at[@]}" -r "$RPC" | sed 's/true/True/;s/false/False/'),
                slip=$(num "$VAULT" 'slippageBps()(uint256)' "${at[@]}"))"
        fi
        python - "$1" "$2" "$snapshot" <<'EOF' | tee -a "$LOG"
import sys
expr, what, snap = sys.argv[1], sys.argv[2], eval(sys.argv[3])
snap["ratio"] = snap["coll"] * snap["price"] / snap["debt"] if snap["debt"] else 0
snap["owed"] = snap["debt"] - 200 if snap["active"] else 0
# Raw NAV the way the vault prices it, MUSD above the loan carries the slippage haircut
if "slip" in snap:
    btc, net, slip = snap["idle"] + snap["surplus"] + snap["coll"], snap["held"] - snap["owed"], snap["slip"] / 1e4
    snap["raw"] = btc + net * (1 - slip) / snap["price"] if net >= 0 else max(btc + net * (1 + slip) / snap["price"], 0)
ok = eval(expr, {}, snap)
shown = ", ".join(f"{k} {v:.6g}" if isinstance(v, float) else f"{k} {v}" for k, v in snap.items())
print(f"- {'PASS' if ok else 'FAIL'}: {what} ({shown})")
EOF
        ;;
    market)
        read -r rm rb <<< "$(reserves)"
        price="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
        echo "oracle $(fmt "$price") pool $(python -c "print($rm / $rb)") reserves MUSD $(fmt "$rm") BTC $(fmt "$rb")"
        echo "TCR $(python -c "print($(num "$TROVE_MANAGER" 'getTCR(uint256)(uint256)' "$price") / 1e18)") recovery $(cast call "$TROVE_MANAGER" 'checkRecoveryMode(uint256)(bool)' "$price" -r "$RPC") rate $(cast call "$STAGING_RATE_MANAGER" 'interestRate()(uint16)' -r "$RPC")"
        ;;
    *)
        echo "unknown action $action" >&2
        exit 1
        ;;
esac
