#!/usr/bin/env bash
# Weekly upkeep of the liquid locker, every call is open to anyone so any funded key can run it
# roll claims and releases, gauges opens boost gauges for new rungs, boost votes veMEZO, harvest pays fveMEZO
# LOCKER_PK signs, the deployer's key when unset, so a local run never uses the Action's keeper key
# The locker keeps its own log beside the vault's
LOG="${LOG:-$(cd "$(dirname "$0")/.." && pwd)/deployments/testnet-locker-log.md}"
source "$(dirname "$0")/env.sh"
source "$ROOT/deployments/testnet-locker.env"
KEY="${LOCKER_PK:-$DEPLOYER_PK}"
# Mezo Earn's epoch flips Thursday at midnight UTC, votes open an hour later and close an hour early
WEEK=604800

roll() {
    send "$KEY" "$LOCKER" 'roll()'
}

gauges() {
    for i in 0 1 2 3; do
        local id end
        id="$(cast call "$LOCKER" 'rungs(uint256)(uint256,uint128,uint64)' "$i" -r "$RPC" | sed -n 1p | cut -d' ' -f1)"
        end="$(cast call "$LOCKER" 'rungs(uint256)(uint256,uint128,uint64)' "$i" -r "$RPC" | sed -n 3p | cut -d' ' -f1)"
        [ "$id" = 0 ] && continue
        [ "$end" -le "$(date +%s)" ] && continue
        local booster gauge
        booster="$(cast call "$(cast call "$LOCKER" 've()(address)' -r "$RPC")" 'booster()(address)' -r "$RPC")"
        gauge="$(cast call "$booster" 'boostableTokenIdToGauge(uint256)(address)' "$id" -r "$RPC")"
        [ "$gauge" != 0x0000000000000000000000000000000000000000 ] && continue
        # Opening a gauge measured about 2.5M gas, above what Mezo's estimate returns
        GAS_PCT=200 send "$KEY" "$LOCKER" 'addBoostGauge(uint256,address)' "$i" "$BOOST_GAUGE_FACTORY"
    done
}

boost() {
    local now start
    now="$(date +%s)"
    start=$((now - now % WEEK))
    if [ $((now - start)) -le 3600 ] || [ $((start + WEEK - now)) -le 3600 ]; then
        echo "outside Mezo's voting window, boost waits" >&2
        return 0
    fi
    # Mezo allows one veMEZO vote an epoch, a second call reverts and is skipped
    send "$KEY" "$MEZO_LOCKER" 'boost()' || echo "boost already voted this epoch" >&2
}

harvest() {
    send "$KEY" "$MEZO_LOCKER" 'harvest()'
}

case "${1:-all}" in
    roll) roll ;;
    gauges) gauges ;;
    boost) boost ;;
    harvest) harvest ;;
    all)
        roll
        gauges
        boost
        harvest
        ;;
    *)
        echo "usage: locker.sh [roll|gauges|boost|harvest|all]" >&2
        exit 1
        ;;
esac
