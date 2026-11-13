<p align="center">
  <img src="docs/images/home.png" alt="Feasy home: yearly yield, pool balance, the pool loan chart and how it works" width="100%">
</p>

# Feasy

**Deposit BTC, get more BTC.** Feasy is a BTC savings vault on [Mezo](https://mezo.org). It borrows MUSD against the pooled BTC at Mezo's fixed rate and parks it in the MUSD Savings Vault (sMUSD). The savings income above the loan cost is swapped back into BTC. A small veBTC sleeve also earns the sMUSD gauge's fees. Your exposure stays plain BTC: the borrowed dollars sit in dollar savings, so there is no leverage on BTC.

**[Pitch deck](https://feasy.org/pitch)** · **[Documentation](https://docs.feasy.org)** · **[Live contracts](#live-on-mezo-testnet)** · **[Run it](#run-it)** · **[Security](SECURITY.md)**

Feasy also runs **[Liquid veBTC](https://docs.feasy.org/liquid-locker)**. Lock BTC, or bring a veBTC lock, for fveBTC, which earns Mezo's gauge fees and BTC rebates and redeems within four weeks. Lock MEZO for fveMEZO, a permanent veMEZO lock that boosts them for a share of what they earn. Both products are live on Mezo testnet.

## How it works

```mermaid
flowchart LR
    U([You]) -- BTC --> V["Feasy vault<br/>fBTC shares"]
    V -- "BTC collateral" --> T["MUSD loan<br/>Mezo trove"]
    T -- "borrowed MUSD" --> S["sMUSD<br/>savings"]
    S -- "income above the loan cost" --> H{{harvest}}
    H -- "swapped to BTC" --> V
    V -- "5% of the BTC" --> L["veBTC locks<br/>vote for the sMUSD gauge"]
    L -- "MUSD fees" --> S
    L -- "BTC rebates and ended locks" --> V
    S -- "part staked" --> G["sMUSD gauge<br/>MEZO emissions"]
    G -- "MEZO" --> B["Booster<br/>permanent veMEZO"]
    B -- "boost votes, up to 5x" --> L
    V -- "BTC plus yield" --> U
```

1. **Deposit** native BTC or the BTC ERC-20 and receive `fBTC` shares (ERC-4626, priced in BTC).
2. **One shared loan, only when it pays.** `rebalance()` borrows MUSD at Mezo's fixed rate against the pool, holding the collateral ratio in a band (200 / 250 / 300% by design), and parks the MUSD in sMUSD. It takes on new debt only while sMUSD's realized rate, measured on chain from its yield index, beats the loan's rate plus the borrow fee. It buys back the 0.1% borrow fee right away, so the MUSD the vault holds always covers what the loan owes.
3. **Harvest.** Savings income above the loan cost is swapped to BTC on Mezo's DEX, with an oracle-bounded price.
4. **Fair payouts.** New profit reaches the share price linearly over 7 days, so joining just before a payout and leaving right after earns nothing extra.
5. **The Mezo loop.** Part of the BTC sits in weekly veBTC locks that vote for the sMUSD gauge and earn its fees and Mezo's BTC rebate. Part of the sMUSD is staked in that same gauge and earns MEZO. That MEZO goes into a permanent veMEZO lock, which votes through Mezo's BoostVoter to boost the vault's own veBTC locks, up to 5x their weight.
6. **Exits.** Exits are paid instantly from the liquid part. A larger exit waits in a first-come queue that the next released collateral or ended lock pays.
7. **Recovery Mode.** If Mezo enters Recovery Mode, where it refuses to close loans, the guardian's `unwind()` repays the loan down to Mezo's minimum from savings. The first `rebalance()` after Recovery Mode ends then closes it.

```
raw         = idle BTC + loan collateral + claimable surplus + BTC locked in veBTC
              + (MUSD in savings - MUSD owed) / price
share price = (raw - profit still unlocking) / shares
```

Feasy's one fee is 10% of the BTC profit the vault actually earns. Nothing is charged on deposits, withdrawals or assets held. The fee only takes gains that lift the share value above its highest point, so a loss and its recovery are free. The contract caps it at 20%, and a rise waits 30 days, longer than the slowest exit. Fee shares go to the booster, which holds protocol revenue and the veMEZO. Holders also bear Mezo's costs: the borrow fee, the loan interest and swap slippage. More in the docs: [how it works](https://docs.feasy.org/how-it-works), [economics](https://docs.feasy.org/economics) and [withdrawals](https://docs.feasy.org/withdrawals).

## Inside the pool

<p align="center">
  <img src="docs/images/pool.png" alt="Pool stats: balance split into loan backing, kept aside, locked in veBTC and savings minus loan, loan health 220%, savings 2,140 MUSD, pool activity" width="100%">
</p>

The pool view on testnet shows where every satoshi sits: backing the loan, kept aside for instant exits, locked in veBTC, and the savings above what the loan owes. It also shows the loan's health against its band and every deposit, loan move and cost as it happens.

## The weekly veBTC roll

```mermaid
flowchart LR
    A["Thursday 00:00 UTC<br/>the epoch flips"] --> B["Keeper catches veBTC up<br/>and runs Mezo's period update"]
    B --> C["roll() claims every lock's<br/>MUSD fees and BTC rebate"]
    C --> D["Locks that ended<br/>are withdrawn"]
    D --> E["Waiting exits<br/>are paid first"]
    E --> F["New locks of up to 4 weeks<br/>vote for the sMUSD gauge"]
```

The sleeve keeps at most four locks, each ending on a Thursday. Locked BTC counts at face value but can't leave before its lock ends, so `maxWithdraw` only covers the liquid part. Nothing new is locked while an exit waits. The sleeve has no owner of its own and never moves its NFTs, so locked BTC can only come back to the vault. Details: [veBTC sleeve](https://docs.feasy.org/vebtc-sleeve).

## Using the app

<p align="center">
  <img src="docs/images/deposit.png" alt="Deposit flow: amount, sign, confirm, deposited, in BTC or tBTC" width="100%">
</p>

You can deposit in four steps, with native BTC or tBTC, and connect with Mezo Passport or a browser wallet. Withdrawals show what can leave now and turn anything larger into a queued request. A request can't be cancelled, and the app says so before you sign. A position in an older vault version gets a "Move" row that carries it over in two signatures.

## Who can do what

```mermaid
flowchart TB
    O["Owner<br/>24-hour timelock"] -- "settings, borrowing on or off,<br/>sleeve size, resuming locks" --> V["Vault, queue and sleeve"]
    G["Guardian"] -- "pause borrowing, close the loan,<br/>pause new locks" --> V
    K["Keeper<br/>GitHub Action"] -- "harvest, weekly roll,<br/>pay the queue" --> V
    A["Anyone"] -- "deposit, withdraw, rebalance,<br/>process the queue, sync" --> V
```

Nobody can move user funds. Every owner call is public for 24 hours before it can run. The guardian can only move the vault toward less risk, and only the keeper's roll can lock new BTC. See [roles](https://docs.feasy.org/roles) and [SECURITY.md](SECURITY.md).

## Live on Mezo testnet

All contracts are verified on Sourcify with exact matches.

| | Address |
| --- | --- |
| Vault v8 (fBTC) | [`0x5e7800fB24651038e72ad1e055A2B2AD81a59Ed2`](https://explorer.test.mezo.org/address/0x5e7800fB24651038e72ad1e055A2B2AD81a59Ed2) |
| Withdrawal queue | [`0xFEAa1083F3F5cBcBec51B2c12491E8474F230825`](https://explorer.test.mezo.org/address/0xFEAa1083F3F5cBcBec51B2c12491E8474F230825) |
| veBTC sleeve | [`0x47fE5D3C539314ea299E96a15d5f8D2956b414EC`](https://explorer.test.mezo.org/address/0x47fE5D3C539314ea299E96a15d5f8D2956b414EC) |
| Savings sleeve, spread guard and gauge staking | [`0xF38BE227B69FBE1D5CC5d41C2d7E362c984041aD`](https://explorer.test.mezo.org/address/0xF38BE227B69FBE1D5CC5d41C2d7E362c984041aD) |
| Booster, veMEZO 947 and fee revenue | [`0xE5611627004b8e64ca40C9ad7FEFF9cdEa83Ab25`](https://explorer.test.mezo.org/address/0xE5611627004b8e64ca40C9ad7FEFF9cdEa83Ab25) |
| SystemMath library | [`0xAF59E8672F29f76454aC30D9ac0A2503826eb976`](https://explorer.test.mezo.org/address/0xAF59E8672F29f76454aC30D9ac0A2503826eb976) |
| Owner, 24 h timelock | [`0x2A004C7B97Dbf8096C2331248ABc23CDBc0216d6`](https://explorer.test.mezo.org/address/0x2A004C7B97Dbf8096C2331248ABc23CDBc0216d6) |
| Guardian | [`0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE`](https://explorer.test.mezo.org/address/0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE) |
| Keeper | [`0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23`](https://explorer.test.mezo.org/address/0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23), run every 15 minutes by [`keeper.yml`](.github/workflows/keeper.yml) |
| Liquid veBTC, fveBTC | [`0x8576C2ea77dbae1D6897d4D5834B1ae247e9032F`](https://explorer.test.mezo.org/address/0x8576C2ea77dbae1D6897d4D5834B1ae247e9032F), its transactions in [`testnet-locker-log.md`](deployments/testnet-locker-log.md) |
| Liquid veBTC, fveMEZO and veMEZO 949 | [`0xaE45e8B6f79Ed678dC3986EbA0871eF85cc8D385`](https://explorer.test.mezo.org/address/0xaE45e8B6f79Ed678dC3986EbA0871eF85cc8D385) |

v8 runs a tight 2.15 / 2.20 / 2.25 band, so ordinary BTC moves make it repay from savings or borrow more on Mezo's real contracts. It has a 2% buffer, a 5% sleeve on a 4-week ladder and 20% of its sMUSD staked in the sMUSD gauge. The 10% fee rise waits its 30 days, until Dec 10. Every transaction, from v1 to the live v8, is linked in [`deployments/testnet-log.md`](deployments/testnet-log.md). v7 retired on 2026-11-10: the guardian unwound its live trove, and its holders moved to v8. Older vaults' addresses are in [contracts](https://docs.feasy.org/contracts).

## How it was tested

Forks can't run Mezo, because the BTC token and the price oracle are precompiles. So the testing runs on Mezo itself, with no Mezo contract replaced.

- **Live testnet transactions**, every one linked in the log:
  - deposits, loan opening, real sMUSD payouts harvested into BTC, queued exits, guardian pauses and ownership handovers;
  - veBTC locks claimed and withdrawn after they ended;
  - the guardian unwinding a live loan;
  - the spread guard refusing a loan;
  - a veMEZO lock voting boosts onto the vault's own veBTC locks.
- **47 live-state scenarios** ([`scripts/preflight.sh`](scripts/preflight.sh)). Each is a single `eth_call` against live Mezo testnet state that injects only Feasy's own code. Together they cover:
  - exits, closes, harvests and inflation attacks, plus the exact precompile budget of every entry point;
  - v8's spread guard on the real sMUSD rate and staking in the live sMUSD gauge;
  - a fee rise's 30-day wait;
  - a Recovery Mode unwind, with only the oracle's price overridden.
- **Today's testnet market:** the MUSD/BTC pool prices BTC 5 to 7% above the oracle, so the harvest scenarios refuse to sell, and the 1% buy-back scenarios now fill and run out of their precompile budget. v7's code fails the same scenarios at the same steps.
- **Price shocks on a private copy of Mezo's MUSD system** ([`staging/`](staging/)): -25%, +50%, -50% and -60% in one block, Recovery Mode, liquidation, redemptions, rate changes and a stale oracle. All 55 v6 checks pass.
- **The veBTC cycle on a local chain** built from Mezo's verified Mezo Earn code, with only the BTC precompile stood in. It steps through Thursdays a testnet can't skip. 17 lifecycle tests pass, an independent check reviewed them, and the tested bytecode equals the deployed bytecode.
- **Coverage, 155 tests on Mezo's real code:** the vault is at 98.5% of lines and 96.6% of branches, and the savings sleeve, booster, veBTC sleeve and libraries are at 95% or more. Two bugs the suite found in v8, a fee high-water mark a round trip could erase and a boost an ended lock could block, were fixed before release.
- **Slither:** every finding is triaged in [SECURITY.md](SECURITY.md).

More in the [testing docs](https://docs.feasy.org/testing).

## What we learned building on Mezo

- **20 precompile calls per transaction, and the cap survives `try`/`catch`.** `PriceFeed.fetchPrice()` costs two. Read the price once per transaction and pass it down.
- **Gas estimates come in low** for calls through the BTC precompile. Mezo bills the larger of gas used and half the limit, so a 1.5x pad costs nothing.
- **The loan owes MUSD you never received.** The 0.1% fee and the interest are added to the debt, so buy that gap back right after borrowing, or the last holder to exit is left with it.
- **A paused DEX still quotes.** Check the pool factory's `isPaused()` before trusting `getAmountsOut`.
- **Mezo Earn's public repo is not what is deployed.** Build against the verified explorer source.

The full list is in [Building on Mezo](https://docs.feasy.org/building-on-mezo).

## Mezo integration

| Mezo contract | Used for |
| --- | --- |
| BorrowerOperations, TroveManager | Opening, adjusting, refinancing and closing the shared trove, surplus claims, Recovery Mode checks |
| PriceFeed | BTC price for share pricing and swap limits |
| HintHelpers, SortedTroves | Insert hints for each target ratio |
| MUSD Savings Vault (sMUSD) | Where the borrowed MUSD earns |
| Mezo DEX Router | Harvests (MUSD to BTC) and fee buy-backs (BTC to MUSD) |
| veBTC, Pools Voter | Weekly locks and their votes for the sMUSD gauge |
| Gauge rewards, RewardsDistributor, ChainFeeSplitter | MUSD fees, BTC rebates and the weekly period update |
| sMUSD gauge | Staking part of the sMUSD for MEZO emissions |
| veMEZO, BoostVoter | One permanent veMEZO lock voting boosts onto the vault's own veBTC locks |

## Run it

The web app and the docs start from one command with Docker. The app runs on http://localhost:5667 and the docs on http://localhost:5668, and both listen on localhost only, for a reverse proxy such as nginx to publish. Set `MEZO_NETWORK=mainnet` for a mainnet build, and `APP_PORT` or `DOCS_PORT` to change a port.

```bash
docker compose up -d --build
```

The vault scripts need Foundry, Python 3 and `jq`.

```bash
bash scripts/new-wallet.sh ALICE          # wallets land in .env (gitignored)
bash scripts/preflight.sh                 # 47 scenarios against live testnet contracts, no funds needed
bash scripts/deploy.sh                    # deploy + verify, needs a little testnet BTC for gas
bash scripts/vault.sh deposit ALICE 0.1   # native BTC deposit
bash scripts/vault.sh rebalance           # open or adjust the loan (anyone can call)
bash scripts/vault.sh harvest             # savings income to BTC (keeper)
bash scripts/vault.sh withdraw ALICE 0.05
bash scripts/vault.sh request ALICE 0.05  # queue an exit beyond the instant limit, or "all"
bash scripts/vault.sh roll                # weekly veBTC roll, only the keeper's roll locks new BTC
bash scripts/state.sh                     # live vault state, with the sleeve and each lock
bash scripts/keeper.sh 600                # keeper loop: pay the queue, harvest, rebalance, roll weekly, sync
bash scripts/timelock.sh schedule 'setBorrowingEnabled(bool)' false   # owner call, runs after 24 h
```

## Risks

Feasy is **unaudited and runs on testnet only**. The main risks:

- **Mainnet economics.** sMUSD now pays about 1% a year, against a loan that costs about 1.1%, so the loan side roughly breaks even on mainnet today. A mainnet launch waits until that improves, and new vaults deploy with borrowing off.
- **Locked BTC.** Up to the sleeve's share of the BTC is locked for up to 4 weeks. Exits larger than the liquid part wait for the next lock to end.
- **Recovery Mode.** Mezo blocks collateral withdrawals, so instant exits are limited to idle BTC until it ends, and larger exits queue.
- **Liquidation** needs a BTC drop of about 56% with nobody calling `rebalance()`. On staging, a -60% liquidation cost only the 200 MUSD reserve.
- **Mezo's upgradeable contracts.** The vault trusts Mezo's proxies. The sleeve stops new locks as soon as Mezo Earn's wiring changes.

The full list is in [risks](https://docs.feasy.org/risks) and [SECURITY.md](SECURITY.md).
