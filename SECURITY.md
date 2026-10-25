# Security

This file covers the Feasy vault contracts. It sets out the scope, who can do what, what the vault depends on and its known limits. It also has a Slither run with every finding triaged, how the code was tested, and how to report a problem.

The vault is unaudited and runs on Mezo testnet only. The live vault is v7, which is v6 plus a veBTC sleeve. The v6 and v5 sections below stay as the record of the code it replaced.

## Summary

- **v7 scope:** everything below for v6, plus the veBTC sleeve [`contracts/src/VeSleeve.sol`](contracts/src/VeSleeve.sol), which the vault creates, and the linked library [`contracts/src/SystemMath.sol`](contracts/src/SystemMath.sol). Deployed at vault [`0x4DA2eb6942cF136126A630e4C968CE43474c0Db6`](https://explorer.test.mezo.org/address/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6), queue [`0xB4D1…13C3`](https://explorer.test.mezo.org/address/0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3), sleeve [`0xee76…209B`](https://explorer.test.mezo.org/address/0xee76C202a9e43988c55DC86816a6c14211Db209B) and SystemMath [`0x34df…57f7`](https://explorer.test.mezo.org/address/0x34df486c93DB9a2A263498df97BDDF04BF1d57f7).
- **What v7 adds to v6:**
  - up to four weekly veBTC locks that vote for the sMUSD gauge, and a keeper `roll()` that claims, releases, pays the queue and locks again;
  - a `rawAssets()` view.

  `rebalance()` never calls Mezo Earn, and every Mezo Earn call in `roll()` runs inside `try` on a fixed gas budget.
- **Slither on v7:** 95 findings, none a vulnerability. The 30 new ones are triaged in [v7 run](#v7-run).
- **v7 tests:**
  - The weekly cycle ran on a local chain of Mezo's verified code, with only the BTC precompile stood in. 17 of 17 tests pass, and the tested bytecode equals the deployed bytecode.
  - An independent check reran the tests. It found that a rebate claim paying veBTC's weekly catch-up outruns its gas budget, which costs rebates, never principal (see [Known risks](#known-risks-and-limits)). The keeper works around it.
  - Coverage passes 88 tests, and Preflight passes 42 of 42 on live testnet.
- **v6 scope:** the v6 vault [`contracts/src/Vault.sol`](contracts/src/Vault.sol) and its withdrawal queue [`contracts/src/RedeemQueue.sol`](contracts/src/RedeemQueue.sol), with the libraries [`ProfitLock.sol`](contracts/src/ProfitLock.sol) and [`QueueMath.sol`](contracts/src/QueueMath.sol) and the interface file. Deployed at [`0xb7A15aB24483Dfe92056F73279ECF11CE00675db`](https://explorer.test.mezo.org/address/0xb7A15aB24483Dfe92056F73279ECF11CE00675db) and [`0x4e580155d4d7957874cA88803646141E98f90cb6`](https://explorer.test.mezo.org/address/0x4e580155d4d7957874cA88803646141E98f90cb6) on Mezo testnet.
- **What v6 adds to v5:**
  - a 7-day profit unlock;
  - a guardian that can only stop new borrowing or close the loan, with borrowing off at deployment;
  - a first-come, first-served withdrawal queue;
  - a check that refuses DEX quotes while Mezo's pool factory is paused.

  Every other v5 function is byte for byte the same, including the Mezo edge-case guard `_repayBlocked()` and all three places it is used.
- **Slither 0.11.6 on v6:** 66 findings, none High, and no vulnerability. 20 Medium, 40 Low (24 of them timestamp uses in the unlock) and 6 Informational. The v6 triage follows the v5 one.
- **Review:** the five v6 designs were merged into [`docs/v6-spec.md`](docs/v6-spec.md), and a separate review pass fixed seven problems in it before any code was written. The worst was a dust request that could have frozen borrowing for good. The v5 line-by-line pass found no bug and records six design notes. This is not an audit.
- **Ownership:**
  - v5 is owned by an OpenZeppelin TimelockController with a 24 hour delay.
  - v6 has its own 24 hour TimelockController, set up the same way.
  - The keeper and the guardian each use their own key.

## Scope

### Code

| | |
| --- | --- |
| Contracts | [`contracts/src/Vault.sol`](contracts/src/Vault.sol), plus [`contracts/src/RedeemQueue.sol`](contracts/src/RedeemQueue.sol) and [`contracts/src/VeSleeve.sol`](contracts/src/VeSleeve.sol), which the vault creates in its constructor. The internal libraries [`ProfitLock.sol`](contracts/src/ProfitLock.sol) and [`QueueMath.sol`](contracts/src/QueueMath.sol) are compiled in. [`SystemMath.sol`](contracts/src/SystemMath.sol) is a public library, deployed on its own and linked. Also [`contracts/src/interfaces/IMezo.sol`](contracts/src/interfaces/IMezo.sol). |
| v7 deployment | Vault [`0x4DA2eb6942cF136126A630e4C968CE43474c0Db6`](https://explorer.test.mezo.org/address/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6), created at block 16356409. Queue [`0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3`](https://explorer.test.mezo.org/address/0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3), sleeve [`0xee76C202a9e43988c55DC86816a6c14211Db209B`](https://explorer.test.mezo.org/address/0xee76C202a9e43988c55DC86816a6c14211Db209B), SystemMath [`0x34df486c93DB9a2A263498df97BDDF04BF1d57f7`](https://explorer.test.mezo.org/address/0x34df486c93DB9a2A263498df97BDDF04BF1d57f7). All four are exact matches on Sourcify. The queue and the sleeve need `--libraries` too, because linking writes the library address into every contract's compiler settings. Runtime sizes: vault 24,476 bytes, sleeve 8,055, queue 4,165, SystemMath 1,398. |
| Deployment | v6 at [`0xb7A15aB24483Dfe92056F73279ECF11CE00675db`](https://explorer.test.mezo.org/address/0xb7A15aB24483Dfe92056F73279ECF11CE00675db) on Mezo testnet (chain 31611), created at block 16353457 in [`0xfd2a…477d`](https://explorer.test.mezo.org/tx/0xfd2ad943617c7ea7cbda29f8d88f7de5a48f3cf603766e2a2a0a69860210477d). Its queue is at [`0x4e580155d4d7957874cA88803646141E98f90cb6`](https://explorer.test.mezo.org/address/0x4e580155d4d7957874cA88803646141E98f90cb6). |
| Source verification | Sourcify exact match for the [vault](https://repo.sourcify.dev/31611/0xb7A15aB24483Dfe92056F73279ECF11CE00675db) and the [queue](https://repo.sourcify.dev/31611/0x4e580155d4d7957874cA88803646141E98f90cb6), on the runtime bytecode |
| Local build | Building `contracts/` with the settings below gives the live runtime bytecode of both contracts byte for byte, outside their immutables: 2,592 bytes of the vault's 23,771, and 192 of the queue's 4,144. Slither analyzed this build. |
| Shares | fBTC, ERC-4626 over the BTC token, 24 decimals (18 plus a 6-decimal offset against donation attacks) |

Out of scope: Mezo's contracts (the MUSD system, sMUSD and the DEX), OpenZeppelin Contracts, [`scripts/`](scripts/), the app, [`staging/`](staging/) and the Preflight harness in [`contracts/script/`](contracts/script/).

### Compiler and settings

From Sourcify's compilation record and [`contracts/foundry.toml`](contracts/foundry.toml).

| Setting | Value |
| --- | --- |
| Compiler | solc 0.8.28+commit.7893614a |
| Optimizer | on, 200 runs |
| EVM version | london, so no PUSH0 and no transient storage |
| Via IR | on for v6, which only fits under the 24,576 byte limit this way. v5 was built with it off. |
| Metadata | CBOR appended, IPFS hash |
| OpenZeppelin Contracts | v5.7.0 (commit `cab19933`) |
| Remapping | `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/` |
| Libraries (v7) | `src/SystemMath.sol:SystemMath` at `0x34df486c93DB9a2A263498df97BDDF04BF1d57f7` |

### Deployments

| Vault | Address | Status |
| --- | --- | --- |
| v7, live testnet | [`0x4DA2eb6942cF136126A630e4C968CE43474c0Db6`](https://explorer.test.mezo.org/address/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6), queue [`0xB4D1…13C3`](https://explorer.test.mezo.org/address/0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3), sleeve [`0xee76…209B`](https://explorer.test.mezo.org/address/0xee76C202a9e43988c55DC86816a6c14211Db209B) | Current, in scope |
| v7, test copies | [`0x8E1cB817CFd049969e71B1F5325eC2E54a4DC6a8`](https://explorer.test.mezo.org/address/0x8E1cB817CFd049969e71B1F5325eC2E54a4DC6a8) and [`0xeDb4B6AAE0DcdC5Af45Cb42cf7714807CC9a075c`](https://explorer.test.mezo.org/address/0xeDb4B6AAE0DcdC5Af45Cb42cf7714807CC9a075c), owned by the guardian wallet | Their first veBTC locks end on 2026-10-29. `0x8E1c` runs the final vault and sleeve code with the queue from before its last fix, and `0xeDb4` runs the sleeve from before the review fixes. Do not deposit. |
| v6, live testnet | [`0xb7A15aB24483Dfe92056F73279ECF11CE00675db`](https://explorer.test.mezo.org/address/0xb7A15aB24483Dfe92056F73279ECF11CE00675db), queue [`0x4e58…0cb6`](https://explorer.test.mezo.org/address/0x4e580155d4d7957874cA88803646141E98f90cb6) | Retired on 2026-10-25. Its loan is unwound and its holders moved to v7. The deployer keeps 0.0001 BTC in it until the last profit unlocks on 2026-11-01. |
| v6, 1 hour unlock copy | [`0x58c91F038a7d8aaD87FEF5e3c508ab4695FeD317`](https://explorer.test.mezo.org/address/0x58c91F038a7d8aaD87FEF5e3c508ab4695FeD317) | Same runtime code with `unlockPeriod` 3600, used to measure the release. Do not deposit. |
| v5, live testnet | [`0x2964612e8976b4003083E6014cA39f5fD7b41f3A`](https://explorer.test.mezo.org/address/0x2964612e8976b4003083E6014cA39f5fD7b41f3A) | Retired. Its trove is closed and its holders moved to v6. Only dust and one small position remain. |
| v5, staging | [`0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D`](https://explorer.test.mezo.org/address/0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D) | Same code as live v5 (identical runtime bytecode outside immutables), wired to the private MUSD copy |
| v4, staging | [`0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1`](https://explorer.test.mezo.org/address/0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1) | Superseded |
| v3, staging | [`0x741222d0cD7BeB527b9E45082eC20318Ff899e31`](https://explorer.test.mezo.org/address/0x741222d0cD7BeB527b9E45082eC20318Ff899e31) | Superseded |
| v2, staging | [`0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0`](https://explorer.test.mezo.org/address/0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0) | Superseded, same code as live v2 |
| v2, live testnet | [`0x29CE356E4ea91b1986402AA2311d17d7e2178B78`](https://explorer.test.mezo.org/address/0x29CE356E4ea91b1986402AA2311d17d7e2178B78) | Superseded. Its `rebalance()` reverts when Mezo refuses a close (staging Phase E1). |
| v1, live testnet | [`0x375Ef9f10cf75f138D6454F5253B8cEa65038e86`](https://explorer.test.mezo.org/address/0x375Ef9f10cf75f138D6454F5253B8cEa65038e86) | Superseded |

Superseded vaults are not maintained. Do not deposit into them.

## Trust model

On-chain reads in this section were taken on 2026-10-25 at block 16349995.

### Owner

- **v7:** owned by its own OpenZeppelin 5.7 TimelockController [`0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719`](https://explorer.test.mezo.org/address/0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719), verified on [Sourcify](https://repo.sourcify.dev/31611/0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719) (exact match), with the same roles as v6's. The sleeve takes the vault's `owner()` for its settings, so they wait 24 hours too.
- **v7 handover, 2026-10-25:** the timelock was deployed at zero delay. Then, in order:
  - [`transferOwnership`](https://explorer.test.mezo.org/tx/0x6f7aff7aefbd1d06d210059d931155c291d09f3950135f622c67d5a5b1fe6ede);
  - `acceptOwnership` [scheduled](https://explorer.test.mezo.org/tx/0x3059d8b91409e16b34c1c098194ea1d1d58325b603e0596fddb4c8acd587f010) and [executed](https://explorer.test.mezo.org/tx/0x6f67eb9dc0c5c1390e1d47673b448ef232edfba66cb7b4b748997ca2036a6c7e);
  - `updateDelay(86400)` [executed](https://explorer.test.mezo.org/tx/0x3e5d28fb83a1f11c4b3faa75f553b40384579fae7147ae4d741f9101508bfc96).

  The band, the sleeve and borrowing were set before the handover.
- **v6:** owned by its own OpenZeppelin 5.7 TimelockController [`0x2A4327156Cd2f4472282D1A636b424a86324803E`](https://explorer.test.mezo.org/address/0x2A4327156Cd2f4472282D1A636b424a86324803E), verified on [Sourcify](https://repo.sourcify.dev/31611/0x2A4327156Cd2f4472282D1A636b424a86324803E) (exact match). It has the same roles as v5's: the deployer is the only proposer and canceller, anyone can execute, and there is no admin.
- **v6 handover, 2026-10-25:** it was deployed at zero delay. Then, in order:
  - [`transferOwnership`](https://explorer.test.mezo.org/tx/0x2c38f69c671ef32d6a42815af7a84003d2806646d2f310f94dfeec9d939bb1d4);
  - `acceptOwnership` [scheduled](https://explorer.test.mezo.org/tx/0x30d69f7fe3478c0a3aaa215871e2044a1ba194ec0682914273a76dc45921fc64) and [executed](https://explorer.test.mezo.org/tx/0x63f8891914f147181d526aec42549346a4ac368c1cb74eef210de8291f22e0e4);
  - `updateDelay(86400)` [executed](https://explorer.test.mezo.org/tx/0xc595b448ea000f0545269b56beb9cccc3a27802093ace87ce4bae4139e87a504).

  Every owner call on v6 now waits 24 hours, as on v5. An earlier accept scheduled on v5's timelock was [cancelled](https://explorer.test.mezo.org/tx/0x1f6aa1a69edf700d3edc6495fb1935b772f3597b67fc86f4282646c3b1e64357).
- **v5:** the owner is the OpenZeppelin 5.7 TimelockController [`0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B`](https://explorer.test.mezo.org/address/0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B), verified on [Sourcify](https://repo.sourcify.dev/31611/0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B) (exact match).
- Its minimum delay is 86,400 s (24 h). Every owner call below is public on chain for 24 hours before anyone can execute it.
- The deployer [`0x90fE…5aF1`](https://explorer.test.mezo.org/address/0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1) is the only proposer and canceller. Anyone can execute a ready operation. There is no admin, so only the timelock itself can change its roles or delay, and those changes wait 24 hours too.
- The handover on 2026-10-25: [`transferOwnership`](https://explorer.test.mezo.org/tx/0xa10b6fc5c7f31ba1dffacc91df15d5432e003179254d782cc2ee8af541ee75ab), the timelock's [`acceptOwnership`](https://explorer.test.mezo.org/tx/0x6012157e7820a8ffb62ae24bafd6fc9a2faa977966b12ed8e09a64c3e2ac445f), then [`updateDelay(86400)`](https://explorer.test.mezo.org/tx/0xf0a26a35900b065dea8596fb3f9451954e942b8f5609eb9368547b138b48190b). Both steps ran at a zero delay before the 24 hour delay took effect. No ownership transfer is pending.
- Trade-off: on v5, an emergency `setBorrowingEnabled(false)` or `unwind()` also waits 24 hours. Anyone can still call `rebalance()` at any time to repay towards target. v6 adds the guardian below, which can take both brake steps at once.

| Function | What it does | Limits in code |
| --- | --- | --- |
| `setParams` | Sets `minCR`, `targetCR`, `maxCR`, `bufferBps`, `slippageBps`, `maxBorrowRate` and `depositCap` | `minCR` at least 150%. `minCR` < `targetCR` < `maxCR`. `bufferBps` at most 10,000. `slippageBps` at most 500 (5%). No limit on `maxBorrowRate` or `depositCap`. |
| `setKeeper` | Sets the keeper | Any address, zero allowed |
| `setGuardian` (v6) | Sets the guardian and emits `GuardianSet(previous, new)` | Any address. Zero leaves both brakes with the owner alone. |
| `setBorrowingEnabled` | Turns new borrowing on or off. v6 starts with it off. | Repayments, exits and buy-backs keep working |
| `pauseBorrowing()` (v6) | Turns new borrowing off. The guardian can do the same. | Storage only. No price read and no external call, so it works with a stale oracle. |
| `unwind()` | Turns borrowing off and closes the trove. It repays from savings and buys any MUSD shortfall with BTC. On v6 the guardian can also call it. | Reverts if Mezo refuses the close, as in Recovery Mode, and then it does not even pause. The swap has the same oracle bound as every other swap. |
| `harvest(maxIn)` | Same as the keeper while the trove is open | Same limits as the keeper |
| `VeSleeve.setSleeve` (v7) | Sets the sleeve's share of raw assets, an absolute cap and the ladder length. The sleeve checks the vault's `owner()`, so on testnet it waits 24 hours too. | Share at most 2,500 bps (25%). Ladder 1 to 4 weeks. The cap is unbounded. Locks already running keep their end dates. |
| `VeSleeve.setPaused(false)` (v7) | Resumes new locks after a pause | Only the owner. The guardian, the keeper or the owner may pause. |
| `transferOwnership`, `renounceOwnership` | Two-step transfer, or give up ownership for good | Renouncing removes every owner function. The keeper and the guardian stay. |

On v7 the owner cannot move a veBTC NFT, vote it for another gauge, or withdraw it anywhere but the vault. The sleeve has no function for any of these, and every Mezo Earn address in it is immutable.

v6 has no owner power over the profit unlock. `unlockPeriod` is a constructor immutable (7 days live, at most 30 days), and the queue has no owner at all.

Live v7 settings: band 2.0 / 2.2 / 2.4, buffer 2%, slippage 4%, max borrow rate 2%, no deposit cap, borrowing on, and a 5% sleeve on a 4-week ladder with no cap. The test wallets hold 0.069 BTC, and Mezo's 2,000 MUSD minimum loan needs spare BTC × price / `maxCR` of at least 2,000, so the band sits lower and the sleeve stays small.

Live v6 settings until 2026-10-25: band 2.0 / 2.5 / 2.8, buffer 3%, slippage 4%, max borrow rate 2%, no deposit cap, borrowing on. The test wallets hold too little BTC to open a trove at the 3.0 upper bound, so it sits at 2.8. v5 ran with 2.0 / 2.5 / 3.0.

Changing `slippageBps` also moves the share price. See note 4 under [Manual review notes](#manual-review-notes).

The owner cannot:

- send BTC, MUSD or fBTC to an address it picks. BTC leaves only to the receiver of a withdraw or redeem, to Mezo as collateral, to the router as swap input, or, on v6, to the vault's own RedeemQueue for a fill. The queue pays each request only to the receiver fixed when it was made. MUSD leaves only to sMUSD, to Mezo as repayment, or to the router.
- mint or burn anyone's shares.
- change the Mezo, sMUSD, router or pool factory addresses. They are immutable.
- upgrade the vault. It is not a proxy.
- pause withdrawals or redemptions. There is no pause. The band settings do decide how much collateral stays locked in the states where exits are limited (see [Known risks and limits](#known-risks-and-limits)).
- sell more in a harvest, while the trove is open, than the MUSD above what the loan owes plus a 0.1% cushion.

### Guardian (v6)

- The guardian is the EOA [`0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE`](https://explorer.test.mezo.org/address/0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE), set in the constructor. Its key is kept apart from the keeper's, which also lives in GitHub Actions secrets.
- It can call `pauseBorrowing()` and `unwind()`, and on v7 the sleeve's `setPaused(true)`, and nothing else. All three only move the vault toward less risk. A sleeve pause stops new locks, while the running ones still end and come back on schedule.
- It cannot re-enable borrowing, change settings, the keeper or itself, harvest an open trove, or touch ownership.
- A live role matrix, sent from each role's own address by `eth_call`, passed all 17 checks. Real transactions then showed:
  - the guardian's pause,
  - the owner's re-enable,
  - the guardian's unwind with no trove, which only turns borrowing off.

  The record is the v6 section of [`deployments/testnet-log.md`](deployments/testnet-log.md).
- A leaked guardian key can unwind at a bad moment. Each unwind costs a fresh borrow fee at the next open and possibly a buy-back spread. It can repeat only after the owner re-enables borrowing, so rotate the guardian in the same timelock batch.

### Keeper

- The keeper is the EOA [`0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23`](https://explorer.test.mezo.org/address/0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23), set in [`0x34e3…345a`](https://explorer.test.mezo.org/tx/0x34e3409180fb33728f2246b5c1415bb122be044f5867786630a7a28404e3345a).
- While the trove is open, only the keeper or the owner can call `harvest(maxIn)`. A stranger cannot sandwich the sale inside their own transaction.
- A harvest sells only the MUSD above what the loan owes plus a 0.1% cushion. Its minimum BTC output is the PriceFeed price less `slippageBps`.
- On v7 only the keeper's `roll()` locks new BTC. A lock sized off assets a deposit had just raised would let a depositor steer it, so anyone else's roll only claims, releases and pays the queue. The keeper may also pause new locks, and `scripts/keeper.sh` does so when Mezo Earn's wiring or any of its implementations change.
- The keeper has no other power.
- Safety does not depend on the keeper, because `rebalance()` is open to anyone.

### Anyone

- `deposit`, `mint`, `withdraw` and `redeem` (ERC-4626), and `depositBTC` for native BTC.
- `rebalance()`. It claims surplus collateral. It opens the trove, or adds idle BTC above the buffer as collateral. Under `minCR` it repays toward the target from savings, or closes the trove when even the lowest reachable loan stays under `minCR` and Mezo allows the close. Over `maxCR` it borrows toward the target, if borrowing is allowed. When the trove's borrowing capacity is too low, it refinances first, but only if that does not raise the trove's rate. It then buys back the MUSD gap and parks MUSD in sMUSD.
- `rebalance()` sells BTC only to buy back the MUSD gap, or a shortfall when it closes the trove.
- `harvest(maxIn)` once the trove is closed.
- On v6, the queue and the unlock are also open to anyone:
  - `requestRedeem(shares, receiver, owner)` on the queue escrows the owner's shares, with the same allowance rule as `redeem`.
  - `processQueue(maxAssets)` pays the oldest requests at the share price, releasing collateral exactly as an instant exit of that size would.
  - `claim(ids)` pays each request's BTC to the receiver fixed when it was made.
  - `sync()` takes a checkpoint that never moves the share price.
  - `rebalance()` and `harvest()` also fill the queue, but only from BTC the vault already holds. They never move the trove for it, so the queue can never make them revert.

On v7 anyone can also call `roll()` once the weekly vote window opens, an hour after Thursday 00:00 UTC. It claims every lock's MUSD fees and BTC rebate, resets and withdraws the locks that ended, parks the MUSD in sMUSD, and fills the queue from BTC the vault holds. A lock Mezo refuses to release emits `RungStuck` and stays counted at face value.

Borrowing is allowed only when `borrowingEnabled` is on, Mezo is not in Recovery Mode, and Mezo's rate is at most `maxBorrowRate`. On v6, the queue must also be empty. A fill that empties the queue always runs, even one that pays 0 BTC, so a dust request cannot hold borrowing shut.

### Mezo

- These Mezo contracts are EIP-1967 upgradeable proxies on testnet, per the Mezo explorer: BorrowerOperations, TroveManager, PriceFeed, ActivePool, CollSurplusPool, SortedTroves, HintHelpers, InterestRateManager and sMUSD.
- Whoever holds their upgrade keys can change how they behave. The vault trusts that.
- The MUSD token and the DEX router are not proxies. The MUSD/BTC pool is a minimal clone of the factory's pool code.
- Mezo Earn's veBTC, Voter and booster are upgradeable proxies too. The sleeve trusts them with the BTC it locks. Its defences:
  - `live()` checks before every new lock that veBTC, the Voter, the distributor and the gauge still point at what the constructor saw;
  - `rebalance()` reads only the sleeve's own storage, so it never calls Mezo Earn;
  - each lock's weekly work runs in its own `try` on a fixed gas budget, so one broken call costs only its own lock.

## External dependencies

Live testnet addresses. The vault takes BorrowerOperations, HintHelpers, sMUSD, the router, the pool factory and the BTC token as constructor arguments. It reads the other Mezo addresses from BorrowerOperations at deployment. All of them are immutable.

| Dependency | Address | Used for |
| --- | --- | --- |
| BorrowerOperations | [`0xCdF7028ceAB81fA0C6971208e83fa7872994beE5`](https://explorer.test.mezo.org/address/0xCdF7028ceAB81fA0C6971208e83fa7872994beE5) | Open, adjust, add and withdraw collateral, refinance, close, claim surplus |
| TroveManager | [`0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0`](https://explorer.test.mezo.org/address/0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0) | Trove debt and collateral, status, capacity, rate, Recovery Mode, system totals |
| PriceFeed | [`0x86bCF0841622a5dAC14A313a15f96A95421b9366`](https://explorer.test.mezo.org/address/0x86bCF0841622a5dAC14A313a15f96A95421b9366) | BTC price for share pricing and swap limits |
| SortedTroves, HintHelpers | [`0x722E4D24FD6Ff8b0AC679450F3D91294607268fA`](https://explorer.test.mezo.org/address/0x722E4D24FD6Ff8b0AC679450F3D91294607268fA), [`0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6`](https://explorer.test.mezo.org/address/0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6) | Insert hints |
| ActivePool, CollSurplusPool | [`0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51`](https://explorer.test.mezo.org/address/0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51), [`0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9`](https://explorer.test.mezo.org/address/0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9) | The only senders `receive()` accepts native BTC from. CollSurplusPool also holds surplus collateral. |
| InterestRateManager | [`0xD4D6c36A592A2c5e86035A6bca1d57747a567f37`](https://explorer.test.mezo.org/address/0xD4D6c36A592A2c5e86035A6bca1d57747a567f37) | Mezo's current rate, for `maxBorrowRate` and the refinance rule |
| MUSD | [`0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503`](https://explorer.test.mezo.org/address/0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503) | The loan token |
| sMUSD (MUSD Savings Vault) | [`0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`](https://explorer.test.mezo.org/address/0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16) | Holds the borrowed MUSD and pays savings income |
| Mezo DEX Router | [`0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9`](https://explorer.test.mezo.org/address/0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9) | Harvests (MUSD to BTC) and buy-backs (BTC to MUSD) |
| Pool factory, MUSD/BTC pool | [`0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A`](https://explorer.test.mezo.org/address/0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A), [`0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9`](https://explorer.test.mezo.org/address/0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9) | The single volatile pool every swap routes through |
| BTC token | [`0x7b7C000000000000000000000000000000000000`](https://explorer.test.mezo.org/address/0x7b7C000000000000000000000000000000000000) | The vault asset, a precompile |
| veBTC (v7) | [`0x38E35d92E6Bfc6787272A62345856B13eA12130a`](https://explorer.test.mezo.org/address/0x38E35d92E6Bfc6787272A62345856B13eA12130a) | The sleeve's locks, at most 28 days each |
| Pools Voter (v7) | [`0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D`](https://explorer.test.mezo.org/address/0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D), a constructor argument | Votes for the sMUSD gauge, and the gauge, fee and bribe addresses |
| sMUSD gauge, fees and bribe rewards (v7) | [`0xA6972f35550717280f2538EA77638B29073e3F07`](https://explorer.test.mezo.org/address/0xA6972f35550717280f2538EA77638B29073e3F07), [`0x613F6386A6549d29a1488F5246C58cE54B128ED4`](https://explorer.test.mezo.org/address/0x613F6386A6549d29a1488F5246C58cE54B128ED4), [`0x7D95237854f8Fa8F36c1280860E03736d0150BB1`](https://explorer.test.mezo.org/address/0x7D95237854f8Fa8F36c1280860E03736d0150BB1) | MUSD fees and bribes for the sleeve's votes |
| RewardsDistributor and its ChainFeeSplitter (v7) | [`0x9050218f89F0b5b17df4a30Ba4Fc97C72E307442`](https://explorer.test.mezo.org/address/0x9050218f89F0b5b17df4a30Ba4Fc97C72E307442), [`0x814b08D5293689F5F57f8B31E40A7903C0A4E191`](https://explorer.test.mezo.org/address/0x814b08D5293689F5F57f8B31E40A7903C0A4E191) | The weekly BTC rebate. A claim reverts until the splitter's permissionless `updatePeriod()` has run for the week. |

What the vault assumes about them:

- **PriceFeed staleness.** The verified implementation behind the proxy, [`0xec42B37C12b8D73d320f4075A1BCd58B306629c1`](https://explorer.test.mezo.org/address/0xec42B37C12b8D73d320f4075A1BCd58B306629c1), sets `MAX_PRICE_DELAY = 60`. Once the price is more than 60 seconds old, `fetchPrice()` reverts.
- **Stale price in the vault.** Deposits, withdrawals, `rebalance()` and `harvest()` then revert, the `max*` views return 0, and `totalAssets()` uses the last price a state change saw.
- **Swap bounds.** Every swap is bounded by the PriceFeed price, with `slippageBps` against the vault. The router passes empty callback data to the pool.
- **sMUSD payouts.** sMUSD is a 1:1 receipt token with a yield index, not ERC-4626. `withdraw` also pays all accrued yield. Exits that repay debt need sMUSD to pay out.
- **One BTC balance.** Native BTC and the BTC ERC-20 are one balance on Mezo. A read of both for the vault returned the same value. The vault counts idle BTC with `address(this).balance` and pays exits through the ERC-20.
- **Donations.** `receive()` refuses native BTC from anyone but ActivePool and CollSurplusPool. An ERC-20 transfer cannot be refused, so a donation adds to every holder's value. On v6 it is locked like any other gain and released over 7 days. A live 0.0001 BTC donation left `totalAssets` unchanged until `sync()` locked it, with an end exactly 604,800 s later.
- **A paused DEX still quotes.** Mezo's pool factory has a pauser key, an EOA on testnet. While paused, every pool swap reverts, but the router's `getAmountsOut` still quotes. v5 trusted the quote. v6's `_canBuy` reads `isPaused()` first and treats a paused or unreadable factory as unable to buy, so the max views cannot promise a close the pool would refuse.
- **20 precompile calls per transaction.** The BTC token and the price oracle are precompiles, and `PriceFeed.fetchPrice()` costs two calls. The 21st call burns all of its gas. The vault reads the price once per transaction into a snapshot. The README puts the heaviest call (refinance, borrow and buy-back in one rebalance) at about 13.
- **The cap inside `try` (v7).** In mezod, every precompile call past the 20th fails, a reverted one still counts, and a `try` does not reset the count. A heavy roll that ran over would therefore show as `RungStuck` rather than revert. Counted from the code, the worst `roll()` uses 15: the price 2, four rebates, four withdraws, one sweep and two new locks at 2 each. The local lifecycle test counted the same 15 with all four locks matured. On live testnet, Preflight scenario 41 measured the first roll, which opens two locks, at exactly the 6 calls the count predicts.
- **Gas estimates and `try` (v7).** A caught out-of-gas makes `eth_estimateGas` settle on a limit where the caught call fails quietly. `collect()` and `roll()` check `gasleft()` before each caught call and give each a fixed budget: 2.5M per lock's weekly work, 600k per claim and 3M per new lock. The local test's worst lock used 1.42M, and the lock 1.60M. The reserve checks raise the gas limit a roll needs above what it uses. The measured minimums are 3.37M for the first roll, up to 6.47M for ladder weeks, and 6.54M with four matured locks plus a queue fill. All fit under the 10M block limit and the scripts' 9.5M cap.
- **Gas estimates.** `eth_estimateGas` comes in low for calls through the BTC precompile, so clients should pad it. Mezo bills max(gas used, half the limit), so a 1.5x pad costs nothing. The scripts pad by 1.5x.
- **Max views move.** The loan's debt grows every second, so `maxWithdraw` and `maxRedeem` can drop by a few wei between reading and sending. Leave 0.001% of room.

## Known risks and limits

These match the README's [Risks and limits](README.md#risks-and-limits) section.

| Risk | What happens |
| --- | --- |
| Unaudited | Testnet only. The README records four independent review passes and the staging phases on v5, and the design review of v6. Every finding is fixed or listed there. |
| Yield timing | Profit reaches the share price linearly over 7 days, so depositing just before a payout and leaving right after earns nothing extra. A payout that accrued while one group held is released to whoever holds in the week after. A loss smaller than the lock leaves the share price flat and slows the release instead. |
| Recovery Mode | Mezo blocks collateral withdrawals. Instant exits are limited to idle BTC until it ends, and `rebalance()` keeps idle BTC out of the trove meanwhile. A larger exit waits in the queue and is paid as liquidity returns. |
| Queue order | Requests are paid first come, first served, ahead of instant exits, at the share price of each fill. In a long restricted state the earliest requests take the liquid BTC first. Value per share stays equal, only the order of liquidity changes, which replaces v5's pure pro-rata sharing. A request cannot be cancelled. While one waits, the vault takes no new debt and moves no idle BTC into the trove. |
| Shares sent to the queue | fBTC transferred straight to the queue address, rather than through `requestRedeem`, is not a request. It is never burned and stays there for good. |
| Exit during an unlock | An exit, queued or instant, is priced at the unlocked total. A holder who leaves mid-unlock leaves their unreleased part to the holders who stay. |
| Guardian | It can only pause borrowing or unwind. `unwind()` fails whenever Mezo refuses the close, as in Recovery Mode, so the guardian pauses first. |
| Pool far from the oracle | If the MUSD/BTC pool can't fill the fee buy-back within the slippage setting, the gap stays. Part of the collateral is then locked until yield covers it or the owner raises slippage (5% at most). The testnet pool sits about 2.6% below the oracle, so testnet uses 4%. |
| Oracle outage | If the price is more than 60 seconds old, Mezo halts borrowing and so does the vault. Deposits and withdrawals revert, `max*` views return 0, and `totalAssets` uses the last price seen. |
| Liquidation | The loan is liquidated only after a BTC drop of about 56% with nobody calling `rebalance()`. On staging, -50% in one block left it at 125%, and -60% got it liquidated. The vault kept its MUSD and lost only the 200 MUSD liquidation reserve. |
| Last trove | If the vault holds Mezo's only trove, Mezo never lets it close. Exits stop at the collateral the 2,000 MUSD minimum needs. The vault also covers a Mezo-side edge case where the last trove cannot take a repayment. Exits then release collateral only above 200% of today's debt. |
| Swap liquidity | The mainnet MUSD/BTC pool is thin, so harvests there should be chunked with `harvest(maxIn)`. |
| Redemptions | A redemption against the vault's trove swaps some BTC for MUSD at the oracle price. The next harvest buys the BTC back. |
| Mainnet economics | Not a security bug, but it decides when borrowing is safe to turn on. At the README's numbers the strategy roughly breaks even on mainnet. MUSD also trades about 1% under the oracle, which would make a new vault trove the first redemption target. A mainnet launch waits until both improve, with borrowing off by default. v6 deploys with `borrowingEnabled` off, so a mainnet deployment holds plain BTC until the owner turns borrowing on through the timelock. |
| Locked BTC (v7) | Up to the sleeve's share is locked for up to `lockWeeks` weeks, 5% and 4 weeks on testnet. An exit larger than the liquid part waits in the queue for the next lock to end. No new lock happens while a request waits. |
| Mezo Earn changes (v7) | A Voter swap leaves a voted lock unable to withdraw until Mezo re-adds the old voter as a secondary one. The local test showed `RungStuck` for that lock, the other locks unaffected, and a clean release after `addSecondaryVoter`. A killed gauge stops new locks, while running locks still end and are withdrawn. |
| Rebate catch-up (v7) | Found by the independent check. The first veBTC write after the Thursday flip pays veBTC's global checkpoint catch-up. A rebate claim that is that first write needs 665k gas locally, more than its 600k budget, against 414k with a fresh checkpoint. Each failed claim reverts its own catch-up, so that roll skips every lock's rebate. On testnet, the first veBTC write after each of the last six flips came at 03:00 UTC or later, after a 01:00 roll, so it would hit every week. The rebates stay claimable. A lock that has ended and still can't claim is released after the one-day grace, and gives up its unclaimed rebates. Mitigation: `scripts/keeper.sh` calls veBTC's permissionless `checkpoint()` right before each roll, which on testnet estimated at 192k. The fix for the next deployment is built. `collect()` runs `ve.checkpoint()` on its own 1M budget before any claim. All 30 distinct local tests pass on it, including the verifier's defect tests (46 runs, since one suite inherits another), and the heaviest roll stays at 15 precompile calls. Principal is never at risk. |
| Other reward tokens (v7) | The sleeve claims MUSD only. The testnet bribe contract also lists MEZO, mUSDT and mFBTC. None were paid in the last three epochs, and any that are stay unclaimed once a lock is withdrawn. |
| Owner powers | See the trust model. The owner cannot move user funds. |

## Slither

### How it ran

| Tool | Version |
| --- | --- |
| Slither (`slither-analyzer`) | 0.11.6 |
| crytic-compile | 0.4.2 |
| solc-select | 1.2.0, with solc 0.8.28 selected |
| Foundry (`forge`) | 1.8.6 |
| Python | 3.12.6 |

The run was on 2026-10-25, in a fresh virtual environment on Windows (Git Bash). On Linux or macOS the venv's scripts sit in `bin/` instead of `Scripts/`.

```bash
python -m venv venv
venv/Scripts/python -m pip install slither-analyzer solc-select
source venv/Scripts/activate
solc-select install 0.8.28
solc-select use 0.8.28
cd contracts
slither src/Vault.sol --compile-force-framework foundry --skip-clean \
    --exclude-dependencies --json slither-vault.json
```

- crytic-compile builds through Foundry with `forge build --build-info --deny never src/Vault.sol`. The analysis therefore uses `foundry.toml`'s compiler, EVM version, optimizer and remappings.
- `--skip-clean` stops crytic-compile from running `forge clean` on the project first.
- `--exclude-dependencies` drops results whose elements all sit in `lib/`.
- The run also pointed `FOUNDRY_OUT` and `FOUNDRY_CACHE_PATH` outside the repo, so the project's own build output stayed untouched. This does not change the analysis.
- Slither ran 102 detectors over 30 contracts: the vault, the IMezo interfaces and the OpenZeppelin code it imports.
- The raw JSON is not committed. The command above regenerates it.

### Results

| Severity | Findings | True positive | False positive | Accepted by design |
| --- | ---: | ---: | ---: | ---: |
| High | 0 | 0 | 0 | 0 |
| Medium | 17 | 0 | 12 | 5 |
| Low | 11 | 0 | 2 | 9 |
| Informational | 4 | 1 | 0 | 3 |
| Optimization | 0 | 0 | 0 | 0 |
| **Total** | **32** | **1** | **14** | **17** |

### Triage

Severity is Slither's impact and confidence. Lines refer to `contracts/src/Vault.sol` unless marked `IMezo.sol`.

| # | Detector | Severity | Where | Verdict | Reason |
| ---: | --- | --- | --- | --- | --- |
| 1 | incorrect-equality | Medium, High | `_assets` L293, `s.price == 0` | False positive | Sentinel for "no price seen yet", which only happens before the first deposit. Not a balance an attacker can steer. |
| 2 | incorrect-equality | Medium, High | `_liquidShare` L387, `shares == 0` | False positive | Early return for a holder with no shares. |
| 3 | incorrect-equality | Medium, High | `_maxDeposit` L393, `total == 0 && totalSupply() > 0` | False positive | Blocks deposits while existing shares are worth nothing. A donation that makes `total` non-zero only reopens deposits, and nobody gains from it. |
| 4 | incorrect-equality | Medium, High | `_maxShares` L399, `maxAssets == type(uint256).max` | False positive | Compares with the "no cap" constant. |
| 5 | incorrect-equality | Medium, High | `depositBTC` L160, `shares == 0` | False positive | Reverts a deposit that would mint nothing, which protects the depositor. |
| 6 | incorrect-equality | Medium, High | `_release` L445, `coll == 0` | False positive | True only when an exit needs all trove collateral, and then the trove closes. |
| 7 | incorrect-equality | Medium, High | `_release` L450, `debt == t.debt` | False positive | Picks `withdrawColl` when no repayment is due. `debt` comes from `Math.min(t.debt, ...)`, so the equality is exact. |
| 8 | incorrect-equality | Medium, High | `_repayToTarget` L552, `repay == 0 && spare == 0` | False positive | Skips a Mezo call that would change nothing. |
| 9 | incorrect-equality | Medium, High | `harvest` L520, `amount == 0` | False positive | Nothing above the cushion to sell, so it returns early. |
| 10 | incorrect-equality | Medium, High | `_parkMusd` L634, `held == 0` | False positive | Skips an empty sMUSD deposit, which sMUSD rejects. A 1-wei MUSD donation simply gets deposited. |
| 11 | reentrancy-no-eth | Medium, Medium | `withdraw` L191-L204 | False positive | Deposits, exits, `rebalance`, `harvest` and `unwind` are all `nonReentrant`. The calls in `_release` reach only Mezo, sMUSD, the DEX and the BTC and MUSD tokens, and none of them calls an address the caller controls. Shares burn before the payout. |
| 12 | reentrancy-no-eth | Medium, Medium | `redeem` L206-L219 | False positive | Same as row 11. |
| 13 | uninitialized-local | Medium, Medium | `_liquid` L305, `locked` | Accepted by design | Zero means "nothing locked", the intended default. Solidity zero-initializes it. |
| 14 | unused-return | Medium, Medium | `trove()` L259-L260 | Accepted by design | The three values used are Mezo's totals for the trove. The three ignored are parts already inside them, checked against `getEntireDebtAndColl` in mezo-org/musd. |
| 15 | unused-return | Medium, Medium | `_repayBlocked()` L321 | Accepted by design | Reads only the two fields its check needs. |
| 16 | unused-return | Medium, Medium | `_hint()` L623 | Accepted by design | The ignored value is a seed for chained hint calls, and the vault makes one call. |
| 17 | unused-return | Medium, Medium | `_pullMusd()` L648, `claimYield()` | Accepted by design | The function only has to raise the vault's MUSD balance. The claimed amount is not needed. |
| 18 | shadowing-local | Low, High | `withdraw` L191, `owner` | Accepted by design | ERC-4626 names this parameter `owner`, as OpenZeppelin does. The function never reads `Ownable.owner()`. |
| 19 | shadowing-local | Low, High | `redeem` L206, `owner` | Accepted by design | Same as row 18. |
| 20 | shadowing-local | Low, High | `maxWithdraw` L241, `owner` | Accepted by design | Same as row 18. |
| 21 | shadowing-local | Low, High | `maxRedeem` L246, `owner` | Accepted by design | Same as row 18. |
| 22 | shadowing-local | Low, High | `_maxWithdraw` L359, `owner` | Accepted by design | Same as row 18. |
| 23 | shadowing-local | Low, High | `_maxRedeem` L369, `owner` | Accepted by design | Same as row 18. |
| 24 | missing-zero-check | Low, Medium | constructor L126, `poolFactory_` | Accepted by design | Deploy-time immutable. The live value is Mezo's pool factory `0x4947…Ce1A`, read on-chain. |
| 25 | missing-zero-check | Low, Medium | constructor L127, `keeper_` | Accepted by design | Zero is a valid "no keeper" setting. The owner can still harvest. |
| 26 | missing-zero-check | Low, Medium | `setKeeper` L674, `keeper_` | Accepted by design | Setting zero is how the owner revokes the keeper. |
| 27 | reentrancy-benign | Low, Medium | `withdraw` L191-L204 | False positive | Same reasoning as row 11. The late write is the allowance, and a short allowance reverts the whole call. |
| 28 | reentrancy-benign | Low, Medium | `redeem` L206-L219 | False positive | Same as row 27. |
| 29 | pragma | Informational, High | L2, `IMezo.sol` L2, OpenZeppelin files | Accepted by design | The floating pragmas are OpenZeppelin's. One compiler, solc 0.8.28, builds everything, and the vault pins 0.8.28. |
| 30 | naming-convention | Informational, High | `IMezo.sol` L22, `MUSD_GAS_COMPENSATION()` | Accepted by design | Mezo's function name. Renaming it would change the selector. |
| 31 | naming-convention | Informational, High | `IMezo.sol` L49, `CCR()` | Accepted by design | Same as row 30. |
| 32 | unindexed-event-address | Informational, High | L102, `KeeperSet(address)` | True positive, no security impact | Correct. Indexing the address would only help log filters, and the event fires once per keeper change. Changing it needs a redeploy. |

### Findings in dependencies

Without `--exclude-dependencies`, Slither reports 73 results. The 41 extra results all sit in OpenZeppelin Contracts v5.7.0. They are outside scope and were not triaged one by one.

- 1 High, incorrect-exp, in `Math.mulDiv`. The `^` there is meant as XOR.
- 9 Medium, divide-before-multiply, in `Math`.
- 1 Low, missing-zero-check, in `Ownable2Step.transferOwnership`.
- 30 Informational: assembly (25), solc-version (4) and too-many-digits (1).

### v6 run

Same tools and command, on the v6 sources with `via_ir = true`. Slither analyzed `src/Vault.sol`, which imports the queue and both libraries: 35 contracts, 102 detectors.

| Severity | Findings | True positive | False positive | Accepted by design |
| --- | ---: | ---: | ---: | ---: |
| High | 0 | 0 | 0 | 0 |
| Medium | 20 | 0 | 15 | 5 |
| Low | 40 | 0 | 4 | 36 |
| Informational | 6 | 1 | 0 | 5 |
| **Total** | **66** | **1** | **19** | **46** |

All 32 v5 findings above appear again on v6, in the same functions and with the same verdicts. Only their line numbers moved. These are the 34 new ones. Lines refer to the v6 `contracts/src/Vault.sol` unless marked `RedeemQueue.sol`.

| # | Detector | Severity | Where | Verdict | Reason |
| ---: | --- | --- | --- | --- | --- |
| 33 | incorrect-equality | Medium, High | `_fillQueue` L291, `shares == 0 \|\| (assets < MIN_FILL && shares < pending)` | False positive | The wait rule. A fill that would burn nothing returns early. A dust fill that empties the queue still runs, so a 1-share request cannot hold borrowing shut. |
| 34 | reentrancy-no-eth | Medium, Medium | `_fillQueue` L281-L296 | False positive | Its callers, `processQueue`, `rebalance` and `harvest`, are all `nonReentrant`. The calls in `_release` reach only Mezo, sMUSD, the DEX and the BTC and MUSD tokens, the same as row 11. The shares burn before the BTC moves to the queue, the vault's own contract. |
| 35 | locked-ether | Medium, High | `RedeemQueue.sol`, `fill` | False positive | The queue receives a fill as native BTC and pays claims with the BTC token's ERC-20 `transfer`. On Mezo both are one balance (see "One BTC balance"), so the BTC always has a way out. The live claim of request 1 paid exactly the 0.004 BTC its fill reserved. |
| 36, 37 | missing-zero-check | Low, Medium | constructor L153 and `setGuardian` L844, `guardian_` | Accepted by design | Zero is a valid "no guardian" setting that leaves both brakes with the owner alone. |
| 38 | reentrancy-benign | Low, Medium | `_fillQueue` L281-L296 | False positive | Same reasoning as row 34. The late writes are the share burn and the queue's fill record. |
| 39 | reentrancy-benign | Low, Medium | `RedeemQueue.sol` `requestRedeem` L77-L95 | False positive | The external call is to the vault's own `escrow`, which only moves shares and calls nothing else. `requestRedeem` is `nonReentrant`. |
| 40 | shadowing-local | Low, High | `escrow` L264, `owner` | Accepted by design | The request's owner, named as in ERC-4626 `redeem`. The function never reads `Ownable.owner()`. |
| 41-64 | timestamp | Low, Medium | 24 comparisons in functions that read the unlocked total | Accepted by design | `block.timestamp` only drives the linear unlock and the router deadline. A block producer who shifts it by seconds moves the share price by seconds' worth of a 7-day release, about 1/604,800 of the lock per second, which nobody can turn into profit. |
| 65 | costly-loop | Informational, Medium | `RedeemQueue.sol` `_claim` L155-L167 | Accepted by design | The loop is bounded by `MAX_CLAIMS = 16` per call. |
| 66 | missing-inheritance | Informational, High | `Vault` should inherit `IEscrow` | Accepted by design | `IEscrow` is the queue's one-function view of the vault. Inheriting it would change no bytecode that matters. |

### v7 run

Same tools and command on the v7 sources. `src/Vault.sol` now also imports `VeSleeve.sol` and the linked `SystemMath.sol`: 42 contracts, 102 detectors.

| Severity | Findings | True positive | False positive | Accepted by design |
| --- | ---: | ---: | ---: | ---: |
| High | 2 | 0 | 2 | 0 |
| Medium | 33 | 0 | 26 | 7 |
| Low | 53 | 0 | 11 | 42 |
| Informational | 7 | 1 | 0 | 6 |
| **Total** | **95** | **1** | **39** | **55** |

65 of the 66 v6 findings appear again with the same verdicts. The one that drops out is the timestamp row for `_systemAllowsExit`, whose body moved into `SystemMath`. These are the 30 new ones. Slither's line numbers drift on these files, so the lines below are taken from the sources.

| # | Detector | Severity | Where | Verdict | Reason |
| ---: | --- | --- | --- | --- | --- |
| 67, 68 | weak-prng | High, Medium | `roll` L842 and `VeSleeve._revote` L236, `block.timestamp - block.timestamp % WEEK` | False positive | Not randomness. It is the start of the current veBTC epoch, Thursday 00:00 UTC, the same arithmetic Mezo Earn uses. |
| 69 | divide-before-multiply | Medium, Medium | `VeSleeve.lock` L218, `part = amount / n` | False positive | The last new rung takes `amount - part * j`, so the parts add up to exactly the BTC sent. |
| 70 | incorrect-equality | Medium, High | `VeSleeve._revote` L238, `votingPowerOfNFT(id) == 0` | False positive | A lock with no voting power left cannot vote, so the re-vote is skipped. |
| 71 | locked-ether | Medium, High | `VeSleeve`, payable `lock` | False positive | The BTC either goes into veBTC or back to the vault through the BTC token's `transfer` at the end of `collect`. On Mezo the native balance and the token balance are one, as with row 35. |
| 72-74 | reentrancy-no-eth | Medium, Medium | `VeSleeve.lock`, `_open` and `tend` | False positive | Only the vault calls `lock` and `collect`, from `roll`, which is `nonReentrant`. `tend` and `release` only accept calls from the sleeve itself. Every vault entry point that moves value is `nonReentrant`, so a Mezo Earn call cannot re-enter the vault mid-roll. |
| 75-79 | uninitialized-local | Medium, Medium | `lock` `ends` and `n`, `tend` `claimed`, the constructor's `sleeve_`, `rebalance` `spare` | False positive | Each one starts at zero on purpose, as no rung, no claim, no sleeve or no spare BTC. |
| 80 | unused-return | Medium, Medium | `roll` ignores `collect()` | Accepted by design | The vault reads its balance again after `collect`, which covers released BTC, claimed rebates and MUSD alike. |
| 81 | unused-return | Medium, Medium | `tend` ignores `distributor.claim` | Accepted by design | The claim only matters as succeeded or reverted. The BTC it pays lands in the sleeve's balance and is swept to the vault. |
| 82 | events-maths | Low, Medium | `lock` L223, `principal += amount` | Accepted by design | veBTC emits `Deposit` for every lock and top-up, and `principal` is a public view. |
| 83 | missing-zero-check | Low, Medium | `VeSleeve` constructor, `pool_` | False positive | A zero pool has no gauge in the voter, so the constructor reverts `BadSleeve`. |
| 84-86 | calls-loop | Low, Medium | `collect` over `tend`, `lock` over `_open` | Accepted by design | At most 4 rungs per `collect` and 2 new rungs per `lock`. Each `tend` runs on a fixed 2.5M gas budget inside `try`. |
| 87-90 | reentrancy-benign | Low, Medium | `lock`, `_open`, `collect`, `roll` | False positive | Same reasoning as rows 72-74. |
| 91, 92 | reentrancy-events | Low, Medium | `RungStuck` in `collect` and `tend` | False positive | The event follows a failed call to Mezo Earn and reports it. Nothing can re-enter, as in rows 72-74. |
| 93-95 | timestamp | Low, Medium | `tend` (matured, claim grace), `_revote` (epoch), `roll` (vote window) | Accepted by design | veBTC locks, votes and epochs are timestamp-based in Mezo Earn itself. A producer who shifts the time by seconds moves a roll's window by seconds. |
| 96 | assembly | Informational, High | `VeSleeve._read` | Accepted by design | A gas-capped `staticcall` that copies at most one word and never reverts. It keeps a broken or upgraded Mezo Earn view from reverting `rebalance`. |

## Manual review notes

These come from reading `Vault.sol` and `IMezo.sol` line by line. The interface was checked against mezo-org/musd at `de1ec2af`. sMUSD's payout logic was checked against the MUSDSavingsRate source kept in `staging/`. The PriceFeed, MUSD and Router sources were checked as verified on the Mezo explorer. None of these notes is a bug.

1. **Oracle-bounded swaps are open to any caller (low, accepted).** `rebalance()` buys back the MUSD gap with BTC. An exit or a rebalance that closes the trove can buy a shortfall. Once the trove is closed, anyone can `harvest()`. Each swap is bounded by the PriceFeed price with `slippageBps` against the vault. So a caller who moves the pool in the same transaction can capture up to that slippage on the amount swapped.
2. **Most of those swaps are small (low, accepted).** Buy-backs cover the 0.1% borrow fee, interest and the 0.1% cushion. A harvest after the trove is closed can cover all of the vault's MUSD, for example after a liquidation. The share price already values that MUSD with the same haircut, so a sandwich cannot push the share price below what it shows. Holders lose only the difference to the market price.
3. **Borrow fees are shared (low, accepted).** When `rebalance()` borrows, the 0.1% fee is bought back from the vault's idle BTC, so every holder pays it pro rata. It borrows when it opens the trove, or when the ratio goes over `maxCR`, for example after a large deposit. A depositor who exits soon after leaves the rest of that fee with the holders who stay. Doing this on purpose costs the griefer their own pro-rata share of every fee. Smaller deposits only join the trove as collateral and trigger no fee.
4. **`slippageBps` also prices the vault's net MUSD (low, owner trust).** `totalAssets()` values MUSD held minus MUSD owed with the slippage haircut, so changing `slippageBps` moves the share price. Normally the net MUSD is the 0.1% cushion plus unharvested yield, and the move is tiny. When most of the vault is MUSD, for example after a liquidation, the move approaches the size of the change. An owner who deposits or exits around their own change could shift value between holders.
5. **Deposits stay open while exits are limited (low, by design).** In Recovery Mode, or when Mezo would refuse a close, each holder's exit is capped at their pro-rata share of the BTC that can leave. A deposit made then joins that shared BTC. Other holders can withdraw part of it, and the depositor's own exit is capped at their pro-rata share. Exits still happen at the share price, so value does not move, only liquidity.
6. **The ERC-20 `deposit()` has no zero-share revert (informational).** `depositBTC()` reverts when a deposit would mint zero shares. The ERC-20 `deposit()` path keeps OpenZeppelin's behaviour and does not. With the 6-decimal share offset, a non-zero deposit rounds to zero shares only if the value behind each share unit rises about a million-fold, for example through a donation. This is not practical.

## How the code was tested

There are three proof methods, plus this Slither run. [EVIDENCE.md](EVIDENCE.md) collects every v5 result and link.

**v7**
- **A local chain of Mezo's verified code** steps through the Thursdays a testnet can't skip. veBTC, the Voter, the VaultGauge, the reward contracts, the RewardsDistributor, both splitters and the booster were compiled unchanged from the testnet explorer's verified sources, each with its own compiler settings. Their 23 runtime codes are byte-identical to testnet, outside immutables and metadata. MUSD, sMUSD and the DEX are the coverage suite's builds of Mezo's code. The only stand-in is the BTC precompile. 17 of 17 tests pass:
  - the first lock;
  - fees through Mezo's own distribute path, locked by the profit unlock;
  - maturity after and before the period update, and the one-day claim grace;
  - a killed gauge, with and without a pause, and a re-vote after a stranger's poke;
  - a Voter swap and its `addSecondaryVoter` fix;
  - a request paid from a matured lock;
  - a 4-week ladder over 5 rolls, a 3-week keeper gap, and all four locks matured;
  - stranger and keeper rolls;
  - the largest exit with a MUSD gap.
- **The tested code is the deployed code.** Its source hashes equal `contracts/src`, and the local build matched the deployed bytecode byte for byte.
- **Live testnet transactions**, in the v7 section of [`deployments/testnet-log.md`](deployments/testnet-log.md):
  - the deploy with the library linked;
  - a 34-call role matrix;
  - the move from v6, with the guardian's unwind, and the keeper opening the trove at 2.20.
- **Coverage** with `--ir-minimum`, from the coverage session: 88 tests, the 17 above included.
  - ProfitLock, QueueMath, RedeemQueue and SystemMath are at 100%.
  - The vault is at 98.43% of lines, 94.69% of branches and 100% of functions.
  - VeSleeve is at 95.97% of lines, 86.11% of branches and 100% of functions.

  [`coverage/README.md`](coverage/README.md) lists every uncovered line. They are the excluded Mezo edge-case guard, defensive checks no entry point can reach, and lines `--ir-minimum` cannot attribute although they always run. Coverage builds every source for london, because forge's source maps break under osaka. The byte-identity check above uses osaka.

**v6 so far**
- **Live testnet transactions**, in the v6 section of [`deployments/testnet-log.md`](deployments/testnet-log.md):
  - deployment with borrowing off, then a rebalance that opens no trove;
  - the 17-call role matrix;
  - the guardian's pause and unwind, and the owner's re-enable;
  - both v5 positions moving over, and the keeper opening the trove at 2.50;
  - a queue request paid from idle BTC, and one that freed collateral and repaid from savings with the trove kept at target, both claimed to the wei;
  - a donation held out of the share price until `sync()` locked it for exactly 7 days;
  - a copy with a 1 hour unlock, read 8 times over 70 minutes, matching the release formula to the wei every time.
- **The 21 eth_call scenarios on v6.**
  - 20 pass unchanged.
  - Scenario 10 fails by design: a fresh payout no longer lifts the share price at once. Its check moves to the unlock rule in the spec.
  - Every scenario leaves the same precompile budget on v6 as on v5.
- **Staging on Mezo's own MUSD code**, vault [`0xf3C2…6D30`](https://explorer.test.mezo.org/address/0xf3C209Ded3D4Ad30F2C940D012Ab8Cf71C526D30), Sourcify exact match. 55 PASS and 0 FAIL across five phases, recorded in [`deployments/staging-log.md`](deployments/staging-log.md) under "v6 on staging":
  - Recovery Mode with a waiting request;
  - liquidation;
  - a full redemption of the vault trove;
  - a stale oracle;
  - sMUSD payouts the vault triggers itself.
  Every number is checked to the wei. The one thing it could not run is a paused v2 factory, since Mezo's real factory is not paused and only a mock could pause it.
- **Known display lag.** After a loss, `lockedProfit()` keeps reading the stored lock until the next checkpoint, which nets the loss. The share price is right all along, because `totalAssets` takes the minimum of the two. The next vault version adds a raw-assets view, so a front end can show the netted figure.
- **Fuzz and invariant suites** for the two math libraries, in [`contracts/test/ProfitLock.t.sol`](contracts/test/ProfitLock.t.sol) and [`contracts/test/QueueMath.t.sol`](contracts/test/QueueMath.t.sol). No fork or stand-in is needed, since neither library touches a token.
  - 34 tests pass at 5,000 fuzz runs each. The five invariant suites run 256 runs × 64 calls each, with `fail_on_revert`, and none of their calls reverts.
  - ProfitLock also passed a deeper run of 100,000 fuzz runs and 256,000 invariant calls per suite.
  - The suites were checked by breaking the libraries one line at a time. Every break that changes behaviour was caught.
  - Two survivors only differ in states the vault cannot reach: locked above recorded, and a fill of zero shares.
- **Still running:** full line and branch coverage of `contracts/src`.

**v5 record**

| Method | What it covers | Record |
| --- | --- | --- |
| live testnet transactions | v5: a native BTC deposit and an ERC-20 deposit, the trove opening at a 2.50 ratio with the fee bought back, a real sMUSD payout harvested into BTC, a partial exit repaid from savings, the keeper moving to its own key, and a Mezo Passport (Unisat) deposit and withdrawal. Earlier full cycles ran on the superseded v1 and v2. | [`deployments/testnet-log.md`](deployments/testnet-log.md) (v5 section at the bottom), [`deployments/testnet-log-v1.md`](deployments/testnet-log-v1.md) |
| eth_call scenarios against live Mezo testnet state that inject only our own code and its BTC balance | 21 scenarios. They cover open, harvest, borrowing more, exits through the trove, closes, band repay, unwind, the ERC-20 and ERC-4626 paths, two users sharing yield, closes the pool cannot fill, large vaults, chunked harvests and pro-rata exits. They also check that a stranger cannot harvest an open trove, and try an inflation attack by donation. | [`scripts/preflight.sh`](scripts/preflight.sh), [`contracts/script/Preflight.sol`](contracts/script/Preflight.sol) |
| shock tests on a private deployment of Mezo's own MUSD code (mezo-org/musd at de1ec2af) on Mezo testnet, using Mezo's own test hooks for price and rate (MockAggregator, InterestRateManagerTester) | Redemptions, band moves, rate changes, -50% and -60% in one block, Recovery Mode, liquidation, a close Mezo refuses, and the last trove | [`deployments/staging-log.md`](deployments/staging-log.md), code in [`staging/`](staging/), Mezo's source at [`de1ec2af`](https://github.com/mezo-org/musd/tree/de1ec2af9449f65dec4fb3293f02674446143e87) |
| Static analysis | Slither 0.11.6, triaged above | This file |

The staging phases ran on several vault versions. The log marks which vault ran what.

| Staging phase | Vault code | How |
| --- | --- | --- |
| Redemption, partial and full | v2 (the live v2 code) | Real transactions |
| A close Mezo refuses | v2, then v3 | Real transactions on v2. v3 by eth_call with the vault code swapped in. |
| Band and rates | v3 | Real transactions |
| -50% in one block, Recovery Mode | v3 | Real transactions |
| Exits when Mezo would refuse a close | v4 | eth_call on v3 state, then real transactions |
| Last trove | v4, then v5 | Real transactions on v4. v5 by eth_call with the vault code swapped in. |
| -60% in one block, liquidation | v5 | Real transactions |
| A close Mezo refuses, on the final code | v5 | Real transactions |

- The phases that ran on v2 or v3 code were not repeated on v5 with real transactions.
- The staging log marks every check PASS or FAIL. It has four FAIL lines, each followed by a note. Three were checks written wrong, and one is the Mezo-side edge case that v5 covers.

What is not covered:

- No third-party audit.
- No formal verification. Only the two math libraries have Foundry suites so far. Full vault coverage is in progress.
- Nothing has run on mainnet.
- No fork tests. The BTC token and the oracle are precompiles, and forks cannot run them.
- This file does not re-run the 21 scenarios. EVIDENCE.md collects their results.

## Reporting a vulnerability

- **Email:** contact@oynozan.com
- Report privately first. Do not open a public issue for a bug that is not fixed.
- Include the function, the vault state it needs, and an `eth_call` or transaction that shows it.
- Test on Mezo testnet only. There is no mainnet deployment.
- For a bug in Mezo's own contracts (MUSD, sMUSD or the DEX), follow [Mezo's security policy](https://github.com/mezo-org/musd/blob/main/SECURITY.md).
