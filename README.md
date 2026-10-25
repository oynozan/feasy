# Feasy: BTC savings vault on Mezo

Deposit BTC, get more BTC. The vault borrows MUSD against the pooled BTC at Mezo's fixed rate, parks it in the MUSD Savings Vault (sMUSD), and swaps the savings income above the loan cost back into BTC. Your exposure stays plain BTC: the borrowed dollars sit in dollar savings, so there is no leverage on BTC.

Documentation: [docs.feasy.org](https://docs.feasy.org).

Built for the Mezo buildathon, Track 1 (DeFi). It runs on Mezo testnet. The live vault is v7 (Wave 2), which adds a veBTC sleeve that earns the sMUSD gauge's fees.

## How it works

1. You deposit BTC (native or the BTC ERC-20) and receive `fBTC` shares (ERC-4626, priced in BTC).
2. `rebalance()` opens one shared MUSD trove at a 250% collateral ratio (loan = 40% of the BTC value) and deposits the MUSD into sMUSD. It also buys back the 0.1% borrow fee with BTC, so the MUSD the vault holds always covers what the loan owes. A new vault starts with borrowing off, and the owner turns it on.
3. sMUSD pays savers from the interest and fees all MUSD borrowers pay.
4. `harvest(maxIn)` swaps the savings income above the loan cost into BTC on Mezo's DEX, keeping a 0.1% MUSD cushion against interest.
5. New profit reaches the share price over 7 days. Each share then earns its BTC at the same rate per day held, so depositing just before a payout and leaving right after earns nothing extra.
6. Part of the BTC sits in veBTC, Mezo's vote-escrowed BTC, voting for the sMUSD gauge. The gauge's MUSD fees go into savings with the rest, and Mezo's weekly BTC rebate comes back as BTC. The keeper's weekly `roll()` keeps at most four locks ending on consecutive Thursdays at 00:00 UTC, the longest `lockWeeks` ahead. Each roll claims every lock's fees and rebate, withdraws the locks that ended, pays waiting exits from them first, and only then locks again.

The ratio is kept inside a 200% to 300% band. Below 200%, the vault repays from savings. No BTC is sold, so there is no price risk. Above 300%, it borrows more. Withdrawals are paid from a 3% idle buffer first. After that, collateral is released and debt is repaid from savings, back to the 250% target. If the loan would drop under Mezo's 2,000 MUSD minimum, the vault closes it. Every exit takes a clean pro-rata slice of BTC and MUSD, so nobody who stays ends up with leverage left behind by someone who left.

```
raw         = idle BTC + trove collateral + claimable surplus + BTC locked in veBTC
              + (MUSD in savings - MUSD owed) / price
share price = (raw - profit still unlocking) / shares
```

Every entry point takes a checkpoint first. A rise in raw that no deposit caused is locked there and released linearly over 7 days. A loss uses up the locked profit before it lowers the share price. `lockedProfit()` and `profit()` show what is still unlocking and until when, and `pendingProfit()` shows gains the next checkpoint will lock. Anyone can call `sync()` to take one.

An exit larger than what can leave right now waits in the withdrawal queue ([`RedeemQueue`](contracts/src/RedeemQueue.sol)). `requestRedeem` moves the shares into escrow, where they keep earning and keep their risk until paid. Requests are paid first come, first served, at the share price of the fill, ahead of instant exits. `processQueue()` can free collateral to pay them, and `claim(ids)` sends each request's BTC to its receiver. A request can't be cancelled, and while one waits the vault takes no new debt.

Locked BTC counts at face value, but it can't leave before its lock ends. `maxWithdraw` covers only the liquid part. A larger exit waits in the queue, and the next lock to end pays it before anything is locked again. While a request waits, nothing new is locked. The owner sets the sleeve's share, at most 25%, an optional cap, and the ladder length, 1 to 4 weeks. The guardian, the keeper or the owner can pause new locks, and only the owner resumes them. The sleeve ([`VeSleeve`](contracts/src/VeSleeve.sol)) has no owner of its own and never moves its NFTs, so locked BTC can only come back to the vault.

Anyone can call `rebalance()`, `processQueue()`, `sync()` and `roll()`, but only the keeper's roll locks new BTC, so a deposit made just before it cannot size a lock. `harvest()` is open to anyone once the trove is closed. While the trove is open, only the keeper or owner can harvest, so nobody can sandwich the swap inside their own transaction. A guardian key can only stop new borrowing or `unwind()` the loan. Every other power stays with the owner, a 24-hour timelock.

## Mezo integration

| Mezo contract | Used for |
| --- | --- |
| BorrowerOperations | `openTrove`, `adjustTrove`, `addColl`, `withdrawColl`, `refinance`, `closeTrove`, `claimCollateral` |
| TroveManager | `getEntireDebtAndColl`, `getTroveStatus`, `getTroveMaxBorrowingCapacity`, `getTroveInterestRate`, `checkRecoveryMode`, system collateral and debt |
| PriceFeed | BTC price for share pricing and swap limits |
| HintHelpers, SortedTroves | Approximate insert hints for each target ratio, so large moves never walk the whole trove list |
| MUSD Savings Vault (sMUSD) | `deposit`, `withdraw`, `claimYield`, yield-index valuation |
| Mezo DEX Router (MUSD/BTC pool) | Harvest (MUSD to BTC) and fee buy-backs (BTC to MUSD), with minimum outputs taken from the PriceFeed |
| veBTC | `createLock`, `increaseAmount`, `withdraw`, and reads of `voted` and `votingPowerOfNFT` |
| Pools Voter | `vote`, `poke` and `reset`, plus reads of `ve`, `gauges`, `isAlive`, `gaugeToFees` and `gaugeToBribe` |
| sMUSD gauge rewards | `getReward` on its fees and bribe rewards, in MUSD |
| RewardsDistributor | `claim`, the weekly BTC rebate |
| ChainFeeSplitter | `updatePeriod`, which the keeper runs when Mezo hasn't by the time it rolls |

## Things we learned about Mezo the hard way

- **20 precompile calls per transaction.** The BTC token and the price oracle are precompiles, and `PriceFeed.fetchPrice()` costs two calls. The 21st call burns all of its gas. The vault reads the price once per transaction into a snapshot. The heaviest call (refinance, borrow and buy-back in one rebalance) uses about 13. The cap applies inside a single `eth_call` too, so a multicall of price-reading views costs 2 per view. The profit unlock and the queue add no calls to any v5 path: all 21 preflight scenarios leave the same budget on v5 and v6.
- **A paused DEX still quotes.** One key can pause Mezo's pool factory. Its pools then refuse every swap while `getAmountsOut` keeps quoting, so the vault checks `isPaused()` before it trusts a quote.
- **Borrowing capacity is frozen at open.** A trove's `maxBorrowingCapacity` is set from its collateral at open time. Adding collateral does not raise it. The vault adds new deposits as collateral, then `refinance()`s, then borrows, all in one rebalance. It only refinances if that doesn't raise the trove's interest rate.
- **sMUSD is not ERC-4626.** It is a 1:1 receipt token with a yield index. `withdraw` also pays out all accrued yield.
- **The loan owes MUSD you never received.** The 0.1% fee and the interest are added to the debt. Left alone, that gap stays with whoever exits last. The vault buys it back right after borrowing. If the pool can't fill that purchase within the slippage limit, `maxWithdraw` offers only exits that leave a safe minimum loan open, split pro rata between holders.
- **Gas estimates come in low.** `eth_estimateGas` undershoots calls that go through the BTC precompile, and a transaction sent with the bare estimate can run out of gas. Mezo bills max(gas used, half the limit), so a 1.5x pad costs nothing. The scripts always pad, and a wallet front end should too.
- **Hints must be deterministic.** A sorted-list hint seeded with the block number samples different troves at estimation and at execution, so gas swings by about 25%. The vault seeds the sample with the target ratio, and reuses its own list neighbours for small moves.
- **Mezo refuses closes that hurt the system.** `closeTrove` reverts if the system ratio would end under 150%, and the last trove can never close. The vault then keeps the trove open: `rebalance()` repays instead of closing, and exits release collateral only down to the line that keeps the trove at target and the rest of the system at 150%.
- **Edge case on the last trove.** The vault also covers a Mezo-side edge case where the last trove cannot take a repayment. Exits then go through `withdrawColl` and release collateral only above 200% of today's debt.
- **Max views move every second.** Mezo accrues interest live, so `maxWithdraw` and `maxRedeem` can drop by a few wei between reading and sending. Leave 0.001% of room, as `scripts/vault.sh withdraw-max` and `redeem-max` do.
- **The precompile cap survives try/catch.** Once a transaction passes 20 precompile calls, every later one fails too, including calls inside `try`, and a reverted call still counts. The heaviest `roll()` uses 15: the price 2, four rebates, four withdraws, one sweep and two new locks at 2 each.
- **Estimates and try/catch.** `eth_estimateGas` looks for the smallest limit that does not revert. When a `try` swallows an out-of-gas, that limit is one where the caught call quietly fails. The sleeve checks `gasleft()` before every caught Mezo Earn call and gives each a fixed budget, so a short limit reverts instead.
- **Mezo Earn's public repo is not what is deployed.** tigris on GitHub (`0a3b5e84`) differs from the verified testnet veBTC, Voter and gauge sources by hundreds of lines, and has no VaultGauge. Tests here use the verified explorer source.
- **veBTC timing.** Votes and resets open an hour after the Thursday 00:00 UTC flip and close an hour before the next. A voted lock cannot be withdrawn, so a matured lock is reset first. The weekly rebate cannot be claimed until someone runs the splitter's `updatePeriod()`, which anyone can.
- **Forks can't run Mezo.** The BTC token and the oracle are precompiles. The testing here runs on Mezo testnet: real transactions, single-`eth_call` scenarios that inject only our own code and its BTC balance into live state, and shock tests on a private deployment of Mezo's own MUSD code (see Staging). No Mezo contract is replaced. The one exception is v7's veBTC cycle. It also ran on a local chain built from Mezo's verified code, to step through Thursdays a testnet can't skip, with only the BTC precompile stood in.

## Staging: shocks the live testnet can't make

The live oracle can't be moved. So price shocks, liquidation, redemption and Recovery Mode ran on a private copy of Mezo's MUSD system, deployed on Mezo testnet from [`staging/`](staging/). It is Mezo's own code (mezo-org/musd at `de1ec2af`, plus the verified MUSDSavingsRate source), wired in the order of Mezo's deploy scripts. It uses the two test hooks that the same repo uses on its matsnet_fuzz network: MockAggregator sets the price, InterestRateManagerTester sets the rate. BTC is the real precompile, and swaps go through the real Mezo DEX router, in a MUSD/BTC pool on the live factory. Every transaction and check is in [`deployments/staging-log.md`](deployments/staging-log.md).

| Phase | What happened | Result |
| --- | --- | --- |
| Redemption | 300 MUSD redeemed from the vault trove, later a full redemption | NAV held. Surplus collateral was counted, then claimed by a stranger's `rebalance()`. Anyone could harvest afterwards. |
| Band | BTC -25%, then +50% | Repaid, then borrowed back to 2.50 from savings. No BTC sold. |
| Rates | Mezo at 3%, then 1.5%, then 1% (trove at 1%) | No new debt above the 2% limit. At 1.5%, borrowed only up to the frozen capacity and kept the 1% rate. At 1%, refinanced and borrowed to target. |
| -50% in one block | Trove at 125%, system in Recovery Mode | Exits limited to idle BTC. `rebalance()` repaid to 2.50 and lifted the system out. |
| -60% in one block | Trove at 100%, liquidated | The vault kept all its MUSD. NAV fell only by the 200 MUSD reserve and the 1% haircut. A stranger's harvest and both exits worked. |
| Close refused | Rest of the system under 150% | v2's `rebalance()` reverted inside Mezo. v5 keeps the trove at the floor, and exits stop at the 150% line. |
| Last trove | The other borrower was liquidated | Hit the Mezo-side edge case above. v5 exits through `withdrawColl`. |

v6 ran five more phases on the same private copy (vault `0xf3C2…6D30`). All 55 checks passed. Real transactions and plain `eth_call`s only.

| Phase | What happened | Result |
| --- | --- | --- |
| Recovery Mode with the queue | BTC -50%, a holder queues every share | Fills took idle BTC only and never moved the trove. The guardian's pause worked, and its unwind was refused inside Mezo. Once the price came back, `processQueue` freed collateral. The claim paid exactly the sum of the three fills, with value per share kept at every fill. |
| Liquidation | BTC -60%, Mezo's real `liquidate` | `totalAssets` fell by exactly the loss minus the standing lock. A request made before the crash lost the same per share. A stranger's harvest locked its premium in the same transaction and paid the waiting request. |
| Redemption | The vault trove redeemed in full | The lock absorbed the 1% haircut. The next fill claimed the surplus collateral. |
| Stale oracle | The price two hours old | `claim` and `requestRedeem` still worked. Every pricing entry point reverted, and the max views read 0. `totalAssets` and `pendingProfit` priced at the last price to the wei. |
| Payouts the vault triggers | Staging sMUSD pays out inside the vault's own withdraw | `pendingProfit` showed the gain, and `sync` locked it with `totalAssets` continuous to the wei. |

## Try it

The web app and the docs run from one command with Docker: the app on http://localhost:5667 and the docs on http://localhost:5668. Set `MEZO_NETWORK=mainnet` for a mainnet build, and `APP_PORT` or `DOCS_PORT` to change a port.

```bash
docker compose up -d --build
```

The scripts below need Foundry, Python 3 and `jq`.

```bash
bash scripts/new-wallet.sh ALICE          # wallets land in .env (gitignored)
bash scripts/preflight.sh                 # 42 scenarios against live testnet contracts, no funds needed
bash scripts/deploy.sh                    # deploy + verify, needs a little testnet BTC for gas
bash scripts/sim.sh 0.06 0.03             # full loop with real transactions, explorer links in deployments/
bash scripts/vault.sh deposit ALICE 0.1   # native BTC deposit
bash scripts/vault.sh rebalance           # open or adjust the trove (anyone can call)
bash scripts/vault.sh distribute          # push protocol fees into sMUSD
bash scripts/vault.sh harvest             # savings income to BTC (keeper)
bash scripts/vault.sh withdraw ALICE 0.05
bash scripts/vault.sh request ALICE 0.05  # queue an exit beyond the instant limit, or "all"
bash scripts/vault.sh process             # pay waiting requests, freeing collateral if needed (anyone)
bash scripts/vault.sh claim 1,2           # send filled requests' BTC to their receivers (anyone)
bash scripts/vault.sh sync                # lock gains no entry point picked up, so they start unlocking
bash scripts/vault.sh pause               # guardian: stop new borrowing, `unwind` closes the loan
bash scripts/vault.sh roll                # weekly veBTC roll, only the keeper's roll locks new BTC
bash scripts/vault.sh sleeve-pause        # guardian: stop new veBTC locks, running ones still end on schedule
bash scripts/state.sh                     # live vault state, with the sleeve and each lock
bash scripts/keeper.sh 600                # keeper loop: pay the queue, harvest, rebalance, roll weekly, sync
bash scripts/timelock.sh schedule 'setBorrowingEnabled(bool)' false   # owner call, runs with execute after 24 h
TARGET=$SLEEVE bash scripts/timelock.sh schedule 'setSleeve(uint16,uint256,uint8)' 500 $(cast max-uint) 4
bash scripts/staging.sh price 500000      # staging only: move the oracle, then rate, arb, redeem, liquidate, expect
```

## Testnet

| | Address |
| --- | --- |
| Vault v7 (fBTC) | [`0x4DA2eb6942cF136126A630e4C968CE43474c0Db6`](https://explorer.test.mezo.org/address/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6), source verified on [Sourcify](https://repo.sourcify.dev/31611/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6) (exact match) |
| Withdrawal queue | [`0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3`](https://explorer.test.mezo.org/address/0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3), created by the vault, verified on [Sourcify](https://repo.sourcify.dev/31611/0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3) (exact match) |
| veBTC sleeve | [`0xee76C202a9e43988c55DC86816a6c14211Db209B`](https://explorer.test.mezo.org/address/0xee76C202a9e43988c55DC86816a6c14211Db209B), created by the vault, verified on [Sourcify](https://repo.sourcify.dev/31611/0xee76C202a9e43988c55DC86816a6c14211Db209B) (exact match). 5% of the BTC on a 4-week ladder. |
| SystemMath library | [`0x34df486c93DB9a2A263498df97BDDF04BF1d57f7`](https://explorer.test.mezo.org/address/0x34df486c93DB9a2A263498df97BDDF04BF1d57f7), linked into the vault, verified on [Sourcify](https://repo.sourcify.dev/31611/0x34df486c93DB9a2A263498df97BDDF04BF1d57f7) (exact match) |
| Vault owner, 24 h timelock | [`0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719`](https://explorer.test.mezo.org/address/0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719), OpenZeppelin TimelockController, verified on [Sourcify](https://repo.sourcify.dev/31611/0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719) (exact match). It owns v7 and so the sleeve's settings. v6 keeps its timelock [`0x2A43…803E`](https://explorer.test.mezo.org/address/0x2A4327156Cd2f4472282D1A636b424a86324803E), and v5 keeps [`0xf95A…6C5B`](https://explorer.test.mezo.org/address/0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B). |
| Guardian | `0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE`, its own key, can only `pauseBorrowing()`, `unwind()` and pause new veBTC locks |
| Keeper | `0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23`, its own key, separate from the owner. [`.github/workflows/keeper.yml`](.github/workflows/keeper.yml) runs one pass every 15 minutes once the repository has a `KEEPER_PK` secret. |
| Vault v6, retired | [`0xb7A15aB24483Dfe92056F73279ECF11CE00675db`](https://explorer.test.mezo.org/address/0xb7A15aB24483Dfe92056F73279ECF11CE00675db), loan unwound, holders moved to v7, verified on [Sourcify](https://repo.sourcify.dev/31611/0xb7A15aB24483Dfe92056F73279ECF11CE00675db) (exact match). The deployer keeps 0.0001 BTC in it until 2026-11-01, so the 0.000099 BTC of profit still unlocking there has a holder. |
| Vault v5, retired | [`0x2964612e8976b4003083E6014cA39f5fD7b41f3A`](https://explorer.test.mezo.org/address/0x2964612e8976b4003083E6014cA39f5fD7b41f3A), loan closed, holders moved to v6, verified on [Sourcify](https://repo.sourcify.dev/31611/0x2964612e8976b4003083E6014cA39f5fD7b41f3A) |
| MUSD Savings Vault (sMUSD) | `0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16` |
| BorrowerOperations | `0xCdF7028ceAB81fA0C6971208e83fa7872994beE5` |
| Router | `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9` |

The live vault runs byte for byte the code the v7 lifecycle test ran, apart from its constructor addresses, and its MUSD paths are v6's, which passed the staging phases. Testnet runs a 2.0 / 2.2 / 2.4 band with a 2% buffer and a 5% sleeve, because the test wallets hold 0.069 BTC and Mezo's minimum loan is 2,000 MUSD. Every transaction is linked:

- [`deployments/testnet-log.md`](deployments/testnet-log.md), v7 section at the bottom.
  - The deploy from the repo with SystemMath linked, and all four contracts verified.
  - A 34-call role matrix: the 17 v6 checks, plus 17 on the sleeve.
  - The move from v6. The guardian unwinds v6, its leftover MUSD is harvested, and Alice and Bob leave in full. Everyone deposits into v7, and the keeper opens the trove at 2.20.
  - The keeper's first roll locks 0.003388 BTC as veBTC 1724 (until Nov 19) and 1725 (until Nov 12). Both vote all their power for the sMUSD gauge, and `totalAssets` doesn't move.
  - Ownership moves to its own 24-hour timelock in minutes. It is deployed at zero delay, accepts, and then sets the delay.
- The v6 section is above it.
  - Borrowing is off at deploy, so a rebalance opens no trove.
  - A 17-call role matrix, from each role's own address.
  - The guardian pauses and unwinds, and the owner re-enables.
  - Alice and Bob move from v5, and the keeper opens the trove at 2.50.
  - Two queue requests are filled and claimed with real transactions. One is paid from idle BTC. The other frees collateral and repays from savings, keeping the trove at target.
  - A donation is held out of the share price until `sync()` locks it for exactly 7 days.
  - A copy with a 1-hour unlock is checked against the release formula to the wei.
- The v5 section is above it. Alice deposits native BTC and Bob uses the ERC-20 path. Bob opens the trove (ratio 2.50, fee bought back). A real sMUSD payout is harvested into BTC, and Bob exits part of his position, repaid from savings. Both positions stay live, 0.065 BTC at 2.50. Above it are the runs on v2 (`0x29CE…8B78`), which staging later showed mishandles a close that Mezo refuses.
- [`deployments/testnet-log-v1.md`](deployments/testnet-log-v1.md) is the first deployment, a full cycle: deposits, open, a real sMUSD payout of +43.65 MUSD harvested into BTC (+0.58% per share), a partial exit, then a closing exit. Both users got their BTC back plus the yield. It also records the two client-side gas failures that led to the padding and hint fixes above.

## Risks and limits

- **Unaudited.** Testnet only. The v5 code had four independent review passes and the staging phases, and v6 had a design review before it was written. The v7 sleeve had a review pass, and its weekly cycle ran on a local chain of Mezo's verified code. Every finding is fixed or listed here.
- **Locked BTC.** Up to the sleeve's share of the BTC is locked for up to `lockWeeks` weeks. An exit larger than the liquid part waits for the next lock to end, at most `lockWeeks` weeks and usually one.
- **Mezo Earn.** veBTC, the Voter and the booster are upgradeable. Before every new lock the sleeve checks the wiring it was built with, and the keeper pauses new locks when any of their implementations change. `rebalance()` never calls Mezo Earn, so the safety path does not depend on it. A lock Mezo refuses to release keeps counting at face value, emits `RungStuck` and is retried every roll. If Mezo's team swaps the Voter, a voted lock can't be withdrawn until Mezo re-adds the old voter as a secondary one.
- **Rebates after a quiet flip.** A rebate claim that is veBTC's first write after the Thursday flip also pays veBTC's weekly catch-up, about 665k gas, which is more than its 600k budget. That roll skips the rebates, which stay claimable. The keeper calls veBTC's permissionless `checkpoint()` before every roll, so its claims run at about 414k. A lock that has ended and still can't claim is released after a day, and gives up its unclaimed rebates. Principal is never at risk. The next version does the catch-up inside the sleeve itself. It is built and passes every local test.
- **Other reward tokens.** The sleeve claims MUSD from the gauge's fee and bribe rewards. The bribe contract also lists MEZO, mUSDT and mFBTC. None were paid in the last three epochs, and any that are would stay unclaimed.
- **Yield timing.** Profit reaches the share price linearly over 7 days, so everyone earns the same rate per day held. A payout that accrued while one group held is released to whoever holds in the week after. Small losses, such as interest or a fee smaller than what is still unlocking, leave the share price flat and slow the release instead.
- **Recovery Mode.** Mezo blocks collateral withdrawals. Instant exits are limited to idle BTC until it ends, and `rebalance()` keeps idle BTC out of the trove meanwhile. A larger exit waits in the queue and is paid as liquidity returns.
- **Queue order.** Requests are paid first come, first served, and ahead of instant exits. In a long restricted state, the earliest requests take the liquid BTC first. Value per share stays equal for everyone, only the order changes. A request can't be cancelled, and while one waits the vault takes no new debt.
- **Borrowing off by default.** v6 and v7 deploy with borrowing off. Until the owner turns it on, deposits sit idle and earn nothing.
- **Pool far from the oracle.** If the MUSD/BTC pool can't fill the fee buy-back within the slippage setting, the gap stays and part of the collateral is locked until yield covers it or the owner raises slippage (5% at most). The testnet pool sits about 2.6% below the oracle, so testnet uses 4%.
- **Oracle outage.** If the price is more than 60 seconds old, Mezo halts borrowing and so does the vault: deposits and withdrawals revert, `max*` views return 0, and `totalAssets` uses the last price seen.
- **Liquidation.** The loan is liquidated only after a BTC drop of about 56% with nobody calling `rebalance()`. On staging, -50% in one block left it at 125%, and -60% got it liquidated. The vault kept its MUSD and lost only the 200 MUSD liquidation reserve.
- **Last trove.** If the vault holds Mezo's only trove, Mezo never lets it close. Exits stop at the collateral the 2,000 MUSD minimum needs. While the Mezo-side edge case above is open, they stop at 200% of today's debt.
- **Swap liquidity.** The mainnet MUSD/BTC pool is thin, so harvests there should be chunked with `harvest(maxIn)`.
- **Mainnet economics.** sMUSD's income is now mostly interest on Mezo's own 14.5M MUSD of Enclave loans at 1%, paid in lumps, which averages about 1% a year on 7.38M sMUSD. The 2.3% of the last 12 weeks also held redemption fees from the Sep to Oct redemption wave, which stopped once trove debt ran out. About 1% is what the vault pays for its own loan (1% plus the 0.1% borrow fee), so at today's numbers the strategy roughly breaks even on mainnet. MUSD also trades about 1% under the oracle, which would make a new vault trove the first redemption target. A mainnet launch waits until both improve, with borrowing off by default.
- **Redemptions.** A redemption against the vault's trove swaps some BTC for MUSD at the oracle price. The next harvest buys the BTC back.
- **Owner powers.** The owner can tune the ratio band, buffer, slippage, max borrow rate and deposit cap, set the keeper and the guardian, turn borrowing on or off, and `unwind()` the loan. On v7 it also sets the sleeve's share (at most 25%), cap and ladder (at most 4 weeks), and is the only one who can resume paused locks. The owner cannot move user funds. On testnet the owner is a TimelockController, so every one of these calls is public for 24 hours before it can run. The keeper signs with its own key.
- **Guardian.** The guardian can only move the vault toward less risk, by stopping new borrowing or closing the loan. `unwind()` still fails whenever Mezo refuses the close, as in Recovery Mode, so the guardian pauses first. A leaked guardian key can cost a fresh borrow fee and a buy-back spread per unwind, and only after each time the owner re-enables borrowing.
