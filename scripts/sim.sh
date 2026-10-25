#!/usr/bin/env bash
# Full Wave 1 loop on Mezo testnet with real transactions, explorer links go to deployments/testnet-log.md
# Run as scripts/sim.sh <alice BTC> <bob BTC>, together they must clear the ~0.077 BTC a trove needs
source "$(dirname "$0")/env.sh"
ALICE_AMOUNT="${1:-0.06}"
BOB_AMOUNT="${2:-0.03}"
S="$ROOT/scripts"

step() {
    printf '\n### %s\n' "$*" | tee -a "$LOG"
}

step "Top up Alice and Bob from the deployer to their deposit plus a little gas"
for who in ALICE BOB; do
    amount_var="${who}_AMOUNT"
    addr_var="${who}_ADDR"
    short="$(python -c "print(max(0, ${!amount_var} + 0.0002 - $(cast balance "${!addr_var}" -r "$RPC" -e)))")"
    [ "$short" != "0" ] && bash "$S/vault.sh" fund "$who" "$short"
done

step "Testnet params, 4% slippage because the testnet pool sits ~2.6% under the oracle"
bash "$S/vault.sh" params 2 2.5 3 300 400 200

step "Alice deposits $ALICE_AMOUNT BTC as native BTC"
bash "$S/vault.sh" deposit ALICE "$ALICE_AMOUNT"

step "Bob deposits $BOB_AMOUNT BTC through the ERC-20 path"
bash "$S/vault.sh" deposit-erc20 BOB "$BOB_AMOUNT"

step "Bob calls rebalance, anyone can, it opens the trove"
bash "$S/vault.sh" rebalance BOB
bash "$S/state.sh" | tee -a "$LOG"

step "Push protocol fees into sMUSD, then harvest"
bash "$S/vault.sh" distribute
bash "$S/vault.sh" harvest
bash "$S/state.sh" | tee -a "$LOG"

step "Rebalance moves the harvested BTC into the trove"
bash "$S/vault.sh" rebalance
bash "$S/state.sh" | tee -a "$LOG"

step "Bob redeems what he can in BTC, his slice of the MUSD cushion waits for the final harvest"
bash "$S/vault.sh" redeem-max BOB
bash "$S/state.sh" | tee -a "$LOG"

step "Alice redeems her max, which closes the trove"
bash "$S/vault.sh" redeem-max ALICE
bash "$S/state.sh" | tee -a "$LOG"

step "With the trove closed, the leftover MUSD is sold and both redeem the rest"
bash "$S/vault.sh" harvest
bash "$S/vault.sh" redeem-max BOB
bash "$S/vault.sh" redeem-max ALICE
bash "$S/state.sh" | tee -a "$LOG"
bash "$S/balances.sh" | tee -a "$LOG"
