#!/usr/bin/env bash
# Runs every Preflight scenario against live Mezo testnet state, one eth_call each
source "$(dirname "$0")/env.sh"
cd "$ROOT/contracts"
# The harness deploys its own vault, which links the SystemMath library already live on testnet
LIB="src/SystemMath.sol:SystemMath:$(grep '^SYSTEM_MATH=' "$ROOT/deployments/testnet.env" | cut -d= -f2)"
forge build --silent --libraries "$LIB"
CODE_FILE="$(mktemp)"
forge inspect script/Preflight.sol:Preflight deployedBytecode --libraries "$LIB" > "$CODE_FILE"
NAMES=("open" "harvest" "withdraw via trove" "redeem max (close)" "deposit more, borrow" "band repay" "unwind" "erc20 deposit" "small vault, withdraw pins min loan" "small vault, withdraw closes" "two users, yield" "rebalance closes small trove" "erc4626 mint and redeem" "close unfillable at 1% slippage" "rebalance cannot close, repays" "150 BTC vault, big exit at target" "150 BTC vault, big exit to the debt floor" "chunked harvest" "pro rata exits when a close cannot be bought" "stranger cannot harvest an open trove" "inflation attack by donation" "payout snipe closed" "snipe after close, MUSD left" "donation is locked" "continuity at sync" "continuity at rebalance" "continuity at harvest" "depositBTC and deposit priced at the views" "mint and withdraw priced at the views" "redeem and processQueue priced at the views" "exact maxDeposit" "exact maxMint" "exact maxWithdraw" "exact maxRedeem" "loss netting" "queue fill through the trove" "queue order and partial fills" "dust request" "budget: processQueue through the trove" "budget: processQueue closing the trove" "budget: claim 16 ids" "budget: bootstrap roll" "rebate claim, stale vs checkpointed veBTC")
for id in "${!NAMES[@]}"; do
    [ -n "${1:-}" ] && [ "$1" != "$id" ] && continue
    echo "##### scenario $id: ${NAMES[$id]}"
    python "$ROOT/scripts/preflight.py" "$RPC" "$CODE_FILE" "$id" || true
done
