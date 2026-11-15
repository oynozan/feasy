# Wave 2 plan

Deadline Sunday 2026-11-15. Written 2026-11-03 from the Wave 1 judges' feedback.

## What the judges asked for

| Feedback | Work item |
| --- | --- |
| Show risk handling on canonical contracts, not only staging | B2, B3, B4, B5, plus B6 for what testnet can't trigger |
| On-chain guard, no borrowing when sMUSD pays less than the loan costs | A1 |
| `unwind()` usable in Recovery Mode | A2 |
| Run the veBTC claim and withdraw path on-chain | B1 |
| Say how Feasy sustains itself, for example a performance fee | A3, C1 |
| Show real users depositing | C4 |
| Link a pitch deck | D1, D2 |
| Business viability 6/10, extend MUSD and MEZO utility | A4, C2, C3 |

## Facts checked on 2026-11-03

- **Keeper is healthy.** The GitHub Action has 778 runs, and the last 100 all succeeded.
- **`unwind()` can't run in Recovery Mode.** It always calls `closeTrove`, and Mezo's BorrowerOperations refuses that during Recovery Mode (`_requireNotInRecoveryMode`).
- **No borrow guard follows sMUSD.** The only guard is the owner-set `maxBorrowRate`, which never looks at what sMUSD pays.
- **sMUSD has no rate getter, but the rate can be measured.** It exposes `yieldIndex`, the accumulated yield per sMUSD scaled by 1e18. On testnet that index gives a realized rate of about 116% a year over 9.6 days and 276% over 20 days. The vault's loan costs 1%. So on testnet the guard will allow borrowing, and showing it block needs a raised threshold.
- **The sMUSD gauge pays MEZO.** The gauge at `0xA6972f35550717280f2538EA77638B29073e3F07` emits about 551k MEZO a week to 471,586 staked sMUSD, about 61 MEZO per sMUSD per year. About half of all sMUSD is staked there. The MUSD yield of staked sMUSD goes as fees to the veBTC locks that vote for the gauge. Feasy holds sMUSD unstaked and votes veBTC for this gauge, so it only collects one side.
- **MEZO is a precompile token** at `0x7B7c…0001`, so every MEZO call counts toward the 20 precompile calls per transaction.
- **Mezo Earn's BoostVoter** lets veMEZO vote on a boost gauge tied to one veBTC lock, which raises that lock's voting power. The lock's owner creates the gauge and can attach bribes.
- **The vault's runtime is 24,476 bytes** against the 24,576 limit. Every feature below needs room first, see A5.
- **The v8 sleeve fix is lost.** It lived in a session scratch folder that has since been cleared. The spec is short: in `VeSleeve.collect()`, when principal is above zero, run `try ve.checkpoint{gas: CHECKPOINT_GAS}()` behind a `gasleft` floor, and add `checkpoint()` to IVeBTC.
- **No veBTC lock has been withdrawn yet.**
  - The test copies' locks 1720 (vault `0xeDb4…075c`) and 1722 (vault `0x8E1c…C6a8`) ended Oct 29 and were never rolled.
  - Locks 1719 and 1721 end Nov 5.
  - v7's own locks end Nov 12 (1725) and Nov 19 (1724).

## A. Contracts, v8

**A1. Spread guard**
- `_canBorrow` also requires the savings rate to be at least the loan rate plus `minSpreadBps`.
- The savings rate comes from sMUSD's `yieldIndex`, snapshotted weekly in `roll()` and kept in a ring of four.
- The rate is the change in the index over a trailing window of up to 28 days. Until a full week of history exists, the vault doesn't borrow.
- The loan rate is `getTroveInterestRate` plus the 0.1% borrow fee spread over a year.
- When the trailing spread is negative, `rebalance()` repays toward closing, so a loss-making loan winds down without the guardian.
- **Known weak spot:** anyone can donate to sMUSD to lift the index. Faking one point a year over 4 weeks costs about 0.08% of the whole sMUSD supply, and the attacker only gets the vault to borrow at a loss. The 28-day window keeps that expensive. Document it in SECURITY.md.

