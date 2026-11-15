# Ambitious analogs funded by chains or issuers, as models for one bold Feasy feature on Mezo (as of 2026-11-12)

Method note: about 17 searches and 5 page fetches. Many claims come from search summaries, not full-page reads; those are marked "(search summary)". Several searches returned only 2022-2024 material, dated below. Mezo facts are from mezo.org docs and blog (primary).

## Liquid lockers and vote aggregators (Convex, Aura, Velodrome Relay, Pendle wrappers, Mezo's own Boar)

### Takeaway
Every ve(3,3) chain got a liquid-locker layer that captured a large share of locked supply and then bribe or emission flow. Mezo already has the first one (Boar Finance, third party, tiny) and has put a veNFT marketplace on its 2026 roadmap, so the open lane is a larger, Mezo-blessed liquid veBTC / veMEZO wrapper. The grants these analogs got were small relative to the value they captured (about 0.3M to 3M tokens), except Pendle's ecosystem which used program-level chain incentives.

### Cited Findings
- Convex TVL peaked about $20-21B in early Jan 2022; DefiLlama shows about $505M as of 2026-11-07 — [FXStreet Jan 2022](https://www.fxstreet.com/cryptocurrencies/news/defi-protocol-convex-finance-crosses-20b-in-locked-value-202201031038), [DefiLlama](https://defillama.com/protocol/convex-finance) (search summary)
- Convex held 44% of all veCRV in 2022 (GSR report); a 2026 DEXTools guide says about 49% (weaker source) — [GSR](https://www.gsr.io/wp-content/uploads/2022/01/2022.1.21_Curve-Wars.pdf)
- Votium (vote-delegation bribe market for CVX) has processed over $1.4B cumulative bribes as of May 2026 per a guide; not independently verified — [DEXTools guide](https://www.dextools.io/news/what-is-convex-finance-cvx-curve-booster-defi-guide-2026)
- Delphi: vlCVX bribe yield peaked about 46% APR, then compressed to about $1 bribe per $1.90 emissions, i.e. the flywheel decays — [Delphi](https://members.delphidigital.io/reports/is-the-convex-flywheel-sustainable)
- Aura (Convex for Balancer): original Balancer DAO grant request about $300k to cover audits (secondary summary); reportedly 25%+ of veBAL in mid-2022, later 36%+ and 60%+ of BAL emissions directed — [Aura blog](https://blog.aura.finance/more-about-aura-finance-and-our-launch-plans), [Balancer forum](https://forum.balancer.fi/t/proposal-allowlist-aura-finance-in-balancer-votingescrow/2708?page=3), [Weekly Gauge](https://weeklygauge.substack.com/p/weekly-gauge-7-two-years-of-gauge)
- Aura needed Balancer to allowlist it in veBAL voting escrow, so the host protocol's permission was part of the deal — [Balancer forum](https://forum.balancer.fi/t/proposal-allowlist-aura-finance-in-balancer-votingescrow/2708?page=3)
- Velodrome received a 3,000,000 OP Optimism Foundation Partner Fund grant (2022); listed Relay (veNFT auto-compounder, operator-managed voting) among planned v2 upgrades; later a 200,000 OP grant for yield-bearing-asset liquidity (post dated 2024-11-02) — [Optimism forum](https://gov.optimism.io/t/ready-gf-phase-1-proposal-velodrome-finance/3736), [Velodrome Relay](https://medium.com/@VelodromeFi/velodrome-relay-d7cf5ff191f1)
- Velodrome says over 10% of veVELO supply uses Relay (team self-report) — [Velodrome Relay](https://medium.com/@VelodromeFi/velodrome-relay-d7cf5ff191f1)
- Pendle wrappers: Penpie and Equilibria launched June 2023, held about 24% and 26% of vePENDLE; Magpie ecosystem asked 1.25M ARB from Arbitrum STIP (500k ARB to Penpie LPs) and reported Arbitrum TVL of $193M by 2024-03-25, up 144% — [Nansen](https://research.nansen.ai/articles/the-pendle-wars-an-analysis-of-de-fi-s-latest-battleground), [Arbitrum forum](https://forum.arbitrum.foundation/t/magpie-penpie-radpie-campie-final-stip-round-1/16648)
- Pendle itself asked 2M ARB from STIP Round 1, 55% routed to pools by vePENDLE vote weight; reported about $547M Arbitrum TVL, up 832% (self-report) — [Arbitrum forum](https://forum.arbitrum.foundation/t/pendle-final-stip-round-1/17234), [Pendle addendum](https://forum.arbitrum.foundation/t/final-pendle-stip-addendum/23342)
- Mezo veBTC: 28-day max lock; veMEZO: 4-year max; 7-day epochs starting Thursday 00:00 UTC; veBTC earns bridging and chain fees; boost up to 5x from veMEZO via per-position boost gauges — [Mezo Earn overview](https://mezo.org/docs/users/mezo-earn/overview), [boost mechanism](https://mezo.org/docs/users/mezo-earn/lock/vemezo/boost-mechanism)
- Mezo's matching market lets veBTC holders post any ERC-20 incentive on a boost gauge to attract veMEZO votes; docs do not state whether the NFTs are transferable or mention liquid wrappers — [matching market](https://mezo.org/docs/users/mezo-earn/lock/vemezo/matching-market)
- Boar Finance (third party, post 2026-04-20): non-custodial vault, users deposit BTC or delegate veBTC, weekly auto-voting and compounding, 10% performance fee, 10.6 BTC delegated over first 5 epochs, "not a Mezo project and not endorsed"; no liquid receipt token — [Mezo blog](https://mezo.org/blog/set-it-and-earn-automated-vebtc-yield-with-boar-finance/)
- Mezo's 2026 roadmap lists a veNFT marketplace (list/buy veBTC and veMEZO for BTC, MEZO or MUSD), voting delegation, and a Grant Committee; "no automated strategies yet for veMEZO" at the time of the Aerodrome campaign — [Mezo roadmap](https://mezo.org/blog/mezo-2026-roadmap), [Aerodrome campaign](https://mezo.org/blog/aerodrome-x-mezo-2-25-of-token-supply-rewards)

### Inferences
- Feasy already holds veBTC and veMEZO for the vault, so it is a natural aggregator: a "liquid veMEZO" or "Feasy boost pool" that pools user BTC and MEZO to hit near-5x boost would be the Mezo analog of Convex/Aura. This is the strongest fit with Feasy's current architecture.
- Because Boar has only about 10 BTC delegated, the lane is open, but a wrapper likely needs Mezo to confirm veNFT transferability and the planned marketplace; check the veBTC contract before design.
- Funding precedent: Optimism-type grants (3M OP) went to the host-chain DEX, not to the locker. Lockers were funded by capturing emissions; the host's "yes" was permissioning (allowlisting) plus audits. Expect Mezo's route to be MEZO/veMEZO grants from the Grant Committee or hackathon-style veMEZO, not cash.
- Risk: Convex shows flywheel decay and centralization criticism (multisig control); Mezo may resist a wrapper that takes a large veMEZO share.

### Gaps
- Aura's and Pendle wrappers' current 2026 shares were not found.
- No primary source on exact Convex launch incentives (CVX distribution to LPs) was fetched.
- Whether Mezo veNFTs are transferable is unconfirmed; the roadmap marketplace implies yes.

## Stablecoin-ecosystem builders funded by the issuer (Spark/Sky, GHO/Aave, crvUSD/Curve, Ethena)

### Takeaway
Issuers fund products that create demand and distribution for their stablecoin. The most relevant precedents are Aave's 5M USD Merit program (GHO plus WETH incentives), Curve DAO's 60M crvUSD credit line to Yield Basis (a BTC-focused product), and Spark as an issuer-funded product arm. For MUSD, the equivalent is MEZO or veMEZO incentives for apps that mint and hold MUSD.

### Cited Findings
- Aave Merit initial budget: 2.1M USD in WETH plus 2.9M USD in GHO, 5M USD over 90 days, approved by Aave DAO; extensions continued into 2025 — [Aave governance forum](https://governance.aave.com/t/arfc-merit-a-new-aave-alignment-user-reward-system/16646), [Defiant](https://thedefiant.io/news/defi/aave-moves-to-launch-usd5m-quarterly-incentives-program)
- Aave Grants DAO funded a Native Bitcoin GHO Facilitator project (BTC light-client verified minting of GHO on Ethereum); amount not found — [Aave governance forum results](https://governance.aave.com/t/arfc-merit-is-forever-reward-system-program-extension/17336) (search summary)
- Curve DAO approved a credit line of up to $60M crvUSD for Yield Basis (BTC-collateral yield design); Curve DAO gets 7.5% of YB supply, 35-65% of value to veCRV lockers; a later proposal to raise to $1B surfaced; criticized as extractive — [Cointelegraph](https://cointelegraph.com/news/curve-dao-approves-60m-crvusd-yield-basis-bitcoin-pools), [Blockworks](https://blockworks.com/news/yield-basis-curve-dao-vote)
- Spark (Sky Star) allocated $1B (BUIDL $500M, USTB $300M, JTRSY $200M) after a governance vote 2025-04-03, plus $100M to USCC — [Decrypt](https://decrypt.co/318035/spark-commits-additional-1-billion-to-lead-tokenized-treasuries-sector) (search summary)
- Mezo's MUSD Savings Vault issues sMUSD, with staked sMUSD earning MEZO emissions; vault managed by August; about $28M MUSD in circulation at H1 2026 review per Mezo link; borrow rate 1% fixed — [Mezo docs](https://mezo.org/docs/users/mezo-earn/vaults/musd-savings-vault), [roadmap](https://mezo.org/blog/mezo-2026-roadmap)
- Mezo gave Aerodrome voters 2.25% of total MEZO supply over four weeks (week 1 0.5% liquid MEZO, weeks 2-4 1%, 0.5%, 0.25% as max-locked veMEZO) to make Aerodrome the MUSD/MEZO liquidity hub on Base (March 2026) — [Mezo blog](https://mezo.org/blog/aerodrome-x-mezo-2-25-of-token-supply-rewards)

### Inferences
- Mezo has shown it will spend token supply (2.25% of MEZO) on MUSD liquidity; a Feasy feature that creates MUSD demand (sticky MUSD borrowing plus sMUSD staking, which Feasy already does) matches that pattern. A "Feasy MUSD facilitator" analog is speculative.
- Yield Basis shows a stablecoin DAO will extend large credit to a BTC-collateral product that sends value back to lockers; for Mezo, the analog is a product that routes fees and boosted gauge rewards to veBTC/veMEZO holders.

### Gaps
- Ethena sUSDe and sDAI ecosystem grant amounts were not searched or found.
- Spark's own Maker/Sky funding terms not found.
- GHO builder grant sizes not found.

## BTC-yield and BTCfi programs on other chains (Stacks, BOB, Core, Botanix, Lombard, Babylon)

### Takeaway
Chains fund BTC vault and lending builders mostly via short, dated incentive programs paid in the chain token or BTC (Stacks 1 BTC per month, BOB 750k OP, Core accelerator). Amounts are modest (hundreds of thousands to low millions USD) and tied to measurable TVL or user deposits.

### Cited Findings
- Stacks 90-day DeFi incentive program with Zest and Bitflow: 1 BTC per month, half to Bitflow (sBTC/USDCx, STX/USDCx), half to Zest (sBTC or STX collateral, USDCx borrowing), Sept 10 to Dec 10 (Telegram post; year not stated in the summary, likely 2025); the Endowment will use data to design a long-term framework — [Stacks blog](https://www.stacks.co/blog/stacks-90-day-defi-incentive-program-announced-with-zest-and-bitflow)
- Stacks SIP-031 interim grants gave targeted liquidity support to Zest, StackingDAO, Bitflow, Hermetica and Granite — [Stacks Foundation](https://stacks.foundation/july-grants-update)
- Zest raised $3.5M led by Tim Draper (2024-05) — [CoinDesk](https://hotfix.coindesk.com/business/2024/05/13/zest-raises-35m-led-by-tim-draper-for-on-chain-bitcoin-lending-using-stacks)
- BOB Rise: 750,000 OP from Optimism Grant Season 6, 2025-02-24 to 2025-06-23, rewards for BTC deposits in DeFi protocols including a Veda-built HybridBTC.pendle vault; BOB also got a $375k Uniswap Foundation grant (May 2025) — [Blockmedia](https://www.blockmedia.co.kr/archives/864297) (search summary), [PR Newswire](https://prnewswire.co.uk/news-releases/bob-leads-the-next-era-of-bitcoin-defi-with-the-launch-of-hybrid-btc-yield-products-302387613.html)
- Core Ventures BTC-FI Accelerator launched Aug 2025, 14 weeks, 8 teams (funding amount not captured) — [Decrypt](https://decrypt.co/336421/core-ventures-launches-btc-fi-accelerator-to-empower-the-next-wave-of-bitcoin-defi-builders)
- Botanix stBTC: permissionless ERC-4626 vault, 50% of gas fees redistributed to holders — search summary, no direct link retained
- Lombard: LBTC across 9 ecosystems; 10% fee on Babylon staking yield; $250M BTC deposits at launch era (promotional post; unverified) — [Staking Rewards](https://www.stakingrewards.com/journal/research/lbtc-a-new-era-of-defi-for-bitcoin)
- Mezo side: BitcoinFi Accelerator with Thesis, over $3M upfront across two cycles; first hackathon about 400 participants, 37,500 MUSD to nine winners; Alpha Builder Program offers milestone grants and audit support to MUSD-integrating dApps; hackathon prizes in veMEZO with matching milestone grants (first place $5,000 plus $5,000) — [roadmap](https://mezo.org/blog/mezo-2026-roadmap), [Alpha Builders](https://mezo.org/docs/users/resources/mezo-alpha-builders), [hackathon](https://mezo.org/blog/the-mezo-hackathon-is-back/)
- Mezo Prime (Anchorage Digital and Bullish) launched with a 250 BTC anchor commitment — [crypto.news](https://crypto.news/mezo-launches-institutional-bitcoin-yield-vaults-with-anchorage-digital-and-bullish-including-250-btc-anchor-investment/)

### Inferences
- A vault builder's realistic Mezo ask is in the tens to low hundreds of thousands USD of MEZO/veMEZO, structured as milestones (Alpha Builder, Grant Committee), because that matches BOB/Stacks scale. Larger asks need a metric Mezo wants (BTC locked as veBTC, MUSD minted).
- Mezo Prime's 250 BTC anchor shows Mezo values BTC deposits that arrive with a credible partner.

### Gaps
- Bitlayer and Babylon foundation vault-builder programs: nothing found.
- Core accelerator dollar amount not captured.
- Whether the Stacks program year is 2025 or 2026 was not confirmed.

## Bold consumer products funded by chains (no-loss prize savings, cards, DCA, fixed rate, credit)

### Takeaway
The best-documented precedent is PoolTogether on Optimism (two OP grants, 1.0M OP total, deposits grew to $40M and 35k depositors). Mezo's own consumer path is spend-focused (Bitrefill gift cards, Lolli cashback, Fold card announced); a no-loss prize savings layer on sMUSD is unclaimed on Mezo as far as found.

### Cited Findings
- PoolTogether: Grant 1 of 450,000 OP (Foundation Partner Fund, 2022) and Grant 2 of 550,000 OP; second grant cut OP paid to depositors 30% (27,500 to 20,000 per week) while deposits reached $40M and 35,000+ depositors (2023); third grant planned, outcome unknown — [Optimism forum](https://gov.optimism.io/t/pooltogether-grant-2-update-moving-forward/5724), [PoolTogether OP grant #1](https://gov.optimism.io/t/review-gf-phase-1-pooltogether/3747)
- PoolTogether now has prize pools on Arbitrum, Optimism and Base (USDT, USDC, WETH) — [imToken support page](https://support.token.im/hc/en-us/articles/33452700472985-How-to-Interact-with-PoolTogether-on-imToken-to-Receive-NFT-Rewards)
- Mezo: MUSD spendable on Bitrefill gift cards (min $25); Fold debit card described as a coming integration (status unconfirmed); Lolli (also Thesis-owned) launched card-linked BTC cashback May 2026 — [Bitrefill](https://www.bitrefill.com/blog/mezo-x-bitrefill/), [The Block](https://www.theblock.co/news/business/2026-05-19-lolli-launches-automatic-bitcoin-cashback-on-linked-debit-and-credit-card-purchases-401837)
- Mezo roadmap: new card-issuing and payment partners, Anchorage institutional minting, "AI-ready" payment rails; no dedicated savings product, no fixed-rate changes announced — [roadmap](https://mezo.org/blog/mezo-2026-roadmap)

### Inferences
- A no-loss "prize sMUSD" (yield from the 1% borrow-funded sMUSD or staked-gauge MEZO emissions funds weekly prizes) fits Feasy's existing sMUSD staking and PoolTogether's proven grant model; Mezo could fund prizes in MEZO. This is the most "crazy but fundable" consumer idea found, but legal and gambling-regulation review is needed (not researched).
- A Feasy BTC-backed card or DCA is not tied to any chain-funded precedent found here.

### Gaps
- No chain-funded precedent found for BTC-backed mortgages, onchain payroll, or fixed-rate MUSD loans.
- Pendle-style fixed-rate products were only touched via Pendle wrappers, not as a consumer product.

## Candidate catalogue and ranking for Feasy (synthesis)

### Takeaway
Ranked by fit: (1) liquid veMEZO/veBTC booster pool (Convex/Aura model), (2) no-loss prize savings on sMUSD (PoolTogether model), (3) a BTC vault with MEZO incentives per Alpha Builder/BOB Rise model.

### Cited Findings
- See sections above; typical funding sizes: Aura about $300k, PoolTogether 1.0M OP, Velodrome 3M OP, BOB 750k OP, Magpie 1.25M ARB, Aave Merit $5M, Curve to Yield Basis $60M credit line, Mezo accelerator over $3M, Mezo Aerodrome campaign 2.25% of MEZO supply.

### Inferences
- Mezo's likely "yes" criteria, inferred from its own programs: raises MUSD supply or demand, locks BTC as veBTC or MEZO as veMEZO, deepens MEZO/MUSD liquidity, and has milestone-based structure.

### Gaps
- No direct statement from Mezo about whether it would fund a liquid-locker wrapper; the roadmap's Grant Committee terms are unpublished.
