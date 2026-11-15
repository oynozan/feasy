**Feasy turns BTC into more BTC on Mezo.** It has two products, both live on Mezo testnet.

- **Savings vault (fBTC).** Deposit BTC and get fBTC. The vault borrows MUSD against the pooled BTC at Mezo's fixed rate and keeps it all in Mezo's MUSD Savings Vault (sMUSD). The income above the loan cost is swapped back into BTC. Your exposure stays plain BTC, with no leverage.
- **Liquid veBTC (fveBTC and fveMEZO).** Lock BTC, or bring a veBTC lock you already hold, and get fveBTC. It earns Mezo's gauge fees and BTC rebates and redeems within four weeks. Lock MEZO and get fveMEZO, a permanent veMEZO lock that boosts every Feasy veBTC lock in return for a share of what they earn.

## Links

- **App:** https://feasy.org
- **Liquid veBTC:** https://feasy.org/lock
- **Pitch deck:** https://feasy.org/pitch ([PDF](https://feasy.org/pitch/feasy-deck.pdf))
- **Docs:** https://docs.feasy.org
- **What's new in Wave 2:** https://docs.feasy.org/changelog
- **Live contracts:** https://docs.feasy.org/contracts
- **Code:** https://github.com/oynozan/feasy
- **Every testnet transaction:** [vault log](https://github.com/oynozan/feasy/blob/main/deployments/testnet-log.md), [locker log](https://github.com/oynozan/feasy/blob/main/deployments/testnet-locker-log.md)
- **Security and testing:** [SECURITY.md](https://github.com/oynozan/feasy/blob/main/SECURITY.md)

## What's new in Wave 2

Each Wave 1 request, and what shipped for it:

- **Borrow only when it pays.** A spread guard measures what sMUSD really paid, from its yield index, and blocks new debt while that is below the loan cost. It refused a loan until it had a day of history ([tx](https://explorer.test.mezo.org/tx/0xb196c724c091cbf231122c3bb2b2234a44aa42c560ec8dfdd18186201e62d592)). It then let the vault open its first v8 loan, 2,179 MUSD, on Nov 11 ([tx](https://explorer.test.mezo.org/tx/0x1697d373f206f50d84d2621cceec8779642ecf7cd86a6efca1c48f96392f0b9a)).
- **An unwind that works in Recovery Mode.** While Mezo refuses to close loans, the guardian's `unwind()` now repays down to Mezo's minimum loan. The next `rebalance()` closes it once Mezo allows. Testnet can't enter Recovery Mode, so this is tested on Mezo's real MUSD code.
- **veBTC claimed and withdrawn on chain.** Four ended veBTC locks from Feasy's test vaults collected their fees and rebates and were withdrawn on Mezo's veBTC ([tx](https://explorer.test.mezo.org/tx/0xf85cdac3d6f81e9c6696d525a1b2e993ac73c43cd4a8e7333d2ba505868ee047)).
- **Risk handling on Mezo's real contracts.** The guardian unwound v7's live loan and moved its holders to v8 ([tx](https://explorer.test.mezo.org/tx/0xf504500badf0ca8da50a2ef03bd8ac0d6967e12aadba11b908d19dac6048938b)). Every linked transaction ran on Mezo's own testnet contracts, not a copy.
- **A business model.** The vault charges 10% of its profit, only on gains above the share price's previous high. The contract caps the fee at 20%, and any rise waits 30 days. On testnet the fee starts Dec 10. Liquid veBTC keeps 5% of its income.
- **More use for MUSD and MEZO.** Part of the vault's sMUSD is staked in Mezo's sMUSD gauge and earns MEZO. That MEZO goes into a permanent veMEZO lock, which boosts the vault's own veBTC through Mezo's BoostVoter. Liquid veBTC opens the same loop to anyone.
- **A pitch deck.** https://feasy.org/pitch
- **Handed over.** The vault's owner is now its own 24-hour timelock ([tx](https://explorer.test.mezo.org/tx/0xab63897960b36e37d5366a280c70b092bfd3b02ab4c7e5c660729a0b31adae4a)), and the keeper is a public GitHub Action that runs every 15 minutes.

## The problem it solves

Most BTC yield lends your BTC out or adds leverage. Feasy borrows too, but the dollars never buy BTC. They stay in savings and always cover the loan, so you keep plain BTC exposure and the yield comes back as BTC.

veBTC has its own gap. A lock is stuck for up to four weeks, and it only earns its full share when someone also holds veMEZO to boost it. Most BTC holders hold no veMEZO, and most MEZO holders have no veBTC to boost. Liquid veBTC pairs the two sides and turns both into tokens you can hold, send and redeem.

## How it stays safe

- Nobody can move user funds. The owner is a 24-hour timelock, and the guardian can only reduce risk.
- No new debt while sMUSD pays less than the loan costs.
- New profit reaches the share price over 7 days, so joining just before a payout and leaving right after earns nothing extra.
- Exits are paid instantly from the liquid part, and larger ones wait in a first-come queue.
- On a private copy of Mezo's MUSD system, even a −60% crash only cost the loan's 200 MUSD reserve.

## How we built it

I built Feasy alone. I shipped eight vault versions to Mezo testnet, each tested with real transactions before the next, and then Liquid veBTC.

- **187 Foundry tests** run on Mezo's own MUSD, sMUSD, DEX and Mezo Earn code. Only the BTC precompile is stood in, because Mezo publishes no testable version.
- **47 scenarios** run as calls against live testnet state.
- **Price shocks down to −60%** ran on a private copy of Mezo's MUSD system.
- **Slither findings** are triaged in SECURITY.md, and every live contract is verified on Sourcify.

**Stack.** Solidity 0.8.28, Foundry, OpenZeppelin, Slither and Sourcify for the contracts. Mezo's MUSD, sMUSD and its gauge, DEX, veBTC, veMEZO and BoostVoter. Next.js 16, React 19, TypeScript, wagmi, viem, RainbowKit, Mezo Passport and Tailwind for the app. Nextra for the docs, Docker for hosting and GitHub Actions for the keeper.

## Challenges

- **No forks.** Mezo's BTC token and oracle are precompiles, so a fork can't run Mezo. Feasy is tested on Mezo's own code and live testnet state, without mocking any Mezo contract.
- **The 24 KB contract limit.** v8's features only fit after the math moved into a linked library. The vault has 210 bytes to spare.
- **sMUSD has no rate getter.** The spread guard measures the rate from sMUSD's yield index, so it needs a day of history before the first loan.
- **20 precompile calls per transaction,** and `try`/`catch` doesn't refund them. Every entry point is budgeted.
- **Mezo's lock rules.** A veBTC lock merges only when it votes nowhere and isn't permanent, and a permanent veMEZO lock can't unlock in the same block it moves. The locker handles both.

More in [Building on Mezo](https://docs.feasy.org/building-on-mezo).

## What's next

- An audit, then a small mainnet beta. The spread guard keeps the vault from borrowing at a loss.
- Move Liquid veBTC's owner to the timelock. It is an unaudited MVP and still owned by the deployer.
- Put fee revenue into veMEZO, for a bigger boost on Feasy's veBTC every epoch.
- A harvest route through Mezo's concentrated pools, to cut swap slippage.