**A2. Recovery Mode unwind**
- In Recovery Mode, `unwind()` repays debt from savings down to Mezo's minimum and leaves the collateral, since repaying is allowed there.
- It sets `closing`, so the first `rebalance()` after Recovery Mode ends closes the loan. Anyone can call that `rebalance()`.
- Exits keep working through the queue.
- `_repayBlocked` stays untouched.

**A3. Performance fee**
- `feeBps`, capped in code at 20% and set through the timelock, with a suggested 10%.
- It's taken in `_checkpoint` from each new gain before it enters the 7-day unlock, minted as fBTC to `feeRecipient`.
- Gains only exist when savings beat the loan cost or the sleeve earns, so the fee is zero whenever the spread isn't positive.
- No management, deposit or exit fee.

**A4. Savings sleeve.** A new contract that holds the vault's sMUSD, modelled on VeSleeve: no owner of its own, and only the vault can pull MUSD out.
- It stakes a share of the sMUSD in the sMUSD gauge (`stakeBps`, set through the timelock) and earns MEZO.
- `harvestMezo()` sells MEZO for BTC through Mezo Pools at an oracle-bounded price, in its own transaction because of the precompile budget.
- The MUSD yield of the staked part flows to veBTC voters, Feasy's sleeve among them.
- This also moves `_parkMusd`, `_pullMusd` and `savingsValue` out of the vault, which frees bytecode.

**A5. Size budget**
- Try `optimizer_runs` 200 → 1 first and measure.
- Move the savings code into A4.
- If that's still not enough, move the trove steering helpers into the linked `SystemMath`.
- Target at least 1.5 KB of headroom before writing A1 to A3.

**A6. Sleeve fix.** Rebuild the checkpoint-in-`collect()` fix from the spec above. Flip the `test_known_*` tests in `coverage/test/RebateCheckpoint.t.sol`.

**A7. Tests**
- Forge coverage on every new branch.
- Staging run of A2: shock the price into Recovery Mode, unwind repays to the floor, the price recovers, rebalance closes.
- Preflight scenarios for A1 to A4 against live testnet state.
- Slither triage added to SECURITY.md.

## B. On-chain proof on canonical testnet contracts

**B1. veBTC claim and withdraw**
- **Now:** roll both test copies from GUARDIAN, their keeper. This claims the fees and rebate of locks 1720 and 1722 and withdraws them on Mezo's real veBTC.
- **After Nov 5, 01:00 UTC:** roll again for 1719 and 1721, and run Preflight 42 at the first block after the flip.
- **Nov 12:** the keeper's roll on v7 does the same for lock 1725 on the production vault.
- Every roll gets logged in `deployments/testnet-log.md`.

**B2. Unwind with a live loan.** Moving holders from v7 to v8 starts with the guardian unwinding v7, which closes a real trove on canonical contracts.

**B3. The band moving with the market**
- v8 runs a tight testnet band of 2.15 / 2.20 / 2.25. A BTC move of about 2.3% then makes the keeper repay from savings or borrow more, on Mezo's real oracle and BorrowerOperations.
- The log collects each one with its price.

**B4. Spread guard demo**
- With today's real spread, v8 borrows.
- The owner then raises `minSpreadBps` above the measured spread, and `rebalance()` refuses new debt.
- The owner lowers it again.
- Do these before the timelock handover, or schedule them 24 hours ahead.

**B5. Queue paid by an ended lock.** Holders leaving v7 take the liquid part at once. The locked part waits in the queue, and the Nov 12 and Nov 19 rolls pay it from the ended locks.

**B6. What testnet can't trigger.**
- Recovery Mode and liquidation need a system-wide crash, so they stay on staging, which runs Mezo's own code.
- Optional, needs your OK: run A2 as an `eth_call` on live testnet state with only the oracle's price overridden. It is labelled as a simulation.

## C. Business and Mezo utility

**C1. Revenue.**
- **The fee:** a 10% performance fee, only on profit.
- **The docs:** the economics page gets a business model section with the formula: revenue = fee × TVL × BTC yield.
- **The pitch:** the deck shows it at a few TVL levels.

**C2. MEZO**
- A4 makes Feasy a staker in the sMUSD gauge, earning MEZO emissions.
- Fee revenue buys MEZO and locks it as veMEZO from a treasury, then votes through BoostVoter for boost gauges on Feasy's own veBTC locks. Their voting power goes up, and so does their share of the sMUSD gauge's fees.
- User funds never hold MEZO longer than a harvest, so depositors stay plain BTC.
- **Wave 2:** staking plus selling MEZO for BTC, and one manual boost on testnet with a wallet-owned lock to measure the effect.
- **Wave 3:** the treasury boost loop.

