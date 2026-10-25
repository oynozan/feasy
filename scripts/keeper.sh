#!/usr/bin/env bash
# Keeps the vault in band, pays its withdrawal queue and harvests, one check every INTERVAL seconds
# Run as scripts/keeper.sh [INTERVAL], ONCE=1 runs a single check and exits for the GitHub Action
source "$(dirname "$0")/env.sh"
INTERVAL="${1:-600}"
MIN_HARVEST="${MIN_HARVEST:-10000000000000000000}"
IDLE_SLACK_BPS="${IDLE_SLACK_BPS:-200}"

big() {
    python -c "import sys; print(int(eval(sys.argv[1])))" "$1"
}

# Pauses new locks once Mezo Earn changes, rolls when a rung matured or a lock is due
roll_sleeve() {
    local now start live paused matured=0 lock=0 id end raw hold depositor period
    now="$(cast block latest -f timestamp -r "$RPC")"
    start=$((now - now % 604800))
    live="$(cast call "$SLEEVE" 'live()(bool)' -r "$RPC")"
    paused="$(cast call "$SLEEVE" 'paused()(bool)' -r "$RPC")"
    if [ "$live" != "true" ] && [ "$paused" != "true" ]; then
        echo "Mezo Earn no longer matches the sleeve, pausing new locks"
        send "$KEEPER_KEY" "$SLEEVE" 'setPaused(bool)' true || echo "pause failed"
        paused=true
    fi
    # An upgrade of veBTC, the voter or the booster every withdraw calls also pauses new locks
    local ve impls watch
    ve="$(cast call "$SLEEVE" 've()(address)' -r "$RPC")"
    impls="$(for a in "$ve" "$(cast call "$SLEEVE" 'voter()(address)' -r "$RPC")" \
        "$(cast call "$ve" 'booster()(address)' -r "$RPC")"; do
        cast storage "$a" 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc -r "$RPC"
    done | paste -sd, -)"
    watch="$ROOT/deployments/keeper-watch-$SLEEVE.txt"
    [ -f "$watch" ] || echo "$impls" > "$watch"
    if [ "$(cat "$watch")" != "$impls" ] && [ "$paused" != "true" ]; then
        echo "Mezo Earn implementation changed, pausing new locks"
        send "$KEEPER_KEY" "$SLEEVE" 'setPaused(bool)' true || echo "pause failed"
    fi
    # Votes and resets open an hour after the Thursday flip
    [ "$now" -le $((start + 3600)) ] && return 1
    for i in 0 1 2 3; do
        id="$(cast call "$SLEEVE" 'rungs(uint256)(uint256,uint128,uint64)' "$i" -r "$RPC" | sed -n 1p | cut -d' ' -f1)"
        end="$(cast call "$SLEEVE" 'rungs(uint256)(uint256,uint128,uint64)' "$i" -r "$RPC" | sed -n 3p | cut -d' ' -f1)"
        [ "$id" != "0" ] && [ "$end" -le "$now" ] && matured=1
    done
    # A rebate claim reverts until Mezo's weekly period update, which anyone may run, the sleeve waits a day at most
    depositor="$(cast call "$(cast call "$SLEEVE" 'distributor()(address)' -r "$RPC")" 'depositor()(address)' -r "$RPC")"
    period="$(num "$depositor" 'activePeriod()(uint256)')"
    if [ "$period" -lt "$start" ]; then
        send "$KEEPER_KEY" "$depositor" 'updatePeriod()' \
            && period="$(num "$depositor" 'activePeriod()(uint256)')" || echo "period update failed"
    fi
    [ "$period" -lt "$start" ] && [ "$now" -lt $((start + 86400)) ] && matured=0
    raw="$(cast call "$VAULT" 'rawAssets()(uint256)' -r "$RPC" 2>/dev/null | cut -d' ' -f1 || num "$VAULT" 'totalAssets()(uint256)')"
    hold="$(num "$SLEEVE" 'hold(uint256)(uint256)' "${raw:-$ASSETS}")"
    if [ "$PENDING" = "0" ] && [ "$RECOVERY" != "true" ] && [ "$now" -le $((start + 604800 - 3600)) ] \
        && [ "$(big "$hold >= $(num "$SLEEVE" 'MIN_RUNG()(uint256)')")" = "1" ]; then
        lock=1
    fi
    [ "$matured" = "0" ] && [ "$lock" = "0" ] && return 1
    # A rebate claim paying veBTC's weekly catch-up outruns its gas budget, so catch veBTC up first
    send "$KEEPER_KEY" "$ve" 'checkpoint()' || echo "veBTC checkpoint failed"
    bash "$ROOT/scripts/vault.sh" roll || { echo "roll failed"; return 1; }
    # A lock that was due and did not happen is retried next pass, the BTC stays idle and liquid
    [ "$lock" = "1" ] && [ "$(big "$(num "$SLEEVE" 'hold(uint256)(uint256)' "${raw:-$ASSETS}") >= $hold")" = "1" ] \
        && echo "roll ran but locked nothing"
    return 0
}

