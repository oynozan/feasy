# Feasy evidence

This page backs each claim Feasy makes about its vault with a transaction, a log line or a read-only call. Everything ran on Mezo testnet (chain id 31611). Transaction and address links open the [Mezo testnet explorer](https://explorer.test.mezo.org). Every status and gas figure in the deployment logs was checked against its receipt on 2026-10-25, and all of them match.

## 1. Summary

The evidence comes in three kinds, all on Mezo testnet: live testnet transactions, eth_call scenarios against live Mezo testnet state that inject only our own code and its BTC balance, and shock tests on a private deployment of Mezo's own MUSD code (mezo-org/musd at de1ec2af) on Mezo testnet, using Mezo's own test hooks for price and rate (MockAggregator, InterestRateManagerTester). The live testnet transactions run the whole v5 flow against Mezo's live contracts: a native and an ERC-20 deposit, a trove opened at 250% with the borrow fee bought back, a real sMUSD payout harvested into BTC, a partial exit repaid from savings, and a deposit and a withdrawal from a Unisat wallet through Mezo Passport. The 21 eth_call scenarios put the same code through opens, harvests, exits, closes, 150 BTC exits and a donation attack against live state, and all 21 passed on 2026-10-25. The shock tests cover what the live oracle cannot do: redemptions, a 25% drop and a 50% rise, rate changes, a 50% drop in one block with Recovery Mode, a 60% drop with liquidation, a close that Mezo refuses, a weak system and the last trove. Live v5 runs the same bytecode as the staging v5 vault, apart from the immutables its constructor sets. Nothing has run on mainnet.

## 2. Live testnet, v5

| | |
| --- | --- |
| Vault v5 (fBTC) | [`0x2964612e8976b4003083E6014cA39f5fD7b41f3A`](https://explorer.test.mezo.org/address/0x2964612e8976b4003083E6014cA39f5fD7b41f3A) |
| Run log | [`deployments/testnet-log.md`](deployments/testnet-log.md), section "v5, the final contract" |
| Source | [Sourcify exact match](https://repo.sourcify.dev/31611/0x2964612e8976b4003083E6014cA39f5fD7b41f3A) on the runtime code, verified 2026-10-24 10:20 UTC |
| Repo build | Compiling [`contracts/src/Vault.sol`](contracts/src/Vault.sol) with [`contracts/foundry.toml`](contracts/foundry.toml) gives runtime code equal to live v5 byte for byte, outside the 2976 immutable bytes that the constructor fills in |
| Staging copy | Staging v5 [`0xE707…d69D`](https://explorer.test.mezo.org/address/0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D) matches the same build the same way, so the staging phases on v5 ran the live code |
| Explorer | The Mezo explorer does not list the source as verified yet. Its API returned `is_verified: false` on 2026-10-25. |

- To repeat the build check, run `forge build` in `contracts/` and compare `cast code` of the vault with `deployedBytecode.object` in `contracts/out/Vault.sol/Vault.json`, skipping the ranges listed in `deployedBytecode.immutableReferences`.

Mezo contracts, read from the vault's immutables with view calls:

| Contract | Address |
| --- | --- |
| BorrowerOperations | [`0xCdF7…beE5`](https://explorer.test.mezo.org/address/0xCdF7028ceAB81fA0C6971208e83fa7872994beE5) |
| TroveManager | [`0xE47c…6bb0`](https://explorer.test.mezo.org/address/0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0) |
| PriceFeed | [`0x86bC…9366`](https://explorer.test.mezo.org/address/0x86bCF0841622a5dAC14A313a15f96A95421b9366) |
| HintHelpers | [`0x4e4c…BCF6`](https://explorer.test.mezo.org/address/0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6) |
| MUSD | [`0x1189…c503`](https://explorer.test.mezo.org/address/0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503) |
| MUSD Savings Vault (sMUSD) | [`0x6f46…8e16`](https://explorer.test.mezo.org/address/0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16) |
| DEX router | [`0x9a1f…D7E9`](https://explorer.test.mezo.org/address/0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9) |
| Pool factory | [`0x4947…Ce1A`](https://explorer.test.mezo.org/address/0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A) |
| BTC, the vault's asset (precompile) | [`0x7b7C…0000`](https://explorer.test.mezo.org/address/0x7b7C000000000000000000000000000000000000) |

PCV, the Mezo contract that pays protocol fees into sMUSD, is [`0x4dDD…80Af`](https://explorer.test.mezo.org/address/0x4dDD70f4C603b6089c07875Be02fEdFD626b80Af) (from [`scripts/env.sh`](scripts/env.sh)).

| Wallet | Address |
| --- | --- |
| Alice | [`0xCea6…780D`](https://explorer.test.mezo.org/address/0xCea69E8C9fe8307a166F6165a9c591C3e74c780D) |
| Bob | [`0xD323…B9f5`](https://explorer.test.mezo.org/address/0xD323eAB315D1AE6C73A6Fe25a2854CB3DcD8B9f5) |
| Owner and deployer, keeper until step 15 | [`0x90fE…5aF1`](https://explorer.test.mezo.org/address/0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1) |
| Keeper from step 15 | [`0xC05D…5a23`](https://explorer.test.mezo.org/address/0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23) |
| Passport account | [`0xee1F…642c`](https://explorer.test.mezo.org/address/0xee1Feb8dCeFb26E31229B17CB6758C2b2F2f642c) |

The deployer funded every other wallet in this table.

### Every v5 transaction

All on 2026-10-24, in block order. Every receipt has status 0x1.

| # | Time (UTC) | Step | What it shows | Tx |
| --- | --- | --- | --- | --- |
| 1 | 10:19:27 | Deploy | The deployer creates vault v5 | [`0xdb19a9a3`](https://explorer.test.mezo.org/tx/0xdb19a9a34c1b2ae9ebc1c98c8cabb93d1e5060071248889e683300d003b7b757) |
| 2 | 10:20:47 | Fund Alice | 0.015728 BTC from the deployer, her deposit plus gas | [`0x150f0882`](https://explorer.test.mezo.org/tx/0x150f08829d6c682bcbe2b037d2cb23818374e8eebcb8c21979f881c64a4640f4) |
| 3 | 10:20:58 | Fund Bob | 0.003827 BTC from the deployer | [`0xf39bfd87`](https://explorer.test.mezo.org/tx/0xf39bfd87f1d26afb81bdfe3f2ba8dec8ca545af0f069ab42182001119f7caadc) |
| 4 | 10:21:05 | Opening params | `setParams` with the band top at 2.6 while only 0.07 BTC is in, and 4% slippage because the testnet pool sat 2.2% under the oracle | [`0x38b870c3`](https://explorer.test.mezo.org/tx/0x38b870c38695d67f5fa044e53a46e221b074df388e18c6d1f3b17e7432eb29f0) |
| 5 | 10:21:12 | Native deposit | Alice sends 0.04 BTC to `depositBTC` and gets 0.04 fBTC | [`0x20330c9e`](https://explorer.test.mezo.org/tx/0x20330c9e4c05686277ffcafa46c23f62446655cb4b3d4bcf819c1cd5b164bc01) |
| 6 | 10:21:16 | ERC-20 approve | Bob approves the BTC ERC-20 for the vault | [`0x97175f37`](https://explorer.test.mezo.org/tx/0x97175f373520ed12b8a48bc44f2f223d388cbc2cf08b16deab5101d1df21abf3) |
| 7 | 10:21:24 | ERC-20 deposit | Bob deposits 0.03 BTC with `deposit` and gets 0.03 fBTC | [`0x2d66d6ef`](https://explorer.test.mezo.org/tx/0x2d66d6ef859bdfa4ef5a6c6069d98f0714c6292282c8a3edc7d4bc9a8eeb16da) |
| 8 | 10:21:31 | Open with fee buy-back | Bob calls `rebalance()`, which anyone can. The trove opens with 0.0679 BTC and 2184.97 MUSD of debt at ratio 2.50, and 1987.02 MUSD goes into sMUSD. `ShortfallBought` shows 0.0000513 BTC buying 4.03 MUSD, so the MUSD held covers what the loan owes. | [`0xf9e4c5ce`](https://explorer.test.mezo.org/tx/0xf9e4c5ce807fd2f4bb4f7ad27811550c3595eff138a0b4d28ee135fb672be085) |
| 9 | 10:22:03 | Yield distribution | Mezo's PCV `distributeMUSD()` pays protocol fees into sMUSD. The vault's savings rise from 1987.019 to 1988.316 MUSD (+1.296). | [`0xe7fe74cb`](https://explorer.test.mezo.org/tx/0xe7fe74cb748486abb8eab9cc6a00e9db3f61fbf779c8f6a0136992c71655a1da) |
| 10 | 10:22:10 | Harvest | `harvest()` swaps the 1.363 MUSD above the 0.1% cushion into 0.0000173 BTC on the Mezo DEX | [`0xba102af2`](https://explorer.test.mezo.org/tx/0xba102af22c2668f52bc57bf6f5062bcf00518c1c81ea30c7cfc966ad3e96f455) |
| 11 | 10:22:14 | Partial exit repaid from savings | Bob withdraws 0.005 BTC: 0.002066 from idle BTC and 0.002934 released from collateral, with 94.59 MUSD of debt repaid from savings. The ratio stays at 2.50. | [`0x5ee373eb`](https://explorer.test.mezo.org/tx/0x5ee373ebeed5967920075b9d6514f04093f34da6801dc3e5898797b986dc9fd9) |
| 12 | 10:22:40 | Default band restored | `setParams` back to 2.0 / 2.5 / 3.0, with the trove at target inside it | [`0xbed5915c`](https://explorer.test.mezo.org/tx/0xbed5915c2e9658769c7534ca4e41b5929da3c886dfa6656b04419e9903bb5886) |
| 13 | 13:43:50 | Fund Passport | 0.002 BTC to the Passport account | [`0xe6b3e267`](https://explorer.test.mezo.org/tx/0xe6b3e26725260e0a30dd9be38b5bf440480af5dc9acec212559695f35f4b93b9) |
| 14 | 13:48:42 | Passport deposit | The Passport account of a Unisat wallet deposits 0.0002 BTC. The `Deposit` event names the Passport account as sender and owner. | [`0x6fe21418`](https://explorer.test.mezo.org/tx/0x6fe214186c7299e2bf17fcc0612372aadc261247487ee2fc189af746ff873ba5) |
| 15 | 14:39:56 | Keeper on its own key | `setKeeper` hands upkeep to [`0xC05D…5a23`](https://explorer.test.mezo.org/address/0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23), so the owner key no longer signs routine upkeep | [`0x34e34091`](https://explorer.test.mezo.org/tx/0x34e3409180fb33728f2246b5c1415bb122be044f5867786630a7a28404e3345a) |
| 16 | 14:40:07 | Fund keeper | 0.0005 BTC for keeper gas | [`0x64100736`](https://explorer.test.mezo.org/tx/0x64100736f991c751a23680ad53b2261cafb577f7e55434c7ad19e4d09d147143) |
| 17 | 15:13:35 | Passport withdraw | 0.00005 BTC back to the Passport account, signed in Unisat. The `Withdraw` event names it as receiver and owner. | [`0x2c3f3658`](https://explorer.test.mezo.org/tx/0x2c3f36588879bd10b614fcebe46fed4828411a100b29f5a5dee44ba7d922b113) |

- The Passport account is a Safe 1.4.1 proxy with one owner and a threshold of 1 (view calls `VERSION()`, `getOwners()`, `getThreshold()`).
- Both Passport transactions run through the Safe's `execTransaction` and emit `ExecutionSuccess`.
- The run log records the account as the OrangeKit Safe of a Unisat wallet.

### Current position

Read with view calls at block 16350281 (2026-10-25 01:01:26 UTC).

| Read | Value |
| --- | --- |
| `totalAssets()` | 0.065139206246808680 BTC |
| `totalSupply()` | 0.065149287294209578013035 fBTC (`decimals()` returns 24) |
| Share price | 0.9998453 BTC per fBTC (`totalAssets() * 1e6 / totalSupply()`) |
| `trove()` | Active, 0.064966018931761802 BTC collateral, 2090.411624430839528353 MUSD debt |
| Collateral ratio | 2.5091, at the PriceFeed price of 80,734.68 USD per BTC |
| `savingsValue()` | 1892.361645819565692634 MUSD in sMUSD |
| Idle BTC | 0.00015 BTC |
| Trove interest rate | 1% (`getTroveInterestRate` on the TroveManager returns 100) |
| Settings | Band 2.0 / 2.5 / 3.0, 3% buffer, 4% slippage, 2% max borrow rate, borrowing on, no deposit cap |
| `owner()` | [`0x90fE…5aF1`](https://explorer.test.mezo.org/address/0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1), the deployer key |
| `keeper()` | [`0xC05D…5a23`](https://explorer.test.mezo.org/address/0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23), nonce 0, so it has sent no transaction yet |
| Holders | Alice 0.04 fBTC (0.0399938 BTC), Bob 0.0249993 fBTC (0.0249954 BTC) and the Passport account 0.00015 fBTC (0.00015 BTC). Together they hold the whole supply. |

- Alice's and Bob's positions and the Passport deposit are all still open.
- The deposits came in at 1.0 BTC per fBTC.
- The open cost 0.038% of the vault: the share price was 0.999617 right after it.
- The payout and harvest lifted it to 0.999853.
- The loan cost since then has moved it to 0.9998453.
- No sMUSD payout has reached the vault since step 11. `savingsValue()` is the same to the wei as in the log after that step.

To read the same numbers yourself:

```bash
R=https://rpc.test.mezo.org
V=0x2964612e8976b4003083E6014cA39f5fD7b41f3A
cast call $V 'totalAssets()(uint256)' -r $R -b 16350281
cast call $V 'totalSupply()(uint256)' -r $R -b 16350281
cast call $V 'trove()((bool,uint256,uint256))' -r $R -b 16350281
cast call $V 'savingsValue()(uint256)' -r $R -b 16350281
```

Drop `-b 16350281` for today's values.

### Keeper

- [`deployments/keeper.log`](deployments/keeper.log) has one line per check: the ratio, the idle BTC, and the MUSD a harvest could sell above the 0.1% cushion.
- 113 checks ran about every 10 minutes, from 2026-10-24 14:07:53 UTC to 2026-10-25 00:54:55 UTC, the last line when this page was written.
- The ratio stayed between 2.4634 and 2.5108, inside the 2.0 to 3.0 band, so no rebalance was due.
- The harvestable MUSD stayed between 0.060 and 0.086, far under the 10 MUSD trigger in [`scripts/keeper.sh`](scripts/keeper.sh), so no harvest was due.
- From 14:40:59 to 23:25:59 UTC two loops wrote to the log side by side, so some lines are minutes apart.
- No loop ran from 2026-10-24 23:25:59 UTC to 2026-10-25 00:04:12 UTC.

## 3. Live testnet, earlier versions (superseded)

v1 and v2 are superseded by v5. Both hold only dust now: `trove()` is inactive and `totalAssets()` is under 0.000000001 BTC on each.

### v1 [`0x375E…8e86`](https://explorer.test.mezo.org/address/0x375Ef9f10cf75f138D6454F5253B8cEa65038e86), superseded

[`deployments/testnet-log-v1.md`](deployments/testnet-log-v1.md), 2026-10-24 07:45 to 07:53 UTC. A full cycle that ends with a closing exit.

| Step | What happened | Tx |
| --- | --- | --- |
| Deposits | Alice 0.06 BTC native, Bob 0.03 BTC through the ERC-20 | [`0x3bf6ef50`](https://explorer.test.mezo.org/tx/0x3bf6ef5065efec120a435b640edba95d96a8a373579f796adc2d9b17702a3955), [`0xfa2370d9`](https://explorer.test.mezo.org/tx/0xfa2370d9cec2aa7a4b2545f5ee86c6a771529050080e429ce748e90a2a80c19f) |
| Open | Bob's `rebalance()` opens at 2.50 and buys back the fee gap, 0.0000674 BTC for 5.30 MUSD | [`0x8edd9e9c`](https://explorer.test.mezo.org/tx/0x8edd9e9c5d277171bc21a8470aba15a313f6127c5a5dd22b8b77ade738976f80) |
| Payout | `distributeMUSD()` raises the vault's savings from 2620.915 to 2664.572 MUSD (+43.656) | [`0x16ed0d35`](https://explorer.test.mezo.org/tx/0x16ed0d35679aacc37d3eefbf14123914f658629074b52089f40679181c4b29c0) |
| Harvest | 43.727 MUSD swapped into 0.000555 BTC. The share price goes from 0.999606 to 1.005769. | [`0x50afcc19`](https://explorer.test.mezo.org/tx/0x50afcc196ae7d1d9827fa7402e993386a9cddec6666a060d6440cebaafbc7b99) |
| Rebalance | The harvested BTC joins the collateral | [`0x3c9c082a`](https://explorer.test.mezo.org/tx/0x3c9c082ac7674153112a3675c83501e5598b7fe1b67a5998c8b25d4a67b0b7be) |
| Partial exit | Bob redeems his max, 0.030162 BTC. The loan shrinks to Mezo's 2,000 MUSD minimum and stays open. | [`0x252f0dbb`](https://explorer.test.mezo.org/tx/0x252f0dbb35cecb74f0644ab3f9c13481d8a1c0dc1e2485fa0215912448540e73) |
| Closing exit | Alice redeems her max, 0.060314 BTC, and the trove closes (`TroveClosed`) | [`0xad45d9f4`](https://explorer.test.mezo.org/tx/0xad45d9f4856be3bcc6afaf38181aba32169c35ea7b6d2a3207ad08bf73332b66) |
| Wind down | The leftover 2.618 MUSD is harvested, then both redeem the rest | [`0x1596ce07`](https://explorer.test.mezo.org/tx/0x1596ce0773eb2603271a845a5abe398557e69d375ed79bff798345042feafed3), [`0xafc01269`](https://explorer.test.mezo.org/tx/0xafc01269d3a80bd36bedf9ae257ceacea8e4b31e7212980b1e05fa494f8c3517), [`0x8cc1fa31`](https://explorer.test.mezo.org/tx/0x8cc1fa31363df09305317173b454dbad4b628e659f56dfd4da04b8fd9501295f) |
| Outcome | Alice took out 0.060348 BTC for 0.06 in, Bob 0.030174 BTC for 0.03 in. That is +0.58% each, counted at the vault before gas. | |

Three v1 transactions reverted, and each one led to a fix:

- [`0x57cd6f58`](https://explorer.test.mezo.org/tx/0x57cd6f58c73efbc301332f2dcddca0deb04d769fb9a5da487ed2e8de41fbac34): the ERC-20 deposit, sent with the bare gas estimate, ran out of gas (137202 used of 137202). The scripts now pad estimates by 1.5x.
- [`0x9696fe25`](https://explorer.test.mezo.org/tx/0x9696fe25f8dd35762c7df4e657fa126f4a86542b66499332ebe81b10e297cd4d): Bob's first redeem asked for the exact max read a block earlier. The vault's own check refused it with `ERC4626ExceededMaxRedeem`, as a replay at block 16335390 shows. Callers now leave 0.001% of room.
- [`0x75ea6ff9`](https://explorer.test.mezo.org/tx/0x75ea6ff92f61e5312c6db6c613bf9c6fd85d06133fabeb6d9261cbb2331b3e64): the retry ran out of gas (1318723 used of 1360891), because the trove hint was seeded with the block number and gas moved between estimate and execution. The vault now seeds hints with the target ratio. [`0x252f0dbb`](https://explorer.test.mezo.org/tx/0x252f0dbb35cecb74f0644ab3f9c13481d8a1c0dc1e2485fa0215912448540e73) then went through with a 3x pad.

### v2 [`0x29CE…8B78`](https://explorer.test.mezo.org/address/0x29CE356E4ea91b1986402AA2311d17d7e2178B78), superseded

The top of [`deployments/testnet-log.md`](deployments/testnet-log.md), 2026-10-24 07:58 to 08:43 UTC.

| Step | What happened | Tx |
| --- | --- | --- |
| Deposits | Alice 0.06 BTC native, Bob 0.03 BTC through the ERC-20 | [`0xbcb1c774`](https://explorer.test.mezo.org/tx/0xbcb1c774b688bf747d170a8423671549bc22e38f002700dfcb08bae497abea6f), [`0x37ec3c19`](https://explorer.test.mezo.org/tx/0x37ec3c1967bcbebced3553c96ba4aface452efa602a95e17d6eea94ae60354b5) |
| Open | At 2.50, with the fee gap bought back, 0.0000674 BTC for 5.30 MUSD | [`0x091a099f`](https://explorer.test.mezo.org/tx/0x091a099feb42e0283a535d8313df10ae11fdf8311604fbcc44da029b1a41109d) |
| Payout | `distributeMUSD()` adds only 0.157 MUSD, because the v1 run had drained PCV | [`0x0d06db83`](https://explorer.test.mezo.org/tx/0x0d06db83fbb8ada18f3823002884129eba255bce206136966e89e71b295763a8) |
| Partial exit | Bob redeems his max, 0.029977 BTC. The loan drops to the 2,000 MUSD minimum and stays open. | [`0xdcc698c1`](https://explorer.test.mezo.org/tx/0xdcc698c1f0dc5bb917205b07010d3de1e94fd42763849150f3e87f375758cb0d) |
| Harvest | The keeper harvests 1.047 MUSD into 0.0000133 BTC | [`0x0f082d52`](https://explorer.test.mezo.org/tx/0x0f082d52ca4768761719874c9c41f3416da04869b104d65adfe287c473e77db2) |
| Closing exit | Alice redeems her max, 0.059956 BTC, and the trove closes without a swap | [`0xc4ca18a8`](https://explorer.test.mezo.org/tx/0xc4ca18a846c1159d493dcf20f9b4dedb0a7bdc54e9217135a2a14f6f27fbad73) |
| Stranger harvest | Bob, not the keeper, harvests the leftover 1.80 MUSD, which anyone may do once the trove is closed | [`0x885ca0ed`](https://explorer.test.mezo.org/tx/0x885ca0ed280769686d3a42fc1dc44539ebc404c6328cae90bd08275e2066851c) |
| Wind down | Both redeem the rest | [`0x9333a39f`](https://explorer.test.mezo.org/tx/0x9333a39f1bf012c08ad6471c6d492b1ece28a1534c03b73b273c34d206f1c3f2), [`0x74931ba8`](https://explorer.test.mezo.org/tx/0x74931ba8581f20a94914e775d9a524dc1887ae75069fab16be8c2631450f654e) |
| Outcome | With almost no payout, the exits returned 99.966% (Alice) and 99.964% (Bob) of the BTC deposited. The fee buy-back cost 0.0000674 BTC and the two harvests won back 0.0000362 BTC. | |

- Staging later showed that v2's `rebalance()` reverts when Mezo refuses a close (section 5), so v2 was replaced.

## 4. The 21 eth_call scenarios

These are eth_call scenarios against live Mezo testnet state that inject only our own code and its BTC balance. They need no funds and send no transactions.

- The scenarios are in [`contracts/script/Preflight.sol`](contracts/script/Preflight.sol). [`scripts/preflight.py`](scripts/preflight.py) makes each eth_call and prints its result, and [`scripts/preflight.sh`](scripts/preflight.sh) builds the code and runs all of them.
- Each scenario is one `eth_call` to a harness address. A state override gives that address the compiled `Preflight` code and 1 BTC, or 300 BTC for scenarios 15, 16 and 18. Nothing else is overridden.
- Inside the call, the harness deploys a fresh vault from `contracts/src/Vault.sol`, wired to the live BorrowerOperations, HintHelpers, sMUSD, router and pool factory, and drives it with real calls into Mezo.
- One eth_call runs as one transaction, so each scenario must fit Mezo's 20 precompile calls per transaction. Each one reports how many it left unused, from 0 to 11 in this run.
- Scenarios marked "at 1%" use 1% slippage, where the testnet pool, a few percent under the oracle, cannot fill the fee buy-back. That exercises the vault's degraded mode. The other scenarios that open a trove use 4%.
- A scenario passes when every check inside the call holds and, for 11 of them, the final ratio lands in the range `preflight.py` expects.
- Last run: 2026-10-25, blocks 16350191 to 16350196 (00:55:12 to 00:55:34 UTC), with code built from this repo. 21 of 21 passed.

| # | Scenario | What it does and checks | Result |
| --- | --- | --- | --- |
| 0 | open | Deposit 0.2 BTC, then `rebalance()`. The trove opens at 2.50 with 0.194 BTC of collateral, 3% stays idle, and the MUSD held covers what the loan owes. | PASS, ratio 2.5000 |
| 1 | harvest | Open at 1%, then a real sMUSD payout: the harness buys MUSD with 0.2 BTC and pays it through `receiveProtocolYield`, as PCV does. `harvest()` keeps the cover and adds BTC. | PASS, idle BTC 0.0060 to 0.0072 |
| 2 | withdraw via trove | Open with 0.2 BTC, withdraw 0.05 BTC, more than the idle buffer. Paid in full, and the trove stays at 2.50. | PASS, 0.05 BTC paid |
| 3 | redeem max (close) | Open, then redeem `maxRedeem`. The exit closes the trove without a swap. | PASS, 0.19984 of 0.2 BTC paid |
| 4 | deposit more, borrow | Open with 0.2 BTC at 1%, then deposit 0.4 BTC more. One `rebalance()` adds the collateral, refinances and borrows. | PASS, collateral 0.582 BTC, ratio 2.5000 |
| 5 | band repay | Open, then move the band to 2.6 / 2.8 / 3.5. `rebalance()` repays from savings to the new target. | PASS, ratio 2.8000 |
| 6 | unwind | Open, then the owner calls `unwind()`. The loan closes and the BTC is back in the vault. | PASS, trove closed |
| 7 | erc20 deposit | `approve` and `deposit` 0.2 BTC through the BTC ERC-20, then `rebalance()`. Same checks as open. | PASS, ratio 2.5000 |
| 8 | small vault, withdraw pins min loan | Open with 0.08 BTC, withdraw 0.02 BTC. The debt lands exactly on Mezo's 2,000 MUSD minimum. | PASS, debt 2000.0000 |
| 9 | small vault, withdraw closes | Open with 0.08 BTC, withdraw 0.04 BTC, which would take the loan under the minimum. The trove closes and the exit is paid. | PASS, trove closed |
| 10 | two users, yield | Alice opens with 0.2 BTC at 1%, Bob deposits 0.1 BTC after the open, then a real sMUSD payout. Both end above their deposit. | PASS, 0.2008 and 0.1004 BTC |
| 11 | rebalance closes small trove | Open with 0.08 BTC, then move the band to 3.2 / 3.4 / 3.6, so the target loan falls under the minimum. `rebalance()` closes the trove. | PASS, trove closed |
| 12 | erc4626 mint and redeem | Mint 0.1 fBTC, redeem 0.04 fBTC, no trove. An exact round trip. | PASS, 0.04 BTC back |
| 13 | close unfillable at 1% slippage | Open with 0.1 BTC at 1%, then withdraw `maxWithdraw`. The exit stops short of a close and leaves the minimum loan open. | PASS, debt 2000.0000 |
| 14 | rebalance cannot close, repays | As 11, but at 1%, so the close cannot be bought. `rebalance()` repays to the minimum loan instead. | PASS, debt 2000.0000 |
| 15 | 150 BTC vault, big exit at target | Open with 150 BTC, withdraw 149.7 BTC in one call. Paid in full, and the loan is back at 2.50. | PASS, ratio 2.5000 |
| 16 | 150 BTC vault, big exit to the debt floor | Open with 150 BTC at 1%, then withdraw `maxWithdraw`. All MUSD held goes to the repayment and the loan stays open. | PASS, 149.848 BTC paid |
| 17 | chunked harvest | Open at 1%, a real sMUSD payout, then `harvest` of a 50 MUSD chunk. The chunk is sold and the rest is kept. | PASS |
| 18 | pro rata exits when a close cannot be bought | Alice with 150 BTC and Bob with 0.1 BTC, at 1%. Bob's max exit is above 99% of his assets, and Alice's max exit goes through. | PASS, Bob's max 99.94% of his assets |
| 19 | stranger cannot harvest an open trove | Open at 1%, then a second account calls `harvest()`. The call fails. | PASS |
| 20 | inflation attack by donation | An attacker deposits 1 wei and sends 0.5 BTC straight to the vault, then a victim deposits 0.4 BTC. The victim loses at most the donation divided by 1e6, and the attacker loses money. | PASS, the victim keeps 0.3999998611 BTC |

To rerun them:

```bash
bash scripts/new-wallet.sh DEPLOYER
bash scripts/preflight.sh
bash scripts/preflight.sh 3
```

- The first line is needed once on a fresh clone. [`scripts/env.sh`](scripts/env.sh) reads `.env` and stops when `DEPLOYER_PK` is unset, even though the scenarios sign nothing. The new key needs no funds.
- The second line runs all 21 scenarios. The third runs one, by number.
- The runner needs Foundry and Python 3, called as `python`.

## 5. Shock tests on staging

These are shock tests on a private deployment of Mezo's own MUSD code (mezo-org/musd at de1ec2af) on Mezo testnet, using Mezo's own test hooks for price and rate (MockAggregator, InterestRateManagerTester). The live oracle cannot be moved, so price shocks, liquidation, redemption and Recovery Mode were tested here.

- The deployment code is in [`staging/`](staging/). Its `staging/lib/musd` submodule points at mezo-org/musd commit `de1ec2af9449f65dec4fb3293f02674446143e87`, and README.md notes the verified MUSDSavingsRate source on top.
- BTC is the real precompile.
- Swaps go through the real Mezo DEX router, in a MUSD/BTC pool created on the live pool factory ([`0x970af642`](https://explorer.test.mezo.org/tx/0x970af642fa2c0a9960698e8fcdf32597d5888749a02ce3bfc1ee8c1581232347), [`0x39d14804`](https://explorer.test.mezo.org/tx/0x39d14804c5b4ecb52a1d0019263c2f69b7f8424235f73d2ed11a7f74bbaf08af)).
- The other borrower in the system is the deployer's own trove ([`0x56ba4634`](https://explorer.test.mezo.org/tx/0x56ba4634286e4c7de183dddabeebba67be03259633ae619c93970c1278eb864e)).
- The full log is [`deployments/staging-log.md`](deployments/staging-log.md), 2026-10-24 09:00 to 10:17 UTC.
- Every check in the log prints PASS or FAIL with a vault snapshot.
- Most checks read state after real transactions. Checks marked "eth_call" below simulate at the logged state, some with a vault's code swapped in by a state override to compare versions.
- Staging uses 1% slippage, and the vault values the MUSD it holds above its debt at the oracle price less that 1%. The log calls this the 1% haircut.
- The log has four FAIL lines. Three were wrong checks, each followed by a NOTE and a corrected check. The fourth is the last-trove edge case.
- One staging transaction has status 0x0. It is explained under weak-system exits.

The private Mezo deployment, from [`deployments/staging.env`](deployments/staging.env):

| Contract | Address |
| --- | --- |
| BorrowerOperations | [`0x5f8A…Db05`](https://explorer.test.mezo.org/address/0x5f8A05fE4189215b0170670BE78B78Ca88FdDb05) |
| TroveManager | [`0x02E3…Bf73`](https://explorer.test.mezo.org/address/0x02E39021fEb0ee98a098A29951DED2A4F31eBf73) |
| PriceFeed | [`0x09Ed…333A`](https://explorer.test.mezo.org/address/0x09EdeF3e8a7752A27a0Ba3df7AD8f4B4E3fa333A) |
| MockAggregator, sets the price | [`0x36a9…46F4`](https://explorer.test.mezo.org/address/0x36a9FD8f522976a6Dc794EA3686de4b5225746F4) |
| InterestRateManagerTester, sets the rate | [`0xF2c8…1D27`](https://explorer.test.mezo.org/address/0xF2c8DC2DE25643B22a6dBEd3D81f7aEb80BD1D27) |
| MUSD | [`0xCa54…234D`](https://explorer.test.mezo.org/address/0xCa54b1c9fC66375D1B3689D0Bf8739a4669F234D) |
| sMUSD | [`0xe7ca…8532`](https://explorer.test.mezo.org/address/0xe7ca5E040dd9478e0c35607FA27C2E8890dc8532) |

Staging vaults, all with the same constructor arguments:

| Version | Address | What changed | Phases | Status |
| --- | --- | --- | --- | --- |
| v2 | [`0xdCf6…41d0`](https://explorer.test.mezo.org/address/0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0) | Same code as live v2 | Redemption, close refused (reverts) | Superseded |
| v3 | [`0x7412…9e31`](https://explorer.test.mezo.org/address/0x741222d0cD7BeB527b9E45082eC20318Ff899e31) | Closes only when Mezo allows | Band, rates and refinance, -50% and Recovery Mode | Superseded |
| v4 | [`0xd69e…06C1`](https://explorer.test.mezo.org/address/0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1) | Exits down to the line that holds the system at 150% | Weak-system exits, last trove | Superseded |
| v5 | [`0xE707…d69D`](https://explorer.test.mezo.org/address/0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D) | Covers the last-trove edge case | -60% and liquidation, close refused (goes through) | Same code as live v5 |

- Staging v2 has the same runtime length and metadata hash as live v2. The two differ only in constructor addresses.
- Staging v5 and live v5 both match the repo build outside the immutables (section 2).

### Redemption, partial and full

Vault: staging v2, superseded. The staging oracle reads 1,000,000 USD per BTC.

| Step | What happened | Tx |
| --- | --- | --- |
| Open | Alice deposits 0.008 BTC native, Bob 0.004 BTC through the ERC-20. Bob opens at 2.50 with the fee gap bought back. | [`0x811501c2`](https://explorer.test.mezo.org/tx/0x811501c256f9b8054e712a0d02e9c2ef2160cf9a42c95c0413401bd7c89a3161), [`0x489cf9b3`](https://explorer.test.mezo.org/tx/0x489cf9b3737a7b1e2a06bbfd8fb3b8d9965a54561f383679b8c0ca10f3a106f0), [`0xaa7add88`](https://explorer.test.mezo.org/tx/0xaa7add88884d84f998792b9bbc63949fb7e4b0c2844cfb16d35a468952d7b891) |
| Partial redemption | Someone redeems 300 MUSD. The vault trove has the lowest ratio, so it pays 300 MUSD of debt with 0.0003 BTC at the oracle price. NAV moves from 0.0119955 to 0.0119925 BTC, the 1% haircut on the 300 MUSD now held above the debt. | [`0x79da2300`](https://explorer.test.mezo.org/tx/0x79da230090ac20970edae3bb9712d793e0d4f52a210530af7f0ae1ef843fa7dd) |
| Buy back | The keeper harvests a 20 MUSD chunk into BTC | [`0x75565988`](https://explorer.test.mezo.org/tx/0x755659884c32593cb503ea49bf916c71a4bf6034ffa25f59bec37ca9c4f5d740) |
| Full redemption | 1800.01 MUSD is redeemed and the vault trove is closed by it. The leftover collateral sits in Mezo's CollSurplusPool and counts in NAV. | [`0x29037efa`](https://explorer.test.mezo.org/tx/0x29037efa5a9f1fe5c7a1cb4c63d4ba2d5e314e08c88a51c77b83fe0058904235) |
| Surplus claim | Bob, not the keeper, calls `rebalance()`. It claims the surplus into idle BTC, NAV stays at 0.00477982 BTC, and no trove this small is reopened. | [`0xcc366d39`](https://explorer.test.mezo.org/tx/0xcc366d396a91666a2b8a2bb8aa46c81ff5e1ab771efa37ecca9eb813a41dd835) |
| Stranger harvest | An arbitrage brings the pool back to the oracle, then Bob harvests 24.0 MUSD, which anyone may do once the trove is gone. NAV does not drop. | [`0xcd09dec6`](https://explorer.test.mezo.org/tx/0xcd09dec6d818935e83d5153cd4568ed2de932f245d59998787e4e9efa2f85bfb), [`0x308abbff`](https://explorer.test.mezo.org/tx/0x308abbffa8792920a79edddba17b59cc13cbf10a6d5ea2057055b77cf0d4fdb0) |
| Exits | Bob and Alice take their max from idle BTC. NAV per share is 0.996401 before and 0.996402 after. | [`0x6493a8f5`](https://explorer.test.mezo.org/tx/0x6493a8f5f106fe2566f01cf48814c3a3e525df82105e8a4517f996e08128dfa2), [`0x7ce49492`](https://explorer.test.mezo.org/tx/0x7ce49492561ed49b933010e41198aa8802dc6858b1d498c044200a8b13007710) |

### Band

Vault: staging v3, superseded. Alice 0.008 BTC and Bob 0.004 BTC, opened at 2.50 ([`0xa9ee636e`](https://explorer.test.mezo.org/tx/0xa9ee636ed308c19fc425b0a9af9ccfaf00d0e2500b2f93f4006ca6427f88c10e)).

| Step | What happened | Tx |
| --- | --- | --- |
| BTC -25% | 1,000,000 to 750,000. The ratio is 1.875, under the 200% floor. | [`0xd3446810`](https://explorer.test.mezo.org/tx/0xd34468102b72ce1895cefc45fc169a3291e2c5c720b2b281709344aa8b5544bb) |
| Repay | Bob's `rebalance()` repays 1164 MUSD from savings, debt 4656 to 3492, back to 2.50. Collateral and idle BTC are untouched and no BTC is sold. | [`0x812ac3c4`](https://explorer.test.mezo.org/tx/0x812ac3c4b396315e2f0f06eb4138ad34a56995ea3e9bcb9ec7525589a0875b9b) |
| BTC +50% | 750,000 to 1,125,000. The ratio is 3.75, above the 300% ceiling. | [`0xf27294be`](https://explorer.test.mezo.org/tx/0xf27294bef999632f31cf12f5ce021a6fefc81b0d3f4cab31ae906b37dda51ab0) |
| Borrow | `rebalance()` borrows 1746 MUSD, back to 2.50, inside the frozen borrowing capacity, with the fee covered by the cushion | [`0xfdd1fe6d`](https://explorer.test.mezo.org/tx/0xfdd1fe6dfc9e422319e49a8314fd4a6b26318495c6dbbd9598cbd3674208fcaf) |

### Rates and refinance

Vault: staging v3, superseded. The trove's own rate is 1%.

| Step | What happened | Tx |
| --- | --- | --- |
| Rate 3% | Mezo's rate goes to 3%, above the vault's 2% limit, and BTC to 1,500,000. `rebalance()` borrows nothing. | [`0x970b9c7e`](https://explorer.test.mezo.org/tx/0x970b9c7eaeaa8d37e7cded37ebb37ff38d42670a3832abaa5672ba30d55888dd), [`0x57d2006f`](https://explorer.test.mezo.org/tx/0x57d2006f4c7af03e133a333c01e13ac8cfeaf6342a7e6a88b1423b90f32ed916), [`0x298f7ab6`](https://explorer.test.mezo.org/tx/0x298f7ab69d4a5d8da05878d9cc6b1f5ba444e17b59c47e44e846106a4326ecca) |
| Rate 1.5% | Bob deposits 0.012 BTC. The target needs more than the frozen capacity, and a refinance would raise the trove's 1% rate. The loan stops at the capacity, 10581.8 MUSD, and keeps 1%. | [`0xb1cedbea`](https://explorer.test.mezo.org/tx/0xb1cedbead2625c93d970fcf9fa33f256531b5b401f473d85ea6bf6d30de78529), [`0x1aabd151`](https://explorer.test.mezo.org/tx/0x1aabd15132dc4a134ecf0804f3fbf685c8d6854a93681bf8855701cf9268695c), [`0x9878aeee`](https://explorer.test.mezo.org/tx/0x9878aeeee09a8b9748a6d722940c3b160f47ca959af7ee9b7a275e5f2a5b9856) |
| Rate 1% | The rate comes back to 1%, equal to the trove's. `rebalance()` refinances, the capacity resets to 31733.5 MUSD, and the loan reaches 2.50 at 13962.7 MUSD. | [`0xb47eb223`](https://explorer.test.mezo.org/tx/0xb47eb223f7a3b0c391089df221edc63d44261a9293278255b47be32666d2632d), [`0xeea3ddbc`](https://explorer.test.mezo.org/tx/0xeea3ddbcde4e9462d672b5c7b60c36ffeb4c0bc52a22793230b08585fa628e07) |
| BTC to 1,000,000 | `rebalance()` repays to 2.50 without selling BTC | [`0xb0d45421`](https://explorer.test.mezo.org/tx/0xb0d45421563a9624ddecfddd9b54699146a73275d1083859275534f4cc7c08d3), [`0xd63de73a`](https://explorer.test.mezo.org/tx/0xd63de73abe5ac952524648ceee5d3b91142ee26da7cddae545aba84963ab548b) |

- The first "no new debt" check FAILed because it compared debt for exact equality. The receipt holds one log, the vault's own `Rebalanced` event, so Mezo was not called. The corrected check passed.

### -50% in one block, Recovery Mode

Vault: staging v3, superseded.

| Step | What happened | Tx |
| --- | --- | --- |
| BTC -50% | One oracle update takes BTC from 1,000,000 to 500,000. The vault trove drops to 125%, above the 110% liquidation line. The system ratio is 1.265, so Mezo enters Recovery Mode. | [`0x6a89037a`](https://explorer.test.mezo.org/tx/0x6a89037a53bf97c797978091a08784788590eb6bfb0606b8fd4fecd5518f7d48) |
| Exits | Recovery Mode freezes trove collateral, so exits are limited to idle BTC, shared pro rata. Alice's request above her share is refused by the vault (eth_call, `ERC4626ExceededMaxWithdraw`). | eth_call |
| Exit and deposit | Alice takes her max from idle BTC. Bob deposits 0.002 BTC. | [`0x6e543a9b`](https://explorer.test.mezo.org/tx/0x6e543a9bf3f7d62b5d23fa544102cbafd6171a3b7502fa0767ccb2cca0040c80), [`0x876517fb`](https://explorer.test.mezo.org/tx/0x876517fbce4fd2a9361b40249124ad9f74d5d4d682755af779affb9e1f4abb58) |
| Repay in Recovery Mode | `rebalance()` repays from savings to 2.50, debt 9308 to 4654, and lifts the system out of Recovery Mode at a system ratio of 1.8075. The new BTC stays idle. | [`0x661e66c0`](https://explorer.test.mezo.org/tx/0x661e66c0c829e63a141fb1c7af39ae8495864ce5bccd31ff404cf04967ede13c) |
| Normal Mode | `rebalance()` adds the idle BTC above the buffer as collateral | [`0x3f8c0545`](https://explorer.test.mezo.org/tx/0x3f8c0545e6e2f6c0b8126d8e107b666e17bad51c286171d70a7aa0765a277e90) |

### -60% in one block, liquidation

Vault: staging v5, the same code as live v5.

| Step | What happened | Tx |
| --- | --- | --- |
| Open | BTC is back at 1,000,000. Alice deposits 0.005 BTC, Bob 0.0025 BTC, and Bob opens at 2.50. | [`0xaf0e9322`](https://explorer.test.mezo.org/tx/0xaf0e9322937cca442b6a7d822fa9efa888de645be0832d80ec3c17078043d188), [`0x1e48467b`](https://explorer.test.mezo.org/tx/0x1e48467b159379a7b7f7206786dd74e7b2cd1a547d02c579dc035c7614e21d2f), [`0x2a847be2`](https://explorer.test.mezo.org/tx/0x2a847be2aa8833970392083622e5af13b227a0489dac3c683613e1a0b0ba42fc), [`0x1de75e0b`](https://explorer.test.mezo.org/tx/0x1de75e0b7e45ea716e9f581cd92622406e9751173957f5ab43395c7674f57b45) |
| BTC -60% | One oracle update takes BTC from 1,000,000 to 400,000. The vault trove sits at 100%, under the 110% line. | [`0xd1c985b0`](https://explorer.test.mezo.org/tx/0xd1c985b03c65304f2eacc53c2cfeace7353d28d9442e928c946d1d3ae3fc1746) |
| Rescue window | A `rebalance()` in the same block would still repay the loan to 2.50 from savings | eth_call |
| Liquidation | A liquidator gets there first. The collateral is gone, the debt is cancelled, and the vault keeps all 2712.76 MUSD it held. | [`0x7d74cfa5`](https://explorer.test.mezo.org/tx/0x7d74cfa5e3d539d9d764a5b02967a561095aa582dcac47ae5fd1c3fd39b3cfd5) |
| Loss | NAV goes from 0.0075014 to 0.0069336 BTC. That is the 200 MUSD liquidation reserve (0.0005 BTC) plus the 1% haircut on 2712.76 MUSD (0.0000678 BTC), and nothing more. | |
| Stranger harvests | After an arbitrage to 400,000, Bob harvests two chunks, 15.16 and 15.18 MUSD. NAV does not drop. | [`0x707766d6`](https://explorer.test.mezo.org/tx/0x707766d65798f6053bbd5bb4e14540504cd4ed4ce8b249dde0cdb7e6a162db0e), [`0x4bc27cfc`](https://explorer.test.mezo.org/tx/0x4bc27cfc36a5f1db579d4310d4b34f694f298e628626b99b703b7791cc9591f7) |
| Exits | Both take their max from idle BTC at an unchanged share price | [`0xc847c710`](https://explorer.test.mezo.org/tx/0xc847c7108b6ebbb0dec2f7e8005c6f44c37a82279a622944651a8d494068c931), [`0xa2a58bfb`](https://explorer.test.mezo.org/tx/0xa2a58bfbc153ddd349d8aca3b8c5529d367a330dd537679e3fe8cf65b00fa939) |

### Close refused by Mezo

Mezo's `closeTrove` reverts if the rest of the system would end under 150%. This phase builds that situation twice, first on v2 and then on v5.

Vault: staging v2, superseded, the same code as live v2.

| Step | What happened | Tx |
| --- | --- | --- |
| Floor | Alice withdraws 0.0072 BTC. The loan is repaid down to the 2,000 MUSD floor and the trove stays open. | [`0x5e6cd2f3`](https://explorer.test.mezo.org/tx/0x5e6cd2f35dc3db77515a5467d96a1535cb73a908a35b162785d59ff37d70d497) |
| Weak system | The other borrower draws 3144 MUSD more | [`0xe8b95b2e`](https://explorer.test.mezo.org/tx/0xe8b95b2ed6f2a76292ad33c77001d40e27735c3754576a9b7d4a6af1eced4414) |
| BTC -15% | 1,000,000 to 850,000. The vault trove is at 191.7%, under its 200% floor, but closing it would leave the system under 150% (system ratio 1.536). The vault refuses exits, so none can revert inside Mezo. | [`0x1aa86f7d`](https://explorer.test.mezo.org/tx/0x1aa86f7d7704957a9929667f361b573596fb505e2c6808d465a11157cc79726a) |
| v2 `rebalance()` | Reverts inside Mezo with `BorrowerOps: An operation that would result in TCR < CCR is not permitted`. The keeper cannot act. | eth_call at block 16336751 |
| v3 code | At the same state with the v3 runtime swapped in, `rebalance()` goes through and keeps the trove at the floor | eth_call |
| Recovery | BTC is back at 1,000,000 and the other borrower repays. The v2 trove survived untouched. | [`0x6925f5f7`](https://explorer.test.mezo.org/tx/0x6925f5f73a61aa4d6f77b5c015b71ef856ed52e0ce86948337e3ab9779644204), [`0xa49c70dc`](https://explorer.test.mezo.org/tx/0xa49c70dc2ee93a87d72ffac04cafc96927c655a4265e9beb070f957bd9cef752) |

Vault: staging v5, the same code as live v5, with real transactions.

| Step | What happened | Tx |
| --- | --- | --- |
| Reopen | BTC is back at 1,000,000. Alice deposits 0.0065 BTC and Bob reopens the trove at 2.50 after the liquidation. | [`0xa85b1f26`](https://explorer.test.mezo.org/tx/0xa85b1f26312c155c1b2fa891e0244a2e9c64715e3fab18aa81b380a2ea291fe1), [`0x96c4f7a5`](https://explorer.test.mezo.org/tx/0x96c4f7a52cdb4b232aefad1eda70cfbafea477e2e39eb56f906bef78f8446dc1) |
| Floor | Alice withdraws 0.002064 BTC. The trove is pinned at the 2,000 MUSD floor at 225%. | [`0x51069798`](https://explorer.test.mezo.org/tx/0x5106979881d62ff0f64e8a127ec02a8aa4f6f3c2033886c3864cf18f0001023e) |
| Weak system | The other borrower refinances and borrows more, down to 171% | [`0xe7413248`](https://explorer.test.mezo.org/tx/0xe74132485181dfe0858f4e63e88e5a3ddb9f1e3476f116ad5761da9a233421da), [`0xb0445199`](https://explorer.test.mezo.org/tx/0xb0445199dd6df2546e819a712fd2c5e13804fadc6aaa2207e20607d99bb70f71) |
| BTC -15% | 1,000,000 to 850,000. The vault trove is at 191.25%, under its 200% floor, and a close would push the rest of the system under 150% (system ratio 1.556). Exits are limited to idle BTC. | [`0x58b5ddb0`](https://explorer.test.mezo.org/tx/0x58b5ddb049c7395a592fdbb894ec6728853911c266607e3d2a2fbf345bdf91e8) |
| v5 `rebalance()` | The same call that reverted on v2 goes through and keeps the trove open at the floor | [`0xabad7fe9`](https://explorer.test.mezo.org/tx/0xabad7fe9b768bb262d5fee444c9d1d89dd92ca7bbd280d54adc66fe96f179c38) |
| Close allowed | The other borrower repays. Bob's `rebalance()` closes the trove with MUSD the vault held, all collateral comes back as idle BTC, and no BTC is sold. | [`0xbe3f6916`](https://explorer.test.mezo.org/tx/0xbe3f691677907958d74c945b1b405e4e379ac7e55c5335b4dec8b210b364477e), [`0x36717900`](https://explorer.test.mezo.org/tx/0x3671790029e4f0847ef9ad70cd17e873389ee6f3723f5f5bcc410966194ac859) |
| Exits | Alice and Bob take idle BTC. Value per share stays exact. | [`0x65abc469`](https://explorer.test.mezo.org/tx/0x65abc46904e456dd252142cd412becda9f75f11542ade3fc927e2fefc9b1b5d6), [`0xd42e5fb6`](https://explorer.test.mezo.org/tx/0xd42e5fb67e21c1b870f88b88c3e574ff399af3f009bd2356a4909767bc189a4d) |

**v2 against v5 in the same situation.** v2's `rebalance()` reverts inside Mezo, so nobody can bring the trove back in band. v5's `rebalance()` succeeds and holds the trove at the floor until Mezo allows the close. Both calls replay read-only:

```bash
cast call --from 0xD323eAB315D1AE6C73A6Fe25a2854CB3DcD8B9f5 \
    0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0 'rebalance()' \
    -r https://rpc.test.mezo.org -b 16336751
cast call --from 0xD323eAB315D1AE6C73A6Fe25a2854CB3DcD8B9f5 \
    0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D 'rebalance()' \
    -r https://rpc.test.mezo.org -b 16337492
```

- The first is v2 at block 16336751. It returns `execution reverted: BorrowerOps: An operation that would result in TCR < CCR is not permitted`.
- The second is v5 at block 16337492, the block before [`0xabad7fe9`](https://explorer.test.mezo.org/tx/0xabad7fe9b768bb262d5fee444c9d1d89dd92ca7bbd280d54adc66fe96f179c38). It returns `0x`, a success.

### Weak-system exits

Vaults: staging v3 and v4, both superseded. When a full close would leave the rest of the system under 150%, v3 (and v2) pay exits from idle BTC only. v4 keeps the trove at target above the floor, keeps enough collateral to hold the rest of the system at 150%, and lets the rest go.

| Step | What happened | Tx |
| --- | --- | --- |
| v4 code on v3 state | At 500,000 with the other borrower alone at 129%, Bob's `maxWithdraw` goes from 0.000540 BTC (idle only) to 0.011002 BTC with v4 code, against a hand calculation of 0.011003. Withdrawing all of it goes through on v4 code and is refused on v3 code. | eth_call |
| v3 wound down | BTC is back at 1,000,000. Alice and Bob leave v3, and the second exit closes its trove. | [`0xd1d9d44e`](https://explorer.test.mezo.org/tx/0xd1d9d44e76a06303d9eb687439f481bf8b7d9068d34760dbf25da6b1f9b1ef0f), [`0x938dcda9`](https://explorer.test.mezo.org/tx/0x938dcda98276b9a8f994f50bc4246df09c089c133bad427d73b6755baeb6b020) |
| v4 open | Alice and Bob deposit 0.012 BTC each and Bob opens at 2.50 | [`0xf8b0a437`](https://explorer.test.mezo.org/tx/0xf8b0a4377ed82e73bf5a00969b2e30ac3473444b024cc4de03b49d64455ebcdd), [`0xb258c2e4`](https://explorer.test.mezo.org/tx/0xb258c2e41e2311023a690bce80c8b333853f465b31df9a30d40d2ff393af5c49), [`0xc777c230`](https://explorer.test.mezo.org/tx/0xc777c23035c6612824629d25bfce9cd023446190ef91cb9912653b240a89c29c) |
| Weak system | BTC goes to 550,000 and `rebalance()` brings the trove back to 2.50. The other borrower draws more and sits at 120%. The system is in Normal Mode, but the rest of it alone is under 150%. | [`0xad9b5ad8`](https://explorer.test.mezo.org/tx/0xad9b5ad8db68b071934141c5a2289fa98e05c330206e73ed769c2d7ead39fbad), [`0x8507676c`](https://explorer.test.mezo.org/tx/0x8507676ca110f63b6beb102c9a81bf95b14cc66f8cb33714112f1d473805bf32), [`0x63cff49b`](https://explorer.test.mezo.org/tx/0x63cff49bece2a243d384c921901af6e90d6c67c31514cfb74650604ad1a8514c) |
| Max matches | `maxWithdraw` is 0.0069942 BTC each, which is (idle 0.0007016 + collateral 0.02328 - keep 0.0099932) / 2 | |
| First exit | Bob's first max exit has status 0x0. The vault's own max check refused it because the max had moved since it was read, so Mezo was never reached. | [`0x3e5f7398`](https://explorer.test.mezo.org/tx/0x3e5f7398dd1af58f1e21ab6ce3bada0639598fb9db48301a5bca2c62f4c23c31) |
| Exits | With 0.001% of room, Bob's exit goes through. Alice's request for twice her max is refused by the vault (eth_call). Alice takes her max, then both take their max once more. | [`0xe7bcffbd`](https://explorer.test.mezo.org/tx/0xe7bcffbd3751c1ca608e3ba2857e0b3a9fbcf3b9637fbc8c6712adcc7a7dae32), [`0x1a996946`](https://explorer.test.mezo.org/tx/0x1a99694601ff6367032e35ed8fb9dfc5a8d4ad9530d8f236f906e9a5e7770942), [`0xea53831c`](https://explorer.test.mezo.org/tx/0xea53831c64b0d472654a91df178448922e1f58201ec0f924044befbaeb6e22b7), [`0xd48559ce`](https://explorer.test.mezo.org/tx/0xd48559ce59bacca79fd4eed38feda9ec3a15809ef0eb30383f889621e4c92a05) |
| Result | Collateral never dropped under the keep line, and the system ratio approached 150% from above, ending at 1.51019 | |

### Last trove

Vaults: staging v4, superseded, then the v5 code.

| Step | What happened | Tx |
| --- | --- | --- |
| Top up | Alice deposits 0.01 BTC and `rebalance()` borrows to 2.50 at 550,000 | [`0x61415b47`](https://explorer.test.mezo.org/tx/0x61415b476964a91d11d735af6757b49289a11a37fa8776b0393bbc98ef2968fe), [`0x71338613`](https://explorer.test.mezo.org/tx/0x71338613749a1d433d66f6526f37746599557bb8d74fb970645417351afa1a05) |
| Last trove | BTC drops 10% to 495,000. The other borrower falls under 110% and is liquidated. The vault trove is now the only trove in the system, which Mezo never lets close. | [`0x64d5e415`](https://explorer.test.mezo.org/tx/0x64d5e415be80ec27716bc35783001ec76d7673357629057511c2f324d5f23c1c), [`0x8cec9cfb`](https://explorer.test.mezo.org/tx/0x8cec9cfbaf00f76d6012dbc31ae1d2f475a46756fde3f0bb4a09a487d205c2ef) |
| Edge case | v5 also covers a Mezo-side edge case where the last trove cannot take a repayment; exits then release collateral only above 200% of today's debt. | v5 deployed in [`0x13a8974a`](https://explorer.test.mezo.org/tx/0x13a8974ac9a7cba2b4300dd5a63ae7d5c374ddf8e52c1caad5b44cae6d007796) |
| v5 code on v4 state | Alice's `maxWithdraw` is 0.0022449 BTC, the collateral above 200% of today's debt, against a hand calculation of 0.0022447. Withdrawing it, less 0.001%, goes through. | eth_call |
| Wind down | The other borrower opens a new trove. Bob's exit and then Alice's wind v4 down, and the second closes its trove. | [`0xc21fe266`](https://explorer.test.mezo.org/tx/0xc21fe266093279bfcc43d6aa7188683b9896f8bf84fb43eec4439743dc9154ed), [`0xd9a085b7`](https://explorer.test.mezo.org/tx/0xd9a085b76ad974f580ecf94bee36cc538b6e1eb3c5e988344f682a8976d18828), [`0x0b285c72`](https://explorer.test.mezo.org/tx/0x0b285c725b4bed0c54ab5cf1bba8c34ef4a9e37cb4c88c7f70c452530b1dea95) |

## 6. What is not proven yet

- **tBTC from Ethereum.** The app's tBTC deposit from Ethereum (Sepolia, through MezoBridge) has not had a signed live run. It needs Sepolia tBTC.
- **A closing exit on live v5.** v5 has not run a closing exit as a live testnet transaction, and both live positions are still open.
- **Closing exits elsewhere.** On staging, v5 closed its trove through `rebalance()` and then paid both exits from idle BTC (close refused phase). Exits that close the trove themselves ran live on v1 and v2, on staging v3 and v4, and in eth_call scenarios 3 and 9 on the v5 code.
- **Mainnet.** Nothing has run on mainnet. Every transaction, scenario and shock test on this page is on Mezo testnet.
- **Explorer verification.** The Mezo explorer does not show v5's source as verified yet. Sourcify does.
- **Keeper upkeep.** The keeper's own key has not sent a transaction yet, because no harvest or rebalance has been due since the move.
- **More BTC out on v5.** Among live testnet transactions, a gain in BTC per share shows on v1 only: +0.58% from one payout of 43.656 MUSD. Scenarios 1 and 10 show one with a payout the harness pays itself. v5 has had one live payout of 1.296 MUSD, and its share price is still under 1.0.
- **Audit.** The vault is unaudited.

## 7. Mainnet economics

The figures below come from [`README.md`](README.md) and were not measured again for this page.

- sMUSD's income is now mostly interest on Mezo's own 14.5M MUSD of Enclave loans at 1%, paid in lumps.
- That averages about 1% a year on 7.38M sMUSD.
- The 2.3% of the last 12 weeks also held redemption fees from the September to October redemption wave, which stopped once trove debt ran out.
- The vault's own loan costs about the same: 1% interest plus the 0.1% borrow fee.
- At today's numbers the strategy roughly breaks even on mainnet.
- MUSD also trades about 1% under the oracle, which would make a new vault trove the first redemption target.
- The mainnet MUSD/BTC pool is thin, so harvests there should be chunked with `harvest(maxIn)`.
- A mainnet launch waits until sMUSD pays more than the loan costs and MUSD trades near the oracle, with borrowing off by default.
- The testnet payouts on this page come from testnet fees and say nothing about mainnet yield.
