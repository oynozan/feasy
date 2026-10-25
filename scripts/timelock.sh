#!/usr/bin/env bash
# Owner calls on the live vault through its 24 hour timelock, e.g. scripts/timelock.sh schedule 'setBorrowingEnabled(bool)' false
# TARGET=$SLEEVE sends the call to the vault's sleeve instead, which takes the vault owner's word too
source "$(dirname "$0")/env.sh"

action="${1:?usage: timelock.sh schedule|execute|status <signature> [args]}"
shift
data="$(cast calldata "$@")"
target="${TARGET:-$VAULT}"
# The timelock refuses an operation id twice, so set SALT to repeat a call that already ran
salt="${SALT:-$(cast keccak "$data")}"
zero=0x0000000000000000000000000000000000000000000000000000000000000000

case "$action" in
    schedule)
        delay="$(num "$TIMELOCK" 'getMinDelay()(uint256)')"
        send "$DEPLOYER_PK" "$TIMELOCK" 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)' \
            "$target" 0 "$data" "$zero" "$salt" "$delay"
        echo "executable after $(date -u -d "@$(($(date +%s) + delay))" +%FT%TZ)"
        ;;
    execute)
        send "$DEPLOYER_PK" "$TIMELOCK" 'execute(address,uint256,bytes,bytes32,bytes32)' \
            "$target" 0 "$data" "$zero" "$salt"
        ;;
    status)
        id="$(cast call "$TIMELOCK" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' \
            "$target" 0 "$data" "$zero" "$salt" -r "$RPC")"
        echo "operation $id ready_at $(num "$TIMELOCK" 'getTimestamp(bytes32)(uint256)' "$id")" \
            "ready $(cast call "$TIMELOCK" 'isOperationReady(bytes32)(bool)' "$id" -r "$RPC")" \
            "done $(cast call "$TIMELOCK" 'isOperationDone(bytes32)(bool)' "$id" -r "$RPC")"
        ;;
    *)
        echo "unknown action $action" >&2
        exit 1
        ;;
esac