while true; do
    PRICE="$(num "$PRICE_FEED" 'fetchPrice()(uint256)')"
    TROVE="$(cast call "$VAULT" 'trove()((bool,uint256,uint256))' -r "$RPC" | tr -d '()' | sed 's/\[[^]]*\]//g')"
    ACTIVE="$(echo "$TROVE" | cut -d, -f1 | xargs)"
    COLL="$(echo "$TROVE" | cut -d, -f2 | xargs)"
    DEBT="$(echo "$TROVE" | cut -d, -f3 | xargs)"
    IDLE="$(cast balance "$VAULT" -r "$RPC")"
    ASSETS="$(num "$VAULT" 'totalAssets()(uint256)')"
    BUFFER_BPS="$(num "$VAULT" 'bufferBps()(uint256)')"
    MIN_CR="$(num "$VAULT" 'minCR()(uint256)')"
    MAX_CR="$(num "$VAULT" 'maxCR()(uint256)')"
    MIN_DEBT="$(big "$(num "$BORROWER_OPS" 'minNetDebt()(uint256)') + 200 * 10**18")"
    HELD="$(big "$(num "$VAULT" 'savingsValue()(uint256)') + $(num "$MUSD" 'balanceOf(address)(uint256)' "$VAULT")")"
    BORROWING="$(cast call "$VAULT" 'borrowingEnabled()(bool)' -r "$RPC")"
    RECOVERY="$(cast call "$TROVE_MANAGER" 'checkRecoveryMode(uint256)(bool)' "$PRICE" -r "$RPC")"
    MAX_RATE="$(num "$VAULT" 'maxBorrowRate()(uint16)')"
    RATE="$(num "$(num "$BORROWER_OPS" 'interestRateManager()(address)')" 'interestRate()(uint16)')"
    TROVE_RATE="$(num "$TROVE_MANAGER" 'getTroveInterestRate(address)(uint16)' "$VAULT")"
    CAP="$(num "$TROVE_MANAGER" 'getTroveMaxBorrowingCapacity(address)(uint256)' "$VAULT")"
    QUEUE="$(cast call "$VAULT" 'queue()(address)' -r "$RPC")"
    PENDING="$(num "$QUEUE" 'pending()(uint256)')"
    PENDING_PROFIT="$(num "$VAULT" 'pendingProfit()(uint256)')"

    OWED="$([ "$ACTIVE" = "true" ] && big "$DEBT - 200 * 10**18" || echo 0)"
    # Harvest only sells above the vault's 0.1% cushion over what the loan owes
    SURPLUS="$(big "$HELD - $OWED - $OWED // 1000")"

    # Rebalance has work when the ratio leaves the band, idle BTC can open or top up the trove, or MUSD runs short
    # Above the band or opening counts only if the vault can borrow, as the contract checks, so a capped trove is left alone
    REBALANCE="$(python -c "
coll, debt, price, idle, assets = $COLL, $DEBT, $PRICE, $IDLE, $ASSETS
recovery = '$RECOVERY' == 'true'
can_borrow = '$BORROWING' == 'true' and not recovery and $RATE <= $MAX_RATE
spare = 0 if recovery else idle - assets * ($BUFFER_BPS + $IDLE_SLACK_BPS) // 10000
if debt:
    ratio = coll * price // debt
    grow = can_borrow and ($CAP - debt > debt // 100 or $TROVE_RATE >= $RATE)
    work = ratio < $MIN_CR or (ratio > $MAX_CR and grow) or spare > 0 or $HELD + 10**18 < $OWED
else:
    work = can_borrow and spare * price // $MAX_CR >= $MIN_DEBT
print(1 if work else 0)")"

    echo "$(date -u +%FT%TZ) ratio=$(python -c "print(round($COLL * $PRICE / $DEBT / 1e18, 4) if $DEBT else 0)") idle=$(fmt "$IDLE") surplus=$(python -c "print($SURPLUS / 1e18)") queued=$PENDING pendingProfit=$(fmt "$PENDING_PROFIT")"
    CHECKPOINTED=""
    # Waiting requests go first, a request holds back borrowing until it is paid
    if [ "$PENDING" != "0" ]; then
        bash "$ROOT/scripts/vault.sh" process && CHECKPOINTED=1 || echo "process failed"
    fi
    if [ "$(big "$SURPLUS > $MIN_HARVEST")" = "1" ]; then
        bash "$ROOT/scripts/vault.sh" harvest && CHECKPOINTED=1 || echo "harvest failed"
    fi
    if [ "$REBALANCE" = "1" ]; then
        bash "$ROOT/scripts/vault.sh" rebalance && CHECKPOINTED=1 || echo "rebalance failed"
    fi
    # Pays filled requests to their receivers, 16 ids a transaction
    # ponytail: scans every request id, keep a cursor once the queue holds hundreds of requests
    if [ "$(num "$QUEUE" 'reserved()(uint256)')" != "0" ]; then
        READY="$(for id in $(seq 1 "$(num "$QUEUE" 'requestCount()(uint256)')"); do
            [ "$(num "$QUEUE" 'claimableRedeem(uint256)(uint256)' "$id")" != "0" ] && echo "$id"
        done | head -16 | paste -sd, -)"
        [ -n "$READY" ] && { bash "$ROOT/scripts/vault.sh" claim "$READY" || echo "claim failed"; }
    fi
    # The weekly veBTC roll, only on vaults that have a sleeve
    SLEEVE="$(cast call "$VAULT" 'sleeve()(address)' -r "$RPC" 2>/dev/null || true)"
    if [ -n "$SLEEVE" ] && [ "$SLEEVE" != "0x0000000000000000000000000000000000000000" ]; then
        roll_sleeve && CHECKPOINTED=1
    fi
    # Every entry point checkpoints, so sync only when none ran and a gain above 1 bp waits
    if [ -z "$CHECKPOINTED" ] && [ "$(big "$PENDING_PROFIT * 10000 > $ASSETS")" = "1" ]; then
        bash "$ROOT/scripts/vault.sh" sync || echo "sync failed"
    fi
    [ -n "${ONCE:-}" ] && break
    sleep "$INTERVAL"
done
