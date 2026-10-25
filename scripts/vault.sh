#!/usr/bin/env bash
# One vault action per call on Mezo testnet, e.g. scripts/vault.sh deposit ALICE 0.05
source "$(dirname "$0")/env.sh"

pk() {
    local var="${1}_PK"
    echo "${!var}"
}

addr() {
    local var="${1}_ADDR"
    echo "${!var}"
}

# Owner calls on the live vault have to go through its timelock
owner_only() {
    if [ -z "${STAGING:-}" ] && [ -n "${TIMELOCK:-}" ]; then
        echo "the live vault is owned by the timelock $TIMELOCK, use scripts/timelock.sh" >&2
        exit 1
    fi
}

queue() {
    echo "${QUEUE:-$(cast call "$VAULT" 'queue()(address)' -r "$RPC")}"
}

sleeve() {
    echo "${SLEEVE:-$(cast call "$VAULT" 'sleeve()(address)' -r "$RPC")}"
}

action="${1:?usage: vault.sh <action> [args]}"
shift
case "$action" in
    deposit)
        send "$(pk "$1")" "$VAULT" 'depositBTC(address)' "$(addr "$1")" --value "$(cast to-wei "$2")"
        ;;
    deposit-erc20)
        amount="$(cast to-wei "$2")"
        send "$(pk "$1")" "$BTC" 'approve(address,uint256)' "$VAULT" "$amount"
        send "$(pk "$1")" "$VAULT" 'deposit(uint256,address)' "$amount" "$(addr "$1")"
        ;;
    withdraw)
        send "$(pk "$1")" "$VAULT" 'withdraw(uint256,address,address)' "$(cast to-wei "$2")" "$(addr "$1")" "$(addr "$1")"
        ;;
    redeem-max | withdraw-max)
        # Price and accruing interest move the max between reading and executing, so leave 0.001% of room
        what="${action%-max}"
        [ "$what" = redeem ] && view='maxRedeem(address)(uint256)' || view='maxWithdraw(address)(uint256)'
        amount="$(python -c "m = $(num "$VAULT" "$view" "$(addr "$1")"); print(m - m // 100000)")"
        send "$(pk "$1")" "$VAULT" "$what(uint256,address,address)" "$amount" "$(addr "$1")" "$(addr "$1")"
        ;;
    rebalance)
        send "$([ -n "${1:-}" ] && pk "$1" || echo "$KEEPER_KEY")" "$VAULT" 'rebalance()'
        ;;
    request)
        # Queues an exit of about this much BTC, or every share the holder has with "all"
        if [ "$2" = all ]; then
            shares="$(num "$VAULT" 'balanceOf(address)(uint256)' "$(addr "$1")")"
        else
            shares="$(num "$VAULT" 'convertToShares(uint256)(uint256)' "$(cast to-wei "$2")")"
        fi
        send "$(pk "$1")" "$(queue)" 'requestRedeem(uint256,address,address)' "$shares" \
            "$(addr "$1")" "$(addr "$1")"
        ;;
    process)
        send "$KEEPER_KEY" "$VAULT" 'processQueue(uint256)' "${1:-$(cast max-uint)}"
        ;;
    claim)
        send "$KEEPER_KEY" "$(queue)" 'claim(uint256[])' "[$1]"
        ;;
    sync)
        send "$KEEPER_KEY" "$VAULT" 'sync()'
        ;;
    roll)
        send "$KEEPER_KEY" "$VAULT" 'roll()'
        ;;
    sleeve)
        owner_only
        send "$DEPLOYER_PK" "$(sleeve)" 'setSleeve(uint16,uint256,uint8)' "$1" "${3:-$(cast max-uint)}" "$2"
        ;;
    sleeve-pause)
        send "$GUARDIAN_PK" "$(sleeve)" 'setPaused(bool)' true
        ;;
    pause)
        send "$GUARDIAN_PK" "$VAULT" 'pauseBorrowing()'
        ;;
    harvest)
        send "$KEEPER_KEY" "$VAULT" 'harvest(uint256)' "${1:-$(cast max-uint)}"
        ;;
    distribute)
        send "$DEPLOYER_PK" "$PCV" 'distributeMUSD()'
        ;;
    params)
        owner_only
        send "$DEPLOYER_PK" "$VAULT" 'setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)' \
            "$(cast to-wei "$1")" "$(cast to-wei "$2")" "$(cast to-wei "$3")" "$4" "$5" "$6" "${7:-$(cast max-uint)}"
        ;;
    unwind)
        send "$GUARDIAN_PK" "$VAULT" 'unwind()'
        ;;
    fund)
        send "$DEPLOYER_PK" "$(addr "$1")" --value "$(cast to-wei "$2")"
        ;;
    borrowing)
        owner_only
        send "$DEPLOYER_PK" "$VAULT" 'setBorrowingEnabled(bool)' "$1"
        ;;
    *)
        echo "unknown action $action" >&2
        exit 1
        ;;
esac
