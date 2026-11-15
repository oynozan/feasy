# Mezo priorities, live apps, builder asks, problems, and partners (as of 2026-11-12)

Confidence key: "Cited" = read on the primary page (mezo.org) unless noted. "Inferred" = my reasoning. Several third-party search summaries were weak; they are flagged.

## 1. What Mezo says it is for, and its stated 2026 priorities

### Takeaway
Mezo's official 2026 roadmap has six pillars: scaling MUSD, MEZO utility and governance, institutional access, chain upgrades, ecosystem growth. It lists no dated milestones and calls all items aspirational. I found no dated 2026 Matt Luongo quote setting a numeric target.

### Cited Findings
- 2026 roadmap pillars: (1) Scaling MUSD: cross-chain MUSD as collateral, trading pair and spending asset; make Mezo the home of wrapped BTC (tBTC, WBTC, cbBTC, SolvBTC) earning yield; more BTC yield vaults across risk profiles; more debit and prepaid card partners beyond Bitrefill and Lolli. (2) MEZO utility and governance: simpler Earn onboarding, voting UI for veBTC holders directing emissions and revenue splits, a veNFT marketplace for veBTC and veMEZO priced in BTC, MEZO or MUSD, delegation, a Grant Committee. (3) Institutional: MUSD minting, MEZO custody and veMEZO locking via Anchorage Digital. (4) Chain: EVM upgrade from London-level spec; explore AI-agent payment rails. (5) Ecosystem: Founder Program for dApps integrating MUSD, hackathons, BitcoinFi Accelerator ($3M+ deployed from Draper Associates, Boost VC, Draper Dragon in two cycles), community bounties. The post says items are "aspirational and subject to change or cancellation without notice." — [Mezo's 2026 Roadmap](https://mezo.org/blog/mezo-2026-roadmap)
- Same post cites 1% fixed APR on BTC-backed loans and Prime Access launching at 40%+ APR, and first hackathon: nearly 400 participants, 37,500 MUSD across nine winners — [Roadmap](https://mezo.org/blog/mezo-2026-roadmap)
- Mainnet launched 2025-05-28 (testnet from Nov 2024) — [Mezo Mainnet is Here / launch coverage](https://chainwire.org/2025/05/28/mezo-launches-first-full-stack-bitcoin-economy-to-mainnet/)
- Luongo quote (via Banxa fiat on-ramp announcement, date not verified): "Bitcoin opened the door, but there's still a gap between holding it and actually being able to use it day-to-day." — [Banxa](https://banxa.com/press/mezo-integrates-with-banxa-to-enable-global-fiat-on-ramp-for-musd-and-bitcoin-backed-finance/) (reached only through a search summary, not read directly)
- Mezo's sponsored Defiant piece frames Mezo as "the infrastructure for a sovereign alternative": borrow against BTC instead of selling; MUSD "100% secured by Bitcoin collateral." Undated, sponsored — [The Defiant](https://thedefiant.io/news/defi/mezo-building-a-global-economy-on-bitcoin)
- Mezo's own Gauges post: "MUSD is only useful if it's liquid where people already are." Thin pools limit the MUSD debt book and pressure the peg (2026-09-11) — [Introducing MEZO Gauges](https://mezo.org/blog/introducing-mezo-gauges)
- Mezo pays 2.25% of total MEZO supply to Aerodrome veAERO voters in a 30-day campaign to make Aerodrome (Base) its primary liquidity hub (2026-03-26; secondary source, Whale Alert) — [Whale Alert](https://whale-alert.io/stories/849d01bf68a929/Bitcoin-Lending-Layer-Mezo-Selects-Aerodrome-as-Primary-Liquidity-Hub)
- Mezo posts on fixed-rate credit via Morpho Midnight (2026-08-10); the post does not mention MUSD — [How to Build a Bitcoin-Backed Credit Market](https://mezo.org/blog/how-to-build-a-bitcoin-backed-credit-market)

### Inferences
- Stated priorities in practice: MUSD liquidity off-Mezo (Curve, Uniswap, Aerodrome), MEZO/veMEZO demand, institutional BTC, and cards/payments.
- Mezo is distributing MUSD to other chains and venues, so a product that increases MUSD debt or demand outside Mezo fits directly.

### Gaps
- No Luongo or Mezo post with dated 2026 numeric targets (MUSD supply, TVL) found. The "H1 2026 in Review" post is listed on mezo.org/blog but its URL could not be fetched (404 on guessed slugs); a search snippet attributes "1,000 BTC deployed through Mezo Prime and $28M MUSD in circulation" to it, unverified.
- Podcast and conference talks not searched.

## 2. Live apps on Mezo and competitors

### Takeaway
Mezo's native stack already includes Mezo Borrow (CDP), MUSD Savings Vault (sMUSD), Mezo Pools, vaults, Earn/ve(3,3), Mezo Prime and a swap. Of Feasy's loop, the individual pieces are Mezo-native. I did not find a mainnet product that automates the full loop as one deposit-BTC vault, but search was shallow.

### Cited Findings
- Mezo Earn: dual-token matching market combining veBTC and veMEZO; audited by Halborn (2026-01-08) — [Mezo Earn docs](https://mezo.org/docs/users/mezo-earn/overview), [audit](https://mezo.org/docs/audits/2026-01-08%20-%20Halborn%20-%20Mezo%20Earn.pdf)
- MUSD Savings Vault: deposit MUSD, get sMUSD; yield from protocol fees accrues in exchange rate weekly. Staking sMUSD in the gauge redirects fee yield to veBTC voters in exchange for MEZO emissions. Docs list ~5% variable APR; an older blog post cites 29.45% fee APR plus 79.63% emissions APR (undated, likely stale) — [Savings Vault docs](https://mezo.org/docs/users/mezo-earn/vaults/musd-savings-vault), [blog](https://mezo.org/blog/stablecoin-yield-powered-by-bitcoin-earn-with-mezos-musd-vault)
- Mezo Prime (April 2026, with Anchorage Digital): institutional BTC in segregated Enclaves, depositors get veBTC, borrow MUSD at 1% fixed via Anchorage Porto. Bullish: 250 BTC as first customer plus a separate 250 BTC investment in Mezo. Site showed $72.4M TVL and $486.7M lifetime MUSD volume at that time — [Introducing Mezo Prime](https://mezo.org/blog/introducing-mezo-prime/), [crypto.news](https://crypto.news/mezo-launches-institutional-bitcoin-yield-vaults-with-anchorage-digital-and-bullish-including-250-btc-anchor-investment/)
- STRC yield (2026-07-20): MUSD/sUSDat pool; sUSDat is Saturn's vault token backed by STRC (Strategy Inc. preferred, variable ~12%); LP tokens stakeable in gauge — [How to Earn STRC Yield on Mezo](https://mezo.org/blog/how-to-earn-strc-yield-on-mezo)
- Morpho vault "alpha-musd" on Ethereum (2025-09-18) allocating to tBTC/MUSD and cbBTC/MUSD markets with Mezo incentives — [Mezo blog](https://mezo.org/blog/stack-sats-and-bitcoin-backed-stables-morpho-vault-incentives-go-live)
- MEZO Gauges (2026-09-11): ~200k MEZO per epoch by vote to MUSD/USDC/USDT Curve, MUSD/USDC Uniswap, MUSD/USDC and MUSD/MEZO Aerodrome — [Introducing MEZO Gauges](https://mezo.org/blog/introducing-mezo-gauges)
- Partners/apps named in 2025 sources: Tigris (veBTC, validator rewards), Bitrefill (gift cards), Lolli (cashback, also Thesis-owned), Fold, Xverse, Ledger, Wormhole, Magic Eden, Brotocol bridge, BitFire, Velar Perps, Upshift, NEAR Intents — [Mezo launch coverage](https://chainwire.org/2025/05/28/mezo-launches-first-full-stack-bitcoin-economy-to-mainnet/), [AlphaGrowth ecosystem list](https://alphagrowth.io/mezo-emb/ecosystem)
- Hackathon 2 (winners 2026-06-09) projects that overlap Feasy: Cermin (automates BTC-backed MUSD borrowing, spendable and savings split, repays debt when BTC falls), Cark (savings circles in MUSD), MezoPay (savings pots), BynD (pools veMEZO, routes boost to best veBTC), Mezoir (intent agent for the ve-economy), Fractals (fractional veBTC/veMEZO). Hackathon 1 (Oct 2025) winners included TrovePilot and KhipuVault — [Hackathon 2 winners](https://mezo.org/blog/announcing-mezo-hackathon-2-winners/), [search summary on H1 winners](https://mezo.org/blog/mezo-hackathon-winners)
- TVL history: ~$76.3M peak after "Bring Bitcoin Home" migration, ~$23.3M on 2026-04-01 (DefiLlama-based analysis, secondary); Mezo Borrow ~$3.57M on an undated DefiLlama snapshot; MUSD circulating ~18.9M (Mar 2026), ~20.4M (Apr 2026), ~30M (mid-Sep 2026) — [Yearn curation](https://curation.yearn.fi/report/mezo-musd/), [Yellow](https://yellow.com/asset/mezo-usd), [DefiLlama Mezo Borrow](https://defillama.com/protocol/mezo-borrow)

### Inferences
- Closest competitors to Feasy are Cermin (borrow + savings automation), BynD (boost routing) and KhipuVault (hackathon 1 winner); status on mainnet unverified. None found that bundles trove + sMUSD + gauge + veBTC + veMEZO boost with a fee.
- Mezo itself shipping a "simpler Earn onboarding" (roadmap) is a risk: the native UI could absorb the wrapper.

### Gaps
- DefiLlama chain page returned 403; no current Mezo-wide TVL, no per-app TVL for Nov 2026.
- Did not verify whether KhipuVault, Cermin or TrovePilot are live on mainnet.
- Mezo Pools TVL/depth not found.

## 3. What Mezo has asked builders to build

### Takeaway
Current buildathon (Akindo): DeFi and Access and Distribution tracks. Earlier hackathon: Bitcoin, MUSD and MEZO tracks with every project required to integrate both tokens.

### Cited Findings
- Current "Mezo Buildathon" (Oct 2026): tracks DeFi (borrowing, lending, looping, yield) and Access & Distribution. $7,000 in MEZO: Wave 1 Oct 16-26 ($2,000), Wave 2 Nov 2-15 ($5,000); winners and demo Nov 23. Idea starters: collateral integration, auto-compounding vault, pool or DEX integration, clearer borrowing/looping interface; Telegram/WhatsApp discovery tool, integration comparison platform, marketplace using MUSD/MEZO for payments, simpler wallet interface. Deployment on Mezo, Ethereum, Base, BSC or Mezo testnet. Note: this page was fetched from a guessed URL that succeeded as `mezo-buildathon-is-underway`; the blog list titles it "The Mezo Buildathon Is Underway: Build What's Next for MUSD and MEZO" — [Mezo buildathon post](https://mezo.org/blog/mezo-buildathon-is-underway), [blog index](https://mezo.org/blog)
- April 2026 hackathon (Encode Club, 6 weeks, posted 2026-04-13): Bitcoin, MUSD and MEZO tracks, $30,000 veMEZO prizes plus milestone grants; "Every project must integrate MUSD and MEZO." — [The Mezo Hackathon Is Back](https://mezo.org/blog/the-mezo-hackathon-is-back)
- Hackathon 2 results: payments and commerce 45% of 64 submissions, DeFi/lending 33%; Mezo says it treats the hackathon as the start of a relationship with follow-on grants and bounties — [Hackathon 2 winners](https://mezo.org/blog/announcing-mezo-hackathon-2-winners/)
- Roadmap funding channels: Founder Program, BitcoinFi Accelerator, Grant Committee, community bounties — [Roadmap](https://mezo.org/blog/mezo-2026-roadmap)

### Inferences
- Money is small ($7k buildathon, $30k hackathon); real funding paths are the Founder Program, Accelerator and Grant Committee.

### Gaps
- No Founder Program or Grant Committee terms or amounts found.

## 4. Problems Mezo has

### Takeaway
Thin MUSD liquidity, a modest MUSD supply, a recent security incident, and an in-house emissions budget are the visible pain points.

### Cited Findings
- Liquidity: Mezo says thin pools can limit the MUSD debt book and pressure the peg — [MEZO Gauges](https://mezo.org/blog/introducing-mezo-gauges)
- Peg: a DIA page says MUSD trades below $1 and PCV held ~15.0M MUSD of a bootstrap loan on 2026-10-02 (undated peg reading) — [DIA](https://www.diadata.org/map/global-stablecoins/stablecoin/musd-mezo/). Mezo's own disclosure warns that rapid BTC drops could trigger mass liquidations and destabilize the peg (via search summary).
- Security: 2026-10-05 veBTC exploit: 37 positions from 36 holders, ~5.52 BTC, chain and bridge paused, fixed 2026-10-06; Mezo plans to sunset native BTC wallet sign-up and bridge-ins, tighten bridge-out limits — [Incident report](https://mezo.org/blog/incident-report-october-5-2026). Earlier: Velar PerpDEX exploit, Jan-Feb 2026 — [Mezo blog](https://mezo.org/blog/velars-perpdex-exploited-on-mezo)
- Aerodrome pool incentives changing as Aero launches (2026-10-22), Mezo says veMEZO voting stays on Mezo — [Mezo blog index](https://mezo.org/blog)
- TVL fell from $76.3M to ~$23M by April 2026 (secondary, see section 2).

### Inferences
- Declining TVL and the October exploit make Mezo more receptive to audited, conservative products, and the planned bridge-in sunset makes onboarding harder (inferred gap: BTC-wallet users).
- veBTC concentration: no data found, only inferred from the Prime Enclaves design where institutions hold veBTC.

### Gaps
- No data on veBTC concentration, sMUSD yield now, or whether the peg is currently off.
- No source for "low demand for MUSD" beyond supply figures.

## 5. Partnerships an app could plug into

### Cited Findings
- Anchorage Digital (custody, Porto borrowing, Mezo Prime) and Bullish (250 BTC, listing MEZO and MUSD) — [Mezo Prime](https://mezo.org/blog/introducing-mezo-prime/), [Blockport on Bullish listing](https://blockport.io/latest-news/mezo-lists-mezo-bitcoin-backed-musd-bullish/)
- Banxa fiat on-ramp for MUSD — [Banxa](https://banxa.com/press/mezo-integrates-with-banxa-to-enable-global-fiat-on-ramp-for-musd-and-bitcoin-backed-finance/)
- Threshold (tBTC rewards), Wormhole (MUSD cross-chain; $750M lifetime volume report), Ledger, Xverse, Bitrefill, Lolli, Fold — [Threshold](https://www.threshold.network/blog/threshold-x-mezo), [Crypto Briefing](https://cryptobriefing.com/musd-750m-volume-wormhole-network/)
- Morpho (Ethereum vault, Midnight post), Aerodrome (Base), Curve and Uniswap via Merkl, Saturn/Strategy (sUSDat) — sources in section 2.

### Inferences
- Plug-in candidates for Feasy: Banxa/Xverse/Ledger for onboarding; Anchorage for institutional share class; Wormhole for MUSD cross-chain.

## Candidate gaps for an ambitious Feasy feature (all inferred from the above)
1. A veBTC/veMEZO position layer: pooled boost, fractional or liquid wrapper for Feasy's veBTC and veMEZO. Matches roadmap veNFT marketplace and MEZO utility, and hackathon winners BynD and Fractals show demand, so it is crowded.
2. Feasy vault share token (fsBTC-style) usable as collateral or a pool pair, tying MUSD and MEZO utility and adding Aerodrome/Curve depth for MUSD.
3. Automated Recovery/liquidation-protected loop for BTC-wallet savers with a fiat on-ramp, which overlaps Cermin and Mezo's own simpler Earn onboarding.
4. Governance bribe/gauge voting aggregator for MEZO Gauges (anyone can add rewards to gauges), which is new since 2026-09-11 and maps to the MEZO track.
