# Mezo onchain incentive mechanisms an app can tap (as of 2026-11-12)

Method note: sources are Mezo's own docs and blog (primary). Fetches were summarised by a small model, so exact wording should be re-checked before quoting. DefiLlama and Dune pages returned 403 or were not reachable. No live explorer reads were done. Mainnet live numbers are therefore thin and several conflict.

## 1. How MEZO emissions work, and can a third party get its own gauge?

### Takeaway
Emissions are a fixed curve (about 4.8M MEZO/week at launch, falling), split by a splitter tree into rebase, validators (20%), staking gauges (about 72% of rewards) and non-staking MEZO Gauges (about 8%). Pool gauges are permissionless for pools whose assets are whitelisted. Staking-gauge creation and MEZO (non-staking) gauges are not permissionless, and no public application process was found.

### Cited Findings
- Genesis supply 1,000,000,000 MEZO, circulating 500,000,000. Epochs are 7 days, starting Thursday 00:00 UTC. Votes in epoch N set emissions for epoch N+1. — [How MEZO Emissions Work](https://mezo.org/blog/how-mezo-emissions-work/); [Mezo Earn overview](https://mezo.org/docs/users/mezo-earn/overview)
- Emission rate curve: years 0-2 25% to 12.5%; years 2-4 12.5% to 6.25%; years 4-8 6.25% to 2%; 8+ years 2% terminal. — [How MEZO Emissions Work](https://mezo.org/blog/how-mezo-emissions-work/)
- Weekly emissions: week 0 (2026-04-02) 4,807,692 MEZO; week 13 4,788,583; week 52 (2027-04-01) 4,488,065; week 260 (2031-03-27) 1,672,756. Cumulative 855,643,904 at week 260 (85.56% inflation). Only every 13th week is on the page; the rest is in a linked CSV. — [Emissions Schedule](https://mezo.org/docs/users/mezo/emissions/)
- Rebase to veMEZO: E_rebase = E_t x R_liquid^2 x 0.5, where R_liquid = (total - veMEZO-locked)/total. At 50% locked the rebase is 12.5% of emissions; at 70% locked 4.5%. The remainder goes to the reward branch. — [How MEZO Emissions Work](https://mezo.org/blog/how-mezo-emissions-work/)
- Chain Splitter: validators 20%, ecosystem 80%. Ecosystem Splitter: 90% staking gauges, 10% non-staking gauges. Totals about 72% and 8% of rewards. — [How Gauges and Splitters Work](https://mezo.org/blog/how-gauges-and-splitters-work-on-mezo/); [Emissions Schedule](https://mezo.org/docs/users/mezo/emissions/)
- Conflict on splitter governance: the blog says veBTC holders can move the ratios by 1 percentage point per epoch; the governance page says the ratios are fixed and cannot be changed by voting. — [Gauges and Splitters](https://mezo.org/blog/how-gauges-and-splitters-work-on-mezo/); contradicted by [Governance](https://mezo.org/docs/users/mezo/governance/)
- Gauge types: staking gauges (DEX LP tokens, MUSD savings vault receipt), non-staking gauges (validators, ecosystem destinations), and veBTC boost gauges (one per veBTC NFT, distributes no emissions). — [How Gauges and Splitters Work](https://mezo.org/blog/how-gauges-and-splitters-work-on-mezo/); [Matching market](https://mezo.org/docs/users/mezo-earn/lock/vemezo/matching-market)
- Pool gauges: all Mezo assets (BTC, MEZO, mainnet tokens) are whitelisted in PoolsVoter `0x48233cCC97B87Ba93bCA212cbEe48e3210211f03`. A pool qualifies when both assets are whitelisted. Anyone calls `createPoolGauge(_poolFactory, _pool)`. Basic pool factory `0x83FE469C636C4081b87bA5b3Ae9991c6Ed104248`, CL pool factory `0xBB24AF5c6fB88F1d191FA76055e30BF881BeEb79`. — [Deploying Incentives](https://mezo.org/docs/developers/features/mezo-earn/deploying-incentives)
- MEZO Gauges (non-staking, voted by veMEZO, 8% of rewards) fund MUSD pools on Curve, Uniswap (Ethereum) and Aerodrome (Base). Eligible pools sit on an onchain allowlist in a remote gauge registry; "governance adds or removes pools"; not permissionless. Launch pools: Uniswap USDC/MUSD, Curve USDT/USDC/MUSD, Aerodrome USDC/MUSD and MEZO/MUSD. Anyone can post incentives on a gauge. — [MEZO Gauges](https://mezo.org/docs/users/mezo-earn/vote/mezo-gauges.md)
- Governance: only veBTC holders vote on proposals; veMEZO has no independent governance power. Formal governance (Governor-style) is listed as a possible future item. — [Governance](https://mezo.org/docs/users/mezo/governance/)
- Validator gauges live in ValidatorsVoter `0xe99a9ad5Ed26BD30e4DB25397f378817e9b9515a`; PoA contract `0x7B7C000000000000000000000000000000000011`. — [Validator Gauge](https://mezo.org/docs/developers/mezo-nodes/validator-gauge/)
- MUSD savings gauge: staking sMUSD in the MUSD Savings gauge earns MEZO, and the staker's share of fee revenue goes to veBTC voters of that gauge. The gauge competes with LP gauges for votes. Vault address `0xb4D498029af77680cD1eF828b967f010d06C51CC`. — [MUSD Savings Vault](https://mezo.org/docs/users/mezo-earn/vaults/musd-savings-vault.md)
- Alpha Builders program: criteria include a live dApp with onchain activity, EVM compatibility, Mezo Passport integration and an audit before mainnet; benefits include priority access to grant programs, not guaranteed. — [Mezo Alpha Builders](https://info.mezo.org/home/mezo-alpha-builders) (from a search summary, not fetched)
- Mezo Market featuring needs MUSD integration, a third-party audit submitted to the Supernormal Foundation, and mainnet deployment. — [dApp requirements](https://mezo.org/docs/developers/getting-started/dapp-requirements.md)
- The Mezo Earn Whitepaper PDF could not be parsed by the fetch tool; a local copy is at C:\Users\Ozan\.claude\projects\c--Users-Ozan-Desktop-Dosyalar-Web3-feasy\a8683437-eb10-443e-8caf-acab9629157a\tool-results\webfetch-1794451582797-60316g.pdf — [Whitepaper](https://mezo.org/docs/Mezo_Earn_Whitepaper.pdf)

### Inferences
- A Feasy fBTC/BTC pool or share-token/MUSD pool on Mezo Pools could get a voting gauge by itself via `createPoolGauge`, provided both tokens are in the PoolsVoter whitelist. fBTC is probably not whitelisted, so a whitelist request to Mezo is likely the real gate (unconfirmed; the docs only say mainnet tokens "have been whitelisted").
- Gauge creation gives no emissions by itself. Emissions flow only if veBTC voters vote for it, so Feasy must win votes (own veBTC, incentives).
- Arithmetic: 4.8M x 0.8 x 0.9 = about 3.46M MEZO/week to staking gauges at the launch rate, before rebase. The user's "over 500k a week" for the sMUSD gauge is consistent with it being one gauge among several.
- A Feasy-specific staking gauge for its own vault shares (not an AMM pool) has no documented route.

### Gaps
- Who approves whitelist additions and non-pool staking gauges, and any application process. Not documented.
- Current epoch emissions after rebase, and the live vote split by gauge. No live read.

## 2. veBTC, veMEZO, BoostVoter, boost gauges, bribes

### Takeaway
veBTC is 1-28 day BTC locks with 1x base weight; veMEZO (1 week to 4 years) only boosts veBTC up to 5x via per-NFT boost gauges. Anyone can post incentives on gauges. Mezo's sources disagree on some details.

### Cited Findings
- veBTC: lock 1 to 28 days, rounded down to full weeks, linear decay, base weight 1x. Bridge and chain fees go to veBTC holders as passive yield without voting. — [Mezo Earn overview](https://mezo.org/docs/users/mezo-earn/overview); [Gauges and Splitters](https://mezo.org/blog/how-gauges-and-splitters-work-on-mezo/)
- veMEZO: 1 week to 4 years (1,456 days), linear decay, up to 5x boost, no independent governance weight; earns incentives on boosted gauges plus rebase. — [veMEZO overview](https://mezo.org/docs/users/mezo-earn/lock/vemezo); a search summary reported a 1-year minimum on the Mezo Earn overview, which the fetched overview page did not show
- Boost depends on your share of total veBTC vs total veMEZO; it needs a "poke" to apply. Each veBTC NFT has its own boost gauge, which distributes no emissions. — [Overview](https://mezo.org/docs/users/mezo-earn/overview); [Matching market](https://mezo.org/docs/users/mezo-earn/lock/vemezo/matching-market)
- Any ERC-20 can be deposited into a boost gauge as incentive to attract veMEZO votes; veMEZO voters claim at epoch end. — [Matching market](https://mezo.org/docs/users/mezo-earn/lock/vemezo/matching-market)
- Matchbox (matchbox.markets) is a community-built boost market, not endorsed by Mezo, possibly unaudited. — same page
- veBTC pool gauge voters earn the swap fees or MUSD revenue of gauges they vote for. — [Gauges and Splitters](https://mezo.org/blog/how-gauges-and-splitters-work-on-mezo/)
- Aerodrome campaign precedent: 2.25% of MEZO supply over 4 weeks (0.5% liquid bribes week 1, then 1%, 0.5%, 0.25% as max-locked veMEZO). Published 2026-03-30. — [Aerodrome x MEZO](https://mezo.org/blog/aerodrome-x-mezo-2-25-of-token-supply-rewards)

### Inferences
- The fetched docs name no BoostVoter contract or address. Confirm from the contracts reference or GitHub (the public repo list I could see did not show it).
- A 5x multiplier needs a veMEZO share comparable to the veBTC share, so a protocol with little MEZO relies on incentives or on buying a permanent lock.

### Gaps
- BoostVoter and VotingEscrow addresses and ABI; the exact boost formula. Not in the fetched pages.
- veMEZO minimum lock conflict unresolved.
- Tigris (Mezo's incentive management system, mezo.org/blog/tigris-mezos-native-incentive-management-system) surfaced in search but the fetch returned 404; unread.

## 3. Fee streams

### Takeaway
Pool swap fees and MUSD revenue go to veBTC voters of the relevant gauge; MUSD protocol fees feed the savings vault (sMUSD) with a bootstrap-loan split; bridge fees go to veBTC. No app-level share was found.

### Cited Findings
- MUSD fees: interest 1-5% fixed APR; origination 0.1%; redemption 0.75% (paid by the redeemer in BTC); refinancing 0.02% of debt; 200 MUSD gas deposit. Interest and redemption fees fund the stability pool at launch; other fees split between bootstrap loan repayment and the Savings Vault, 50/50 initially, at least 50% to repayment until the loan is repaid, then all to the vault. — [MUSD fees](https://mezo.org/docs/users/borrow/fees.md)
- Conflict: the savings vault page says the 50/50 split covers all MUSD protocol fees including interest, while the fees page sends interest and redemption fees to the stability pool at launch. — [MUSD Savings Vault](https://mezo.org/docs/users/mezo-earn/vaults/musd-savings-vault.md) vs [MUSD fees](https://mezo.org/docs/users/borrow/fees.md)
- sMUSD yield: MUSD protocol fees plus BTC fees from loan operations converted to MUSD, distributed weekly, accruing in the sMUSD/MUSD exchange rate. No withdrawal fee, 0h timelock, strategist Mezo. Stakers in the gauge give their fee share to veBTC voters. — [MUSD Savings Vault](https://mezo.org/docs/users/mezo-earn/vaults/musd-savings-vault.md)
- Vault APR week of 2026-04-14: 29.45% fee-backed, 79.63% emissions, about 109% total (the sum is not stated by the article and the period was promotional). — [Pools and Vaults](https://mezo.org/blog/how-to-earn-yield-on-bitcoin-through-mezo-pools-and-vaults/)
- Pool stakers forgo trading fees, which go to veBTC voters. — [Emissions Schedule](https://mezo.org/docs/users/mezo/emissions/)

### Inferences
- Because staking sMUSD in the gauge hands your fee share to voters, a Feasy veBTC position voting the same gauge recaptures part of it. That is the logic of the current v8 sleeve.

### Gaps
- Percent splits of pool fees between voters and LPs; chain-fee volume. Not given.

## 4. App-level revenue shares, referral, builder fees, gas rebates

### Takeaway
No automatic app revenue share, referral fee or gas rebate was found. The routes are grants, Mezo Market listing, and incentives from emissions.

### Cited Findings
- Alpha Builders priority grant access and Mezo Market promotional support (section 1).
- Network gas is paid by users on mint, redeem, stake, claim. — [MUSD fees](https://mezo.org/docs/users/borrow/fees.md)
- The glossary (via search summary) says ecosystem gauges take about 8% of net emissions and fund grants and ecosystem development. — [Glossary](https://mezo.org/docs/users/resources/glossary)

### Gaps
- No builder-fee, referral or gas-rebate documentation found. This is absence of evidence only; confirm with the Mezo team.

## 5. Mainnet numbers right now

### Takeaway
Only partial and conflicting figures. No reliable live veBTC total, veMEZO total, sMUSD supply or rate, MUSD supply, or top gauges.

### Cited Findings
- DefiLlama Mezo Earn TVL (BTC in veBTC): $64.56M, ATH $69.88M on 2026-10-05, data through 2026-11-05, low $33.62M on 2026-05-13; staked MEZO about $1.68M. — [DefiLlama Mezo Earn](https://defillama.com/protocol/mezo-earn) (search snippet; direct fetch 403)
- MEZO price: CoinGecko page $0.003819, market cap $1.93M, FDV $3.86M, undated — [CoinGecko](https://www.coingecko.com/en/coins/mezo). CoinMarketCap $0.008058 (ATH $0.1415 on 2026-04-13), DefiLlama $0.0074 (low $0.0072 on 2026-08-13), Coinbase about $0.015, all via a search summary and undated, mutually conflicting. — [CoinMarketCap](https://coinmarketcap.com/currencies/mezo/); [DefiLlama token](https://defillama.com/token/mezo)
- Emission at launch 4.8M MEZO/week (section 1).

### Inferences
- At $0.004-0.008, about 4.5M MEZO/week is only about $18k-36k/week of total emissions, so MEZO emissions are a small dollar budget now. Wide spread between sources makes this a rough range.
- If veBTC TVL is about $64M and veMEZO about $1.7M, veMEZO is about 2.6% of veBTC by value, so a 5x boost is scarce (inferred from two unverified figures).

### Gaps
- sMUSD supply and rate, MUSD supply, total veBTC and veMEZO in tokens, top gauges by votes. Dune and the Mezo app were not accessed.

## 6. Becoming a large voter or liquid locker

### Takeaway
No liquid locker (Convex or Aura analogue) was found. Matchbox is the only third-party layer. veBTC locks are only 1-28 days, so a wrapper would be a rolling lock manager, not a long-lock vault.

### Cited Findings
- Matchbox is the only third-party boost market found; community-built. — [Matching market](https://mezo.org/docs/users/mezo-earn/lock/vemezo/matching-market)
- Ditto runs a MUSD savings vault product on Mezo. — [Docs index](https://mezo.org/docs/llms.txt) (title only)
- Search found nothing on a liquid locker. I report none found; this is not proof none exists.

### Inferences
- Voting power is veBTC (BTC locked), so a liquid locker would pool depositors' BTC into rolling veBTC locks and vote them; veMEZO is only the multiplier. Feasy already does this for its own slice.
- Depositors could exit within a month, so lock-in is weaker than at Curve or Balancer lockers.

### Gaps
- Whether Ditto, Matchbox or others aggregate votes; existing vote concentration; Dune data.