**C3. MUSD**
- **What Feasy adds to MUSD:** every BTC deposited mints MUSD, about 40% of its value at the 250% target. All of that MUSD stays in sMUSD, so it never adds selling pressure on the peg.
- **The app shows** the MUSD borrowed by Feasy, its share of the sMUSD supply, and the MEZO earned.
- **Stretch, peg guard:** no new borrowing while MUSD trades more than 1% under the oracle on Mezo Pools.

**C4. Real users**
- **Onboarding:** the app gets a "Get testnet BTC" step linking Mezo's faucet, and a depositor count on the pool page.
- **Outreach:** you post in the Mezo Discord and on X, and I draft the posts.
- **Target:** 25 outside wallets by Nov 14, with the count and the explorer links in the submission.
- **Mainnet:** a small mainnet beta is possible, because the guard would keep borrowing off at today's mainnet rates. It's unaudited, so it's your call.

## D. Materials

**D1. /pitch**
- A page in the app at feasy.org/pitch: the slides as images with arrow-key and swipe navigation, plus a PDF download.
- Slides and PDF live in `app/public/pitch/`.
- The deck-rendering script moves into `scripts/deck/` so it can't be lost again.

**D2. Deck refresh.** Add three slides:
- the business model, with the fee and revenue at TVL levels;
- the Mezo loop: MUSD, sMUSD, the gauge, MEZO, veBTC and boost;
- traction: depositors, transactions and keeper runs.

Then update the status slide.

**D3. Docs and README**
- **New docs pages:** business model, spread guard, Recovery Mode unwind and the savings sleeve.
- **Updated:** risks, roles and contracts.
- **README:** new numbers and the /pitch link.

## Timeline

| Day | Work |
| --- | --- |
| Tue Nov 3 to Wed Nov 4 | B1 test-copy rolls, D1 /pitch, C4 onboarding and outreach drafts, A5 size spike, a BoostVoter spike on testnet |
| Thu Nov 5 | B1 second test-copy roll after 01:00 UTC, Preflight 42 |
| Wed Nov 4 to Sun Nov 8 | A1 to A7 |
| Mon Nov 9 to Tue Nov 10 | v8 on testnet, Sourcify, role matrix, B3 band live, B4 demo, then the timelock handover |
| Wed Nov 11 | B2 and B5: guardian unwinds v7, holders move, locked parts queue |
| Thu Nov 12 | v7 roll on lock 1725 (B1, B5), v8's first roll |
| Thu Nov 12 to Sat Nov 14 | App metrics, D2 deck, D3 docs, submission text, user count |
| Sun Nov 15 | Submit |

## Decisions, 2026-11-10

1. **Fee: 10% of realized profit.** It comes from research on about 30 comparable vaults.
   - **Comparables:** Resolv charges 10%, Instadapp Lite ETH and Acre 20%, Convex 17%, and Bitcoin staking validators 3 to 8%.
   - **High-water mark:** per share, so no fee on a loss or on winning a loss back. Without it, lumpy sMUSD income against steady interest would charge depositors when they earn nothing.
   - **Limits:** capped at 20% in code. A rise waits 30 days and a cut is immediate.
   - **Recipient:** the Booster, which holds protocol revenue and the veMEZO.
2. **Real users:** testnet only, no mainnet.
3. **Recovery Mode simulation:** approved. Preflight scenario 43 points the live PriceFeed at a stand-in oracle inside a single `eth_call`.
4. **veMEZO boost:** in Wave 2.
   - The savings sleeve sends `boostBps` of its MEZO to the Booster. It is 100% on testnet, where the only MEZO pool holds about $54.
   - The Booster keeps one permanent veMEZO lock and votes it each epoch for boost gauges on the sleeve's own veBTC locks, up to 5x their weight.
5. **Tight band:** on the production v8 vault.

## Housekeeping

- The deployer's 0.0001 BTC in v6 can move to v8 now, since its unlock ended Nov 1.
- Keep v8 work in the repo, not a scratch folder.
