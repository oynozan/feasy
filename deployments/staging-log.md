# Private MUSD copy on Mezo testnet: crash, liquidation, redemption, recovery mode

Same contracts as the live MUSD (mezo-org/musd de1ec2af) plus the repo test hooks MockAggregator and InterestRateManagerTester. Real Mezo testnet, real BTC precompile, real DEX router and pool factory, real MUSDSavingsRate code.

Vault versions, v2 to v5 with the same constructor arguments, v6 adds the guardian and the unlock period:

| Version | Address | Ran |
| --- | --- | --- |
| v2, the code deployed live at 0x29CE…8B78 | 0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0 | partial and full redemption, the close Mezo refuses (reverts) |
| v3, closes only when Mezo allows | 0x741222d0cD7BeB527b9E45082eC20318Ff899e31 | band, rates and refinance, -50% and Recovery Mode |
| v4, exits down to the line that holds the system at 150% | 0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1 | weak system exits, last trove (hit a Mezo-side edge case, see Phase G) |
| v5, final, falls back to withdrawColl when Mezo cannot take a repayment | 0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D | -60% liquidation, the close Mezo refuses (goes through) |
| v6, profit unlock (3600 s here), guardian, borrowing off at deploy, redeem queue 0xE3BB5407594b2AB90a2e2B9b64E4aDE36d8c7C81 | 0xf3C209Ded3D4Ad30F2C940D012Ab8Cf71C526D30 | Recovery Mode with the queue, -60% liquidation, redemption, stale oracle, self-triggered sMUSD payouts |

Every check prints PASS or FAIL with the full vault snapshot. A FAIL is followed by a NOTE that explains it. Three were checks I wrote wrong, and one hit a Mezo-side edge case (Phase G).

## Setup
- fund deployer 0.03 BTC https://explorer.test.mezo.org/tx/0xdfa77da8aaa091fcbd43f5e4e7c0ba03b8afea5230dd34d36181199a727d7b7c
- `openTrove(uint256,address,address)` https://explorer.test.mezo.org/tx/0x56ba4634286e4c7de183dddabeebba67be03259633ae619c93970c1278eb864e (status 0x1, gas 696293)
- `createPool(address,address,bool)` https://explorer.test.mezo.org/tx/0x970af642fa2c0a9960698e8fcdf32597d5888749a02ce3bfc1ee8c1581232347 (status 0x1, gas 704840)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x4d31197d6dbbdc1ab6c444e582e97925a5d73d4dd56cc277c721ec99272c43c5 (status 0x1, gas 46406)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x6805bf2aebf7e1ad31b99a829622162391e11cadaa3b6cca68f442f11be77cfa (status 0x1, gas 25552)
- `addLiquidity(address,address,bool,uint256,uint256,uint256,uint256,address,uint256)` https://explorer.test.mezo.org/tx/0x39d14804c5b4ecb52a1d0019263c2f69b7f8424235f73d2ed11a7f74bbaf08af (status 0x1, gas 293289)
- Vault deployed https://explorer.test.mezo.org/address/0xdCf6638DE2ECC2C9175530BF5CfFaA0C00e441d0 tx https://explorer.test.mezo.org/tx/0x60a211a03a9eb99170b89bc3aa9e84b3d541c65dd3f15f940d6371993e0ef3fc

### Mainnet-like params, 1% slippage (this pool sits at the oracle price)
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0x0f7b8cd05350c7bcb8cf7a4ce17dd2504c3906142f845e6a15f57dce971f47cd (status 0x1, gas 43672)

### Alice deposits 0.008 BTC native, Bob 0.004 BTC through the ERC-20 path, Bob opens the trove
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x811501c256f9b8054e712a0d02e9c2ef2160cf9a42c95c0413401bd7c89a3161 (status 0x1, gas 171069)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xaec30332be3645fed1ed99fbbedceee662fbf24bb4d0a00b188e662abc8837eb (status 0x1, gas 25528)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x489cf9b3737a7b1e2a06bbfd8fb3b8d9965a54561f383679b8c0ca10f3a106f0 (status 0x1, gas 139516)
- `rebalance()` https://explorer.test.mezo.org/tx/0xaa7add88884d84f998792b9bbc63949fb7e4b0c2844cfb16d35a468952d7b891 (status 0x1, gas 1222550)
price        1000000.000000000000000000 USD/BTC
idle BTC     0.000351003376063936 (BTC token view 0.000351003376063936)
trove        active=true coll=0.011640000000000000 debt=4655.999999999999999999
ratio        2.5
savings      4460.514599237312106161 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.011995472829308874 BTC
share price  0.999622735776 BTC per 1e18 shares
ALICE        0.007996981874520529 BTC, max withdraw 0.007994002250709290
BOB        0.003998490937260264 BTC, max withdraw 0.003997001125354645
oracle 1000000.000000000000000000 pool 994031.5006301351 reserves MUSD 2991.033852311139442290 BTC 0.003008993025286490
TCR 2.544651005160398 recovery false rate 100
- PASS: trove opened at 2.5 with the fee gap bought back (price 1e+06, active True, coll 0.01164, debt 4656, held 4460.51, idle 0.000351003, total 0.0119955, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, ratio 2.5, owed 4456)

## Phase C: redemption against the vault trove

### Someone redeems 300 MUSD, the vault trove is the lowest ratio so it pays (NAV before 0.011995472652567395 BTC)
- `redeemCollateral(uint256,address,address,address,uint256,uint256)` https://explorer.test.mezo.org/tx/0x79da230090ac20970edae3bb9712d793e0d4f52a210530af7f0ae1ef843fa7dd (status 0x1, gas 417598)
- PASS: redemption took 300 MUSD of debt and 300 MUSD of BTC at the oracle price, NAV held within the 1% haircut on the new surplus (price 1e+06, active True, coll 0.01134, debt 4356, held 4460.51, idle 0.000351003, total 0.0119925, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007794, bob 0.003897, ratio 2.60331, owed 4156)

### Keeper harvests a 20 MUSD chunk to start buying the BTC back (shallow test pool)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x755659884c32593cb503ea49bf916c71a4bf6034ffa25f59bec37ca9c4f5d740 (status 0x1, gas 551094)
- PASS: harvest turned surplus MUSD back into BTC (price 1e+06, active True, coll 0.01134, debt 4356, held 4445.74, idle 0.000370982, total 0.0119978, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.00780732, bob 0.00390366, ratio 2.60331, owed 4156)

## Phase E1: a close Mezo refuses, on the deployed v2 bytecode

### Alice withdraws 0.0072 BTC, the loan is repaid down to the 2000 MUSD floor and the trove stays open
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x5e6cd2f35dc3db77515a5467d96a1535cb73a908a35b162785d59ff37d70d497 (status 0x1, gas 693296)
- PASS: withdrawal released collateral and repaid debt to the floor (price 1e+06, active True, coll 0.00451098, debt 2000, held 2089.74, idle 0, total 0.00479782, surplus 0, supply 0.00479869, cap 4100.89, recovery False, alice 0.000750807, bob 0.00376017, status 1, rate 100, tcr 2.49951, ratio 2.25549, owed 1800)

### The other borrower draws 3144 MUSD more, so without the vault the system would sit under 150% after a dip
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0xe8b95b2ed6f2a76292ad33c77001d40e27735c3754576a9b7d4a6af1eced4414 (status 0x1, gas 389595)

### BTC drops 15% to 850k, the vault trove is under its 200% floor but closing it would leave the system under 150%
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x1aa86f7d7704957a9929667f361b573596fb505e2c6808d465a11157cc79726a (status 0x1, gas 28841)
- PASS: exits are refused while a close would break the system ratio, so no withdrawal can revert inside Mezo (price 850000, active True, coll 0.00451098, debt 2000, held 2089.74, idle 0, total 0.00484844, surplus 0, supply 0.00479869, cap 4100.89, recovery False, alice 0, bob 0, status 1, rate 100, tcr 1.53564, ratio 1.91717, owed 1800)
- PASS: BUG in v2, rebalance reverts because Mezo refuses the close, so the keeper cannot act (reverted: execution reverted: BorrowerOps: An operation that would result in TCR < CCR is not permitted)
- Vault deployed https://explorer.test.mezo.org/address/0x741222d0cD7BeB527b9E45082eC20318Ff899e31 tx https://explorer.test.mezo.org/tx/0xb0e6373be00b3b61b70baa428650182259f9dfd77b3c675def406d64096e78b9
- PASS: same state, same call from Bob, with v2 code swapped for the fixed v3 runtime (eth_call state override), rebalance goes through and keeps the trove open at the floor (gas 806402)

### v3 deployed on staging, close is gated on the system ratio, https://explorer.test.mezo.org/address/0x741222d0cD7BeB527b9E45082eC20318Ff899e31

### Price back to 1M and the other borrower repays, the v2 trove is open and back in band
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x6925f5f73a61aa4d6f77b5c015b71ef856ed52e0ce86948337e3ab9779644204 (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x7cafb78bdaea7de7280fea4e28a4f7d9f22ec490ee5ac46096d5d114e370156d (status 0x1, gas 46406)
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0xa49c70dc2ee93a87d72ffac04cafc96927c655a4265e9beb070f957bd9cef752 (status 0x1, gas 347855)
- PASS: v2 trove survived the episode untouched and exits reopened (price 1e+06, active True, coll 0.00451098, debt 2000, held 2089.74, idle 0, total 0.00479782, surplus 0, supply 0.00479869, cap 4100.89, recovery False, alice 0.000750807, bob 0.00376017, status 1, rate 100, tcr 2.49855, ratio 2.25549, owed 1800)

## Phase C2: full redemption of the vault trove (v2, the redemption path is the same in v3)

### Someone redeems 1800.0100969675398 MUSD, the vault trove is the lowest ratio and is redeemed in full
- `redeemCollateral(uint256,address,address,address,uint256,uint256)` https://explorer.test.mezo.org/tx/0x29037efa5a9f1fe5c7a1cb4c63d4ba2d5e314e08c88a51c77b83fe0058904235 (status 0x1, gas 518852)
- PASS: closed by redemption, leftover collateral sits in CollSurplusPool and counts in NAV, MUSD kept is valued with the 1% haircut, exits pay pro rata from the surplus (price 1e+06, active False, coll 0, debt 0, held 2089.74, idle 0, total 0.00477982, surplus 0.00271098, supply 0.00479869, cap 4100.89, recovery False, alice 0.000451215, bob 0.00225977, status 4, rate 100, tcr 2.57685, ratio 0, owed 0)

### Bob, not the keeper, calls rebalance, it claims the surplus collateral and does not reopen a trove this small
- `rebalance()` https://explorer.test.mezo.org/tx/0xcc366d396a91666a2b8a2bb8aa46c81ff5e1ab771efa37ecca9eb813a41dd835 (status 0x1, gas 259430)
- PASS: surplus claimed into idle BTC, NAV unchanged, still no trove (price 1e+06, active False, coll 0, debt 0, held 2089.74, idle 0.00271098, total 0.00477982, surplus 0, supply 0.00479869, cap 4100.89, recovery False, alice 0.000451215, bob 0.00225977, status 4, rate 100, tcr 2.57685, ratio 0, owed 0)

### An arbitrageur pulls the pool back to the oracle, then Bob harvests a chunk, open to anyone once the trove is gone
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x0c946b125929f5e5287907af05fd935a0481188f6ff5bc3a9da5dd06a90d6e53 (status 0x1, gas 25552)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xcd09dec6d818935e83d5153cd4568ed2de932f245d59998787e4e9efa2f85bfb (status 0x1, gas 162982)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x308abbffa8792920a79edddba17b59cc13cbf10a6d5ea2057055b77cf0d4fdb0 (status 0x1, gas 459019)
- PASS: a stranger's harvest sold MUSD for BTC inside the oracle bound and NAV did not drop (price 1e+06, active False, coll 0, debt 0, held 2067.31, idle 0.00273478, total 0.00478142, surplus 0, supply 0.00479869, cap 4100.89, recovery False, alice 0.000455177, bob 0.00227961, status 4, rate 100, tcr 2.57685, ratio 0, owed 0)

### Bob and Alice take their max, paid from idle BTC, the rest of their claim is MUSD waiting for more harvests
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x6493a8f5f106fe2566f01cf48814c3a3e525df82105e8a4517f996e08128dfa2 (status 0x1, gas 122493)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x7ce49492561ed49b933010e41198aa8802dc6858b1d498c044200a8b13007710 (status 0x1, gas 122493)
- FAIL: both exits paid in full from idle, the MUSD left is still counted for them (price 1e+06, active False, coll 0, debt 0, held 2067.31, idle 0.000310387, total 0.00235703, surplus 0, supply 0.00236554, cap 4100.89, recovery False, alice 8.57312e-05, bob 0.000224655, status 4, rate 100, tcr 2.57685, ratio 0, owed 0)
- NOTE on the FAIL above: the check was wrong, not the vault. Alice's max was read after Bob's exit, and Bob still holds shares on the MUSD part, so her max is pro rata of the idle BTC left (the other 0.00031 BTC is hers to take next, or after a harvest)
- PASS: value stayed fair across both exits, NAV per share 0.00478142 / 0.00479869 = 0.996401 before and 0.00235703 / 0.00236554 = 0.996402 after
- v2 is left holding 0.00031 BTC and 2067 MUSD for Alice and Bob, anyone can harvest it into BTC

## Phases on the fixed v3 staging vault 0x741222d0cD7BeB527b9E45082eC20318Ff899e31

### Arbitrage the pool to the oracle, Alice deposits 0.008 BTC native, Bob 0.004 BTC through ERC-20, Bob opens the trove
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x85968301c02e0caffce33c974929fd2d941dd6543a0516ab2c5bf81bd21897bc (status 0x1, gas 25552)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x7b6d0e3095745c324934f7e9ebbaeef2927f5040ad78bf39b9d6808f127a63aa (status 0x1, gas 162982)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x09d0ef7b6a7952b03b384cd81920e2c97e660d944b60845e79e7cc413ca86aed (status 0x1, gas 171069)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xf157d51c5a2c9f53ea752e734101ea80cfcfac849cab8fc4ccb3cbccc6308c2d (status 0x1, gas 25540)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x0d6a19796eea99eaf45b82bb989fb119c281db9fe0087ed8b2e063a16f9a4e78 (status 0x1, gas 139516)
- `rebalance()` https://explorer.test.mezo.org/tx/0xa9ee636ed308c19fc425b0a9af9ccfaf00d0e2500b2f93f4006ca6427f88c10e (status 0x1, gas 1180628)
- PASS: trove opened at 2.5, fee gap bought back, 3% buffer idle (price 1e+06, active True, coll 0.01164, debt 4656, held 4460.51, idle 0.000351003, total 0.0119955, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 2.54392, ratio 2.5, owed 4456)

## Phase B: the ratio band

### BTC drops 25% to 750k, Bob rebalances, the loan is repaid from savings to 2.5 and no BTC is sold
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xd34468102b72ce1895cefc45fc169a3291e2c5c720b2b281709344aa8b5544bb (status 0x1, gas 28841)
- PASS: out of band below 200% (price 750000, active True, coll 0.01164, debt 4656, held 4460.51, idle 0.000351003, total 0.011997, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 1.90794, ratio 1.875, owed 4456)
- `rebalance()` https://explorer.test.mezo.org/tx/0x812ac3c4b396315e2f0f06eb4138ad34a56995ea3e9bcb9ec7525589a0875b9b (status 0x1, gas 669216)
- PASS: repaid to target, collateral and idle BTC untouched (price 750000, active True, coll 0.01164, debt 3492, held 3296.51, idle 0.000351003, total 0.011997, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 2.13686, ratio 2.5, owed 3292)

### BTC rises 50% to 1.125M, Bob rebalances, the trove borrows back up to 2.5
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xf27294bef999632f31cf12f5ce021a6fefc81b0d3f4cab31ae906b37dda51ab0 (status 0x1, gas 28841)
- PASS: out of band above 300% (price 1.125e+06, active True, coll 0.01164, debt 3492, held 3296.51, idle 0.000351003, total 0.011995, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 3.20529, ratio 3.75, owed 3292)
- `rebalance()` https://explorer.test.mezo.org/tx/0xfdd1fe6dfc9e422319e49a8314fd4a6b26318495c6dbbd9598cbd3674208fcaf (status 0x1, gas 762988)
- PASS: borrowed to target inside the frozen capacity, fee covered by the cushion (price 1.125e+06, active True, coll 0.01164, debt 5238, held 5041.31, idle 0.000351003, total 0.0119939, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 2.7164, ratio 2.5, owed 5038)

## Phase B: rates and the refinance rule

### Mezo rate goes to 3%, above the vault 2% limit, BTC rises to 1.5M, Bob rebalances, nothing is borrowed
- `setInterestRateForTesting(uint16)` https://explorer.test.mezo.org/tx/0x970b9c7eaeaa8d37e7cded37ebb37ff38d42670a3832abaa5672ba30d55888dd (status 0x1, gas 118147)
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x57d2006f4c7af03e133a333c01e13ac8cfeaf6342a7e6a88b1423b90f32ed916 (status 0x1, gas 28853)
- `rebalance()` https://explorer.test.mezo.org/tx/0x298f7ab69d4a5d8da05878d9cc6b1f5ba444e17b59c47e44e846106a4326ecca (status 0x1, gas 220711)
- FAIL: no new debt while the rate is above maxBorrowRate (price 1.5e+06, active True, coll 0.01164, debt 5238, held 5041.31, idle 0.000351003, total 0.0119932, surplus 0, supply 0.012, cap 10581.8, recovery False, alice 0.007994, bob 0.003997, status 1, rate 100, tcr 3.62186, ratio 3.33333, owed 5038)

### Rate 1.5%, above the trove 1%, Bob deposits 0.012 BTC, the pool is arbitraged to 1.5M, Bob rebalances
- `setInterestRateForTesting(uint16)` https://explorer.test.mezo.org/tx/0xb1cedbead2625c93d970fcf9fa33f256531b5b401f473d85ea6bf6d30de78529 (status 0x1, gas 101035)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x1aabd15132dc4a134ecf0804f3fbf685c8d6854a93681bf8855701cf9268695c (status 0x1, gas 141528)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x5c4748f4955c334cd9da41a2fbbd89a12cb64c3c51ec6163157515aedd2cf4cb (status 0x1, gas 46430)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xa18ec8244a9cf7197bdc83a261f2782b5663964b36d80b0d1317fff15b79f08c (status 0x1, gas 167294)
- `rebalance()` https://explorer.test.mezo.org/tx/0x9878aeeee09a8b9748a6d722940c3b160f47ca959af7ee9b7a275e5f2a5b9856 (status 0x1, gas 865733)
- PASS: target is above the frozen capacity and refinancing would cost more, so the loan stops at the capacity and keeps its 1% rate (price 1.5e+06, active True, coll 0.0232712, debt 10581.8, held 10394.2, idle 0.000711436, total 0.0239908, surplus 0, supply 0.0240068, cap 10581.8, recovery False, alice 0.00799194, bob 0.0159907, status 1, rate 100, tcr 3.50825, ratio 3.29875, owed 10381.8)

### Rate back to 1%, equal to the trove rate, Bob rebalances, the vault refinances and borrows to 2.5
- `setInterestRateForTesting(uint16)` https://explorer.test.mezo.org/tx/0xb47eb223f7a3b0c391089df221edc63d44261a9293278255b47be32666d2632d (status 0x1, gas 118135)
- `rebalance()` https://explorer.test.mezo.org/tx/0xeea3ddbcde4e9462d672b5c7b60c36ffeb4c0bc52a22793230b08585fa628e07 (status 0x1, gas 796748)
- PASS: refinance reset the capacity to today's collateral and the loan reached target, fees bought back (price 1.5e+06, active True, coll 0.0232712, debt 13962.7, held 13771.9, idle 0.000711436, total 0.0239887, surplus 0, supply 0.0240068, cap 31733.5, recovery False, alice 0.00799194, bob 0.0159907, status 1, rate 100, tcr 2.92025, ratio 2.5, owed 13762.7)

### BTC falls back to 1M, the pool follows, Bob rebalances to 2.5
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xb0d45421563a9624ddecfddd9b54699146a73275d1083859275534f4cc7c08d3 (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xf1fa0a767da6785d3041474e2b7a5f1ce7a2f3452752ae26336c27f12b5be8e8 (status 0x1, gas 25564)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x849fbf11269afbda2d7f1ad8c1d49af2e2702ca0e8d7d72165fad616b4d36b40 (status 0x1, gas 162994)
- `rebalance()` https://explorer.test.mezo.org/tx/0xd63de73abe5ac952524648ceee5d3b91142ee26da7cddae545aba84963ab548b (status 0x1, gas 643677)
- PASS: repaid to target without selling BTC (price 1e+06, active True, coll 0.0232712, debt 9308.48, held 9117.67, idle 0.000711436, total 0.0239917, surplus 0, supply 0.0240068, cap 31733.5, recovery False, alice 0.00799194, bob 0.0159907, status 1, rate 100, tcr 2.53075, ratio 2.5, owed 9108.48)
- NOTE on the FAIL above: the check compared debt for exact equality while interest accrues every second. The rebalance receipt holds a single log, the vault's own Rebalanced event with debt 5238.0001 (interest only), so Mezo was never called
- PASS: no new debt while the rate is above maxBorrowRate, the trove stayed at ratio 3.33 and kept its 1% rate

## Phase D: BTC -50% in one block, the whole system enters Recovery Mode

### Price 1M to 500k, the vault trove drops to 125%, still above the 110% liquidation line
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x6a89037a53bf97c797978091a08784788590eb6bfb0606b8fd4fecd5518f7d48 (status 0x1, gas 28841)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xf575b882d6bbce7ed3df209e33cf631467da58cbe99ae062c43d3b92caf082f7 (status 0x1, gas 25564)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xe9eb3ffd6c79a38303d964e45fd8d749291725f9a1673bf0fdabcae1cd847f0e (status 0x1, gas 162994)
- PASS: Recovery Mode freezes trove collateral, so exits are limited to idle BTC, shared pro rata (price 500000, active True, coll 0.0232712, debt 9308.48, held 9117.67, idle 0.000711436, total 0.0240008, surplus 0, supply 0.0240068, cap 31733.5, recovery True, alice 0.000237078, bob 0.000474358, status 1, rate 100, tcr 1.26537, ratio 1.25, owed 9108.48)
- PASS: Alice cannot withdraw more than her share of idle BTC in Recovery Mode (reverted: execution reverted: ERC4626ExceededMaxWithdraw(0xCea69E8C9fe8307a166F6165a9c591C3e74c780D, 474156171234874 [4.741e14], 237078085617437 [2.37e14]))

### Alice takes her max from idle, Bob deposits 0.002 BTC
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x6e543a9bf3f7d62b5d23fa544102cbafd6171a3b7502fa0767ccb2cca0040c80 (status 0x1, gas 201901)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x876517fbce4fd2a9361b40249124ad9f74d5d4d682755af779affb9e1f4abb58 (status 0x1, gas 141528)

### Bob rebalances inside Recovery Mode, the loan is repaid from savings and the new BTC stays idle
- `rebalance()` https://explorer.test.mezo.org/tx/0x661e66c0c829e63a141fb1c7af39ae8495864ce5bccd31ff404cf04967ede13c (status 0x1, gas 765428)
- PASS: pure repayment is allowed in Recovery Mode, it lifted the trove to 2.5 and pulled the system out of Recovery Mode (price 500000, active True, coll 0.0232712, debt 4654.24, held 4463.43, idle 0.00247436, total 0.0257638, surplus 0, supply 0.0257702, cap 31733.5, recovery False, alice 0.000745362, bob 0.001729, status 1, rate 100, tcr 1.8075, ratio 2.5, owed 4454.24)

### Bob rebalances again in Normal Mode, the idle BTC above the buffer joins the trove
- `rebalance()` https://explorer.test.mezo.org/tx/0x3f8c0545e6e2f6c0b8126d8e107b666e17bad51c286171d70a7aa0765a277e90 (status 0x1, gas 574668)
- PASS: spare BTC added as collateral once Mezo allows it (price 500000, active True, coll 0.0249727, debt 4654.24, held 4463.43, idle 0.000772913, total 0.0257638, surplus 0, supply 0.0257702, cap 31733.5, recovery False, alice 0.000232828, bob 0.000540085, status 1, rate 100, tcr 1.88581, ratio 2.68278, owed 4454.24)
- Vault deployed https://explorer.test.mezo.org/address/0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1 tx https://explorer.test.mezo.org/tx/0x57076db97e72b353c58b32786108d57664040d0f28e639c403276e1ba306f91b

## Exit liquidity when Mezo would refuse a full close

The other borrower alone sits at 129%, so closing the vault trove would put the system under 150%. v3 (and the deployed v2) then pays exits from idle BTC only. That also happens on mainnet the day the other troves close, because Mezo never lets the last trove close.
v4 keeps the trove at target above the floor and keeps enough collateral to hold the rest of the system at 150%, everything else is withdrawable.

### v4 deployed on staging https://explorer.test.mezo.org/address/0xd69eA337047E9EaB81262A9bC64AeC57eB8b06C1
- PASS: v3 state at 500k (eth_call with v3 code swapped for v4), Bob's maxWithdraw goes from 0.000540084962316892 BTC (idle only) to 0.011002461 BTC, the hand calculation gives 0.011003 (locked = max(floor at target 0.01, system keep 0.006568))
- PASS: withdrawing that whole 0.011002461 BTC as Bob goes through with the v4 code, Mezo accepts the system ratio after it, the same call reverts on v3 code (ERC4626ExceededMaxWithdraw)

### BTC back to 1M, the other borrower is healthy again, Alice and Bob leave v3, the second exit closes its trove
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xd6b652d3a717221dae708f14316b1b075ec8a67dcb2d21d23fc4180a87a6516b (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x8ffc44973cfea78f8566d7f1c24e6600dd9f72e92c33204fda735cb22aca0809 (status 0x1, gas 46430)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xd4642a4bb98ad6df916ce294dfb8c6839dbb9b991a1c1772f021a58cbe1b5836 (status 0x1, gas 167294)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xd1d9d44e76a06303d9eb687439f481bf8b7d9068d34760dbf25da6b1f9b1ef0f (status 0x1, gas 751920)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x938dcda98276b9a8f994f50bc4246df09c089c133bad427d73b6755baeb6b020 (status 0x1, gas 565038)
- PASS: v3 wound down, trove closed by its owner with the MUSD it held, only the MUSD cushion and redeem-max dust remain (price 1e+06, active False, coll 0, debt 0, held 9.18943, idle 6.60651e-06, total 1.5704e-05, surplus 0, supply 1.57131e-05, cap 7050.57, recovery False, alice 3.85654e-06, bob 2.74997e-06, status 2, rate 100, tcr 2.57685, ratio 0, owed 0)

### Alice and Bob deposit 0.012 BTC each into v4, Bob opens the trove
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xf8b0a4377ed82e73bf5a00969b2e30ac3473444b024cc4de03b49d64455ebcdd (status 0x1, gas 171069)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xef880e0bb773739e9de02dba996eea54bc8eb62c21d765d531ce58992f36425e (status 0x1, gas 25540)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0xb258c2e41e2311023a690bce80c8b333853f465b31df9a30d40d2ff393af5c49 (status 0x1, gas 139516)
- `rebalance()` https://explorer.test.mezo.org/tx/0xc777c23035c6612824629d25bfce9cd023446190ef91cb9912653b240a89c29c (status 0x1, gas 1108949)
- PASS: v4 trove opened at 2.5 with the fee bought back (price 1e+06, active True, coll 0.02328, debt 9312, held 9121.21, idle 0.000701603, total 0.0239907, surplus 0, supply 0.024, cap 21163.6, recovery False, alice 0.0119908, bob 0.0119908, status 1, rate 100, tcr 2.53074, ratio 2.5, owed 9112)

### BTC drops to 550k, Bob rebalances to 2.5, then the other borrower draws more and sits at 120%
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xad9b5ad8db68b071934141c5a2289fa98e05c330206e73ed769c2d7ead39fbad (status 0x1, gas 28841)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x5108d6377e75115d9b06884fcd631c51af04538fd1e277d952b6f20442fd6805 (status 0x1, gas 25564)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xd283829202b36af474154966f0391889a0870f800b318916c2a79f03822580a8 (status 0x1, gas 162994)
- `rebalance()` https://explorer.test.mezo.org/tx/0x8507676ca110f63b6beb102c9a81bf95b14cc66f8cb33714112f1d473805bf32 (status 0x1, gas 655266)
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0x63cff49bece2a243d384c921901af6e90d6c67c31514cfb74650604ad1a8514c (status 0x1, gas 358646)
- PASS: vault at target, system in Normal Mode, but the rest of the system alone is under 150% (price 550000, active True, coll 0.02328, debt 5121.6, held 4930.81, idle 0.000701603, total 0.0239982, surplus 0, supply 0.024, cap 21163.6, recovery False, alice 0.0069942, bob 0.0069942, status 1, rate 100, tcr 1.73471, ratio 2.5, owed 4921.6)
- PASS: maxWithdraw is 0.0069942 BTC each, the hand calculation is idle 0.0007016 + collateral 0.02328 - keep 0.0099932, halved, where keep = (1.5 x 7332.33 - 8799.99) x 2.5 / 550k binds above the floor lock 0.0090909

### Bob withdraws his max, Alice tries twice hers and is refused by the vault, then takes her max
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x3e5f7398dd1af58f1e21ab6ce3bada0639598fb9db48301a5bca2c62f4c23c31 (status 0x0, gas 524037)
- NOTE on the status 0x0 above: the vault refused it with ERC4626ExceededMaxWithdraw(Bob, 0.006994202850, 0.006994202826), Mezo was never reached. Mezo's system debt accrues interest live, so the line that keeps the system at 150% rises about 1.6e-11 BTC a second and a max read one block earlier is stale. Callers leave 0.001% of room, scripts/vault.sh withdraw-max does that like redeem-max

### Bob withdraws his max with the 0.001% margin, Alice tries twice hers and is refused by the vault, then takes her max
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xe7bcffbd3751c1ca608e3ba2857e0b3a9fbcf3b9637fbc8c6712adcc7a7dae32 (status 0x1, gas 617285)
- PASS: Mezo accepted the exit, the trove repaid to target and the system stays above 150% (price 550000, active True, coll 0.0169875, debt 3737.24, held 3546.85, idle 0, total 0.0170048, surplus 0, supply 0.0170053, cap 8493.74, recovery False, alice 0.00493558, bob 0.00205869, status 1, rate 100, tcr 1.63901, ratio 2.5, owed 3537.24)
- PASS: an exit past the line is refused by the vault before it reaches Mezo (reverted: execution reverted: ERC4626ExceededMaxWithdraw(0xCea69E8C9fe8307a166F6165a9c591C3e74c780D, 9871165840709040 [9.871e15], 4935582920354520 [4.935e15]))
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x1a99694601ff6367032e35ed8fb9dfc5a8d4ad9530d8f236f906e9a5e7770942 (status 0x1, gas 600185)

### Both take their max once more, the collateral converges on the keep line and the system on 150%
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xea53831c64b0d472654a91df178448922e1f58201ec0f924044befbaeb6e22b7 (status 0x1, gas 600185)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xd48559ce59bacca79fd4eed38feda9ec3a15809ef0eb30383f889621e4c92a05 (status 0x1, gas 600173)
- PASS: every exit went through, collateral never dropped under the keep line, the system ratio approached 150% from above (price 550000, active True, coll 0.0104392, debt 2296.63, held 2106.24, idle 0, total 0.0104565, surplus 0, supply 0.0104569, cap 5219.61, recovery False, alice 0.000268949, bob 0.000177081, status 1, rate 100, tcr 1.51019, ratio 2.5, owed 2096.63)

## Phase G: the vault becomes the last trove in the system, as it would on mainnet if the other troves leave

### Alice deposits 0.01 BTC, Bob rebalances and the trove borrows to 2.5 at 550k
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x61415b476964a91d11d735af6757b49289a11a37fa8776b0393bbc98ef2968fe (status 0x1, gas 141528)
- `rebalance()` https://explorer.test.mezo.org/tx/0x71338613749a1d433d66f6526f37746599557bb8d74fb970645417351afa1a05 (status 0x1, gas 631158)
- PASS: vault trove at target (price 550000, active True, coll 0.0198255, debt 4361.62, held 4169.68, idle 0.000613696, total 0.0204537, surplus 0, supply 0.0204572, cap 5219.61, recovery False, alice 0.00832613, bob 0.0021199, status 1, rate 100, tcr 1.68498, ratio 2.5, owed 4161.62)

### BTC dips 10% to 495k, the other borrower falls under 110% and is liquidated, the vault trove is now the only one
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x64d5e415be80ec27716bc35783001ec76d7673357629057511c2f324d5f23c1c (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xf899ab7578081fe4b6bbf2dc1e1d6893d0bb3b2ac582f520efe244479bf6a09c (status 0x1, gas 25552)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x3ac971fd3a88191ec578c9367f4b0bcdea38d487474329af2a394d4f2ada8b35 (status 0x1, gas 162982)
- `liquidate(address)` https://explorer.test.mezo.org/tx/0x8cec9cfbaf00f76d6012dbc31ae1d2f475a46756fde3f0bb4a09a487d205c2ef (status 0x1, gas 536331)
- PASS: last trove, Mezo will never let it close, exits still take everything above the floor held at target (price 495000, active True, coll 0.0198255, debt 4361.62, held 4169.68, idle 0.000613696, total 0.0204554, surplus 0, supply 0.0204572, cap 5219.61, recovery False, alice 0.0082402, bob 0.00209802, status 1, rate 100, tcr 2.25, ratio 2.25, owed 4161.62)
- PASS: same state with v3 code swapped in (eth_call), Alice's maxWithdraw is 0.000489 BTC (idle only) against 0.008240 BTC on v4

### Bob and Alice take their max from the last trove, then Alice is refused anything below the floor
- Vault deployed https://explorer.test.mezo.org/address/0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D tx https://explorer.test.mezo.org/tx/0x13a8974ac9a7cba2b4300dd5a63ae7d5c374ddf8e52c1caad5b44cae6d007796
- FAIL (Mezo-side edge case, see below): Bob's withdraw-max from the last trove reverts inside Mezo. A bare withdrawColl and rebalance in band still work

### Mezo-side edge case on the last trove
The last trove in the system cannot take a repayment, so a v4 exit that has to repay reverts inside Mezo. v5 pays those exits through withdrawColl instead and releases collateral only above 200% of today's debt.

### v5 deployed on staging https://explorer.test.mezo.org/address/0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D, it handles the last-trove edge case and exits through withdrawColl above the band floor
- PASS: v4 state (eth_call with v4 code swapped for v5), Alice's maxWithdraw goes from 0.008240 BTC, which reverts inside Mezo, to 0.0022449 BTC, the collateral above 200% at today's debt (hand calculation 0.0022447)
- PASS: withdrawing that 0.0022449 BTC (less the 0.001% margin) goes through with v5 code and reverts inside Mezo on v4 code, rebalance goes through on both

### The other borrower opens a new trove at 495k, the vault is no longer the last one and v4 works again
- `openTrove(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc21fe266093279bfcc43d6aa7188683b9896f8bf84fb43eec4439743dc9154ed (status 0x1, gas 531181)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xd9a085b76ad974f580ecf94bee36cc538b6e1eb3c5e988344f682a8976d18828 (status 0x1, gas 710463)
- PASS: v4 repays again once a second trove exists, Bob's exit repaid the loan to target (price 495000, active True, coll 0.0162914, debt 3225.69, held 3034.36, idle 0, total 0.0163087, surplus 0, supply 0.016309, cap 5219.61, recovery False, alice 0.0162881, bob 3.31087e-06, status 1, rate 100, tcr 2.67896, ratio 2.5, owed 3025.69)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x0b285c725b4bed0c54ab5cf1bba8c34ef4a9e37cb4c88c7f70c452530b1dea95 (status 0x1, gas 569947)
- PASS: v4 wound down, Alice's exit closed the trove (price 495000, active False, coll 0, debt 0, held 8.6644, idle 3.47377e-06, total 2.08026e-05, surplus 0, supply 2.08029e-05, cap 5219.61, recovery False, alice 2.92031e-06, bob 5.53463e-07, status 2, rate 100, tcr 2.96733, ratio 0, owed 0)

## Phase F on v5 0xE7075B9054f0CeC8dbb901f06071Dd77CD9ad69D: BTC -60% in one block and the vault trove is liquidated

### BTC back to 1M, Alice deposits 0.005 BTC and Bob 0.0025 BTC, Bob opens the trove
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xaf0e9322937cca442b6a7d822fa9efa888de645be0832d80ec3c17078043d188 (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x6847a185274f2c7f3d7bc89954f8f22e2cc0906037936b816a5be2886d3b1a35 (status 0x1, gas 46430)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x3e185608359d4395bc6de6003cc6183cd93b1501d791b54cb4795ef619250174 (status 0x1, gas 236973)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x1e48467b159379a7b7f7206786dd74e7b2cd1a547d02c579dc035c7614e21d2f (status 0x1, gas 171069)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x2a847be2aa8833970392083622e5af13b227a0489dac3c683613e1a0b0ba42fc (status 0x1, gas 133943)
- `rebalance()` https://explorer.test.mezo.org/tx/0x1de75e0b7e45ea716e9f581cd92622406e9751173957f5ab43395c7674f57b45 (status 0x1, gas 1111415)
- PASS: v5 trove opened at 2.5 (price 1e+06, active True, coll 0.007275, debt 2910, held 2712.76, idle 0.000219529, total 0.00749726, surplus 0, supply 0.0075, cap 6613.64, recovery False, alice 0.00499635, bob 0.00249818, status 1, rate 100, tcr 3.92422, ratio 2.5, owed 2710)

### One oracle update takes BTC from 1M to 400k, the vault trove sits at 100%, under the 110% line
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xd1c985b03c65304f2eacc53c2cfeace7353d28d9442e928c946d1d3ae3fc1746 (status 0x1, gas 28829)
- PASS: trove under MCR and liquidatable (price 400000, active True, coll 0.007275, debt 2910, held 2712.76, idle 0.000219529, total 0.00750137, surplus 0, supply 0.0075, cap 6613.64, recovery False, alice 0.00499635, bob 0.00249818, status 1, rate 100, tcr 1.56969, ratio 1, owed 2710)
- PASS: a keeper in the same block could still rescue it, rebalance (eth_call) repays the loan back to 2.5 from savings

### A liquidator gets there first
- `liquidate(address)` https://explorer.test.mezo.org/tx/0x7d74cfa5e3d539d9d764a5b02967a561095aa582dcac47ae5fd1c3fd39b3cfd5 (status 0x1, gas 430931)
- PASS: collateral gone, debt cancelled, the vault keeps every MUSD it held, NAV is idle BTC plus that MUSD at the oracle less the 1% haircut, exits pay pro rata from idle (price 400000, active False, coll 0, debt 0, held 2712.76, idle 0.000219529, total 0.00693362, surplus 0, supply 0.0075, cap 6613.64, recovery False, alice 0.000146352, bob 7.31762e-05, status 3, rate 100, tcr 2.39784, ratio 0, owed 0)
- PASS: the NAV drop across the liquidation is exactly what was forfeited, 0.0075014 to 0.0069336 BTC = the 200 MUSD liquidation reserve kept by the liquidator (0.0005 BTC) plus the 1% haircut now applied to all 2712.76 MUSD (0.0000678 BTC)

### The pool is arbitraged to 400k, Bob harvests two chunks (open to anyone once the trove is gone), then both take their max
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x94fbb282414e120050cf550bd387bb106f64053716262a0270511cb21297e035 (status 0x1, gas 25564)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x6e9a582690e20ac01cbd0fcc3676eba3cb3cfaf5683e14431c2cf72659c451cd (status 0x1, gas 162994)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x707766d65798f6053bbd5bb4e14540504cd4ed4ce8b249dde0cdb7e6a162db0e (status 0x1, gas 461249)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x33b7080057f7b4da39c1afdc9210d7ae610a270dc369b4d95ac776cb13eb57b9 (status 0x1, gas 25552)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x68a05405332736289e29430e7f94d0bb0e5f969a074e3318c84fec3d4303544c (status 0x1, gas 162982)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x4bc27cfc36a5f1db579d4310d4b34f694f298e628626b99b703b7791cc9591f7 (status 0x1, gas 326914)
- PASS: stranger's harvests turned MUSD into BTC inside the oracle bound, NAV did not drop (price 400000, active False, coll 0, debt 0, held 2682.43, idle 0.000294842, total 0.00693385, surplus 0, supply 0.0075, cap 6613.64, recovery False, alice 0.000196561, bob 9.82805e-05, status 3, rate 100, tcr 2.39784, ratio 0, owed 0)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc847c7108b6ebbb0dec2f7e8005c6f44c37a82279a622944651a8d494068c931 (status 0x1, gas 122476)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xa2a58bfbc153ddd349d8aca3b8c5529d367a330dd537679e3fe8cf65b00fa939 (status 0x1, gas 122476)
- PASS: both exits paid from idle at an unchanged share price (price 400000, active False, coll 0, debt 0, held 2682.43, idle 6.36379e-05, total 0.00670264, surplus 0, supply 0.00724992, cap 6613.64, recovery False, alice 4.26267e-05, bob 2.10113e-05, status 3, rate 100, tcr 2.39784, ratio 0, owed 0)

## Phase E on v5: a close Mezo refuses, with real transactions on the final code

### BTC back to 1M, Alice deposits 0.0065 BTC, Bob reopens the trove
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xd31088b1d3ed5026b5176adc6274985e0b60486f575af1fe921a0bb38ec3f828 (status 0x1, gas 28829)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xe9fd4c8e7c5fd68949f73e46dd8cb480ed1930014e5005a26d013c70d5036dc7 (status 0x1, gas 46430)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xcf3deab75295d0e23418a526cf2767aa18a82a6d3da7ae290374863dbadd0a4a (status 0x1, gas 167294)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xa85b1f26312c155c1b2fa891e0244a2e9c64715e3fab18aa81b380a2ea291fe1 (status 0x1, gas 119643)
- `rebalance()` https://explorer.test.mezo.org/tx/0x96c4f7a52cdb4b232aefad1eda70cfbafea477e2e39eb56f906bef78f8446dc1 (status 0x1, gas 871102)
- PASS: trove reopened at 2.5 after the liquidation (price 1e+06, active True, coll 0.00628706, debt 2514.82, held 4995.59, idle 0.000276577, total 0.00921759, surplus 0, supply 0.0245799, cap 5715.51, recovery False, alice 0.00592444, bob 0.000639194, status 1, rate 100, tcr 4.04883, ratio 2.5, owed 2314.82)

### Alice withdraws 0.002063637938977122 BTC, the trove is pinned at the 2000 MUSD floor at about 225%
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x5106979881d62ff0f64e8a127ec02a8aa4f6f3c2033886c3864cf18f0001023e (status 0x1, gas 678479)
- PASS: pinned at the floor (price 1e+06, active True, coll 0.0045, debt 2000, held 4480.76, idle 0, total 0.00715396, surplus 0, supply 0.019077, cap 4090.91, recovery False, alice 0.00393536, bob 0.000564641, status 1, rate 100, tcr 4.12314, ratio 2.25, owed 1800)

### The other borrower draws 5006.64 MUSD and sits at 171%, then BTC dips 15% to 850k
- `refinance(address,address)` https://explorer.test.mezo.org/tx/0xe74132485181dfe0858f4e63e88e5a3ddb9f1e3476f116ad5761da9a233421da (status 0x1, gas 360807)
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0xb0445199dd6df2546e819a712fd2c5e13804fadc6aaa2207e20607d99bb70f71 (status 0x1, gas 374973)
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x58b5ddb049c7395a592fdbb894ec6728853911c266607e3d2a2fbf345bdf91e8 (status 0x1, gas 28841)
- PASS: under the 200% band floor, a close would push the rest of the system under 150%, exits are limited to idle BTC (price 850000, active True, coll 0.0045, debt 2000, held 4480.76, idle 0, total 0.0076223, surplus 0, supply 0.019077, cap 4090.91, recovery False, alice 0, bob 0, status 1, rate 100, tcr 1.55601, ratio 1.9125, owed 1800)

### Bob rebalances, the same call that reverted on v2
- `rebalance()` https://explorer.test.mezo.org/tx/0xabad7fe9b768bb262d5fee444c9d1d89dd92ca7bbd280d54adc66fe96f179c38 (status 0x1, gas 651440)
- PASS: rebalance went through and kept the trove open at the floor instead of reverting inside Mezo (price 850000, active True, coll 0.0045, debt 2000, held 4482.6, idle 0, total 0.00762443, surplus 0, supply 0.019077, cap 4090.91, recovery False, alice 0, bob 0, status 1, rate 100, tcr 1.55601, ratio 1.9125, owed 1800)

### The other borrower repays, so a close is allowed again, and Bob rebalances
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xc2d69375b6f836476a090b85ac316d914f7b1dc5118ce6e86a733a2491f999b4 (status 0x1, gas 29318)
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0xbe3f691677907958d74c945b1b405e4e379ac7e55c5335b4dec8b210b364477e (status 0x1, gas 367433)
- `rebalance()` https://explorer.test.mezo.org/tx/0x3671790029e4f0847ef9ad70cd17e873389ee6f3723f5f5bcc410966194ac859 (status 0x1, gas 626611)
- PASS: trove under the band at the floor closed with MUSD the vault held, all collateral back as idle BTC, no BTC sold (price 850000, active False, coll 0, debt 0, held 2682.6, idle 0.0045, total 0.00762443, surplus 0, supply 0.019077, cap 4090.91, recovery False, alice 0.00393536, bob 0.000564641, status 2, rate 100, tcr 5.08179, ratio 0, owed 0)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x65abc46904e456dd252142cd412becda9f75f11542ade3fc927e2fefc9b1b5d6 (status 0x1, gas 122488)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xd42e5fb67e21c1b870f88b88c3e574ff399af3f009bd2356a4909767bc189a4d (status 0x1, gas 122476)
- FAIL: Alice and Bob took the idle BTC, what remains is MUSD for harvests (price 850000, active False, coll 0, debt 0, held 2682.6, idle 0.000418246, total 0.00354268, surplus 0, supply 0.00886408, cap 4090.91, recovery False, alice 0.000322589, bob 9.5657e-05, status 2, rate 100, tcr 5.08179, ratio 0, owed 0)
- NOTE on the FAIL above: the check was wrong again, exits share the idle BTC pro rata among everyone still holding shares, so the second exit leaves its holder's next slice behind, value per share stays exact

## Cleanup
The deployer trove is now the last one on staging, so Mezo will not let it close and the last-trove edge case applies. Collateral above the system floor can still leave through withdrawColl, and the staging price is ours to set.
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x8cc384af65c615985ff34a6da0f1d03fa142e4c2c22b74c13d951f2e8b93b060 (status 0x1, gas 28841)
- `withdrawColl(uint256,address,address)` https://explorer.test.mezo.org/tx/0x5ea4d9f90e774e44baad9fb167bf83edca3c7314f0a1e7d6e9ff2965b9ce8858 (status 0x1, gas 345442)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xe2a88786794489975ac7466d19da0bfe1eb358703fd77488cc9058902e5fa8b0 (status 0x1, gas 49046)
- `removeLiquidity(address,address,bool,uint256,uint256,uint256,address,uint256)` https://explorer.test.mezo.org/tx/0x8f38935fd3aa1cbf816316acb68147cd012cff10e17986e12cc01afb6ea8d1d8 (status 0x1, gas 317237)

## v6 on staging: profit unlock, guardian and the redeem queue

v6 is v5 plus the profit unlock (A), the guardian with borrowing off at deploy (B) and the redeem queue (D), plus `_canBuy` reading the v2 factory's pause. The concentrated route (C) and the veBTC sleeve (E) are not in this build. This copy unlocks over 3600 s instead of 7 days, with the same runtime code.

Price regime: BTC at 20M USD. The deployer's own trove (0.000341 BTC, 2007 MUSD, the only trove before this run) sits at 340% there, at 170% after -50% and 136% after -60%, so it stays open and above 110% through every phase and the vault trove is never the last one.

### Setup: Bob funds the deployer for the pool's BTC side and tops the guardian up for gas
- `transfer to 0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1` https://explorer.test.mezo.org/tx/0x88511e91577cabce1d1a7422ce7907e32503c91841d97c66a1c5622334e10bed (status 0x1, gas 21000)
- `transfer to 0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE` https://explorer.test.mezo.org/tx/0xdbebe51bc9a5f6b661d08eb995ad0b2dd2647715b192cea181dee0b69b04cecf (status 0x1, gas 21000)

### BTC to 20M, then the drained v2 pool is repriced (a 1e-8 BTC donation and sync move its dust reserves from 1M to the oracle) and reseeded with 0.0002 BTC and 4000 MUSD
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x4ce09cef0ea6d17eb45271d0c944c7e3cae834c1e607130b7c65af758d54ad10 (status 0x1, gas 28841)
- `transfer(address,uint256)` https://explorer.test.mezo.org/tx/0x24557a9ceefe9d8b5bda81a9b259a792c646249890a2e5ce408731eea407274e (status 0x1, gas 25516)
- `transfer(address,uint256)` https://explorer.test.mezo.org/tx/0x762876d9aac2b07514980f5a3b24c8b967937ba3b26fba5b2c079b29b80d7fea (status 0x1, gas 34573)
- `sync()` https://explorer.test.mezo.org/tx/0xd3dbee2cedda1289c3f0545c1fadb435ed8fcf6920dad380079272ffd91c3713 (status 0x1, gas 143418)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xe642e8a287dfb588092e6a6db6d2b16fa5dfe9fa40d64ee2f96e36c4331ad388 (status 0x1, gas 46406)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x9b67cd725a226603b3b5fe25476e133e771fb6e4ecce90328dbd7c3ecb0f5efa (status 0x1, gas 25540)
- `addLiquidity(address,address,bool,uint256,uint256,uint256,uint256,address,uint256)` https://explorer.test.mezo.org/tx/0xeaedef3f59f4714ae85d79e95be451e636dc1b731835d38d10c7d25d3a53c0a3 (status 0x1, gas 170506)

### v6 deployed on staging, deployer owner, KEEPER keeper, GUARDIAN guardian, 3600 s unlock
- Vault deployed https://explorer.test.mezo.org/address/0xf3C209Ded3D4Ad30F2C940D012Ab8Cf71C526D30 (queue 0xE3BB5407594b2AB90a2e2B9b64E4aDE36d8c7C81, block 16354018) tx https://explorer.test.mezo.org/tx/0xb8b9a8ed9785774f5c6b9931c68bb2ac5cb329f80fa37c9a0881a162f9d80ce7

### Band 2 / 2.5 / 3, 3% idle buffer, 1% slippage (the reseeded pool charges 0.04% and a harvest chunk up to about 0.95% of its MUSD side fits), 2% max borrow rate
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0xbc6984e5a4d049e1f43ca7bea15bb06ceb2de25b6a0930f1e433ccb10048be12 (status 0x1, gas 44246)
- PASS: borrowing is off at deploy, no trove (price 2e+07, active False, coll 0, debt 0, held 0, idle 0, total 0, surplus 0, supply 0, cap 0, recovery False, alice 0, bob 0, status 0, rate 0, tcr 3.39993, block 16354036, stale False, recorded 0, locked 0, gain 0, pps 1000000000000000000, queued 0, reserved 0, borrowing False, slip 100, ratio 0, owed 0, raw 0)

### Alice deposits 0.00012 BTC native, Bob 0.0003 BTC through the ERC-20 path, the keeper rebalances while borrowing is still off
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x4b4cfc300fccf4e89f291fdf5c5e66f5d6e94a08e53590650f1bd1e95b1bf1d3 (status 0x1, gas 215871)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xc2c932a0a5e0ded2cdd6b533acf9ac51a26b9b7e08c5b18ac9ef5fb9fc49d1a7 (status 0x1, gas 25552)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x9afcbcfde5114448a7e48aa47f45bf20d5f4d5d0e6dc1a73a45ddd35ed612f95 (status 0x1, gas 150244)
- `rebalance()` https://explorer.test.mezo.org/tx/0x7712803ad529b0ef527fe9a5b651f511679cc10b566a62bc9f2fbe24c06ba4d0 (status 0x1, gas 186279)
- PASS: borrowing off, rebalance opens no trove, every holder can take the full balance (price 2e+07, active False, coll 0, debt 0, held 0, idle 0.00042, total 0.00042, surplus 0, supply 0.00042, cap 0, recovery False, alice 0.00012, bob 0.0003, status 0, rate 0, tcr 3.39993, block 16354048, stale False, recorded 0.00042, locked 0, gain 0, pps 1000000000000000000, queued 0, reserved 0, borrowing False, slip 100, ratio 0, owed 0, raw 0.00042)

### The owner enables borrowing, the keeper rebalances and the vault trove opens at 2.5
- `setBorrowingEnabled(bool)` https://explorer.test.mezo.org/tx/0x96da2cbb01ae1f5743fb64277f8a994bdcb03b0b2ba7d62bc3702a3374a44ab6 (status 0x1, gas 48172)
- `rebalance()` https://explorer.test.mezo.org/tx/0x8abe68bfc6d825ab2ccf84d8a4de2871a721f1bba7c34c9ccf66c81193cffbed (status 0x1, gas 1132196)
- PASS: trove opened at 2.5 with the fee gap bought back, 3% buffer idle (price 2e+07, active True, coll 0.0004074, debt 3259.2, held 3062.31, idle 1.22912e-05, total 0.000419845, surplus 0, supply 0.00042, cap 7407.27, recovery False, alice 0.000119912, bob 0.000299779, status 1, rate 100, tcr 2.84299, block 16354058, stale False, recorded 0.00042, locked 0, gain 0, pps 999631045141797619, queued 0, reserved 0, borrowing True, slip 100, ratio 2.5, owed 3059.2, raw 0.000419845)
- an arbitrageur pulls the pool back to the oracle after the buyback
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x7f1a0804b1d882fb6639d24502ac1f6f38c70f5dfe3751a957e5276669468028 (status 0x1, gas 29318)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0xe5b1f201adb9d118e6c9f386a6759071a3bfad7f4199598c0398583226e34b03 (status 0x1, gas 167282)

## S1 on v6: Recovery Mode with the queue

### BTC drops 50% from 20M to 10M in one oracle update, the vault trove falls from 250% to 125% and the system enters Recovery Mode
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xe6dea47f5d41714ddf71b75f89c9276995c58b1044846a53a21dd7888cca820b (status 0x1, gas 28841)
- PASS: Recovery Mode, instant maxWithdraw is each holder's pro rata slice of idle BTC only (price 1e+07, active True, coll 0.0004074, debt 3259.2, held 3062.31, idle 1.22912e-05, total 0.000419999, surplus 0, supply 0.00042, cap 7407.27, recovery True, alice 3.51176e-06, bob 8.77941e-06, status 1, rate 100, tcr 1.4215, block 16354076, stale False, recorded 0.00042, locked 0, gain 0, pps 999997370052504761, queued 0, reserved 0, borrowing True, slip 100, ratio 1.25, owed 3059.2, raw 0.000419999)

### Alice queues every share she holds, about 0.00012 BTC against 0.0000123 BTC liquid
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x344fcb7725769b849f740390c4614daacc7e8a7c8248d8e7ec70e6fd37be1b76 (status 0x1, gas 194817)
- PASS: request escrowed at the queue, the waiting request is ahead of every instant exit, so nothing is instantly liquid (price 1e+07, active True, coll 0.0004074, debt 3259.2, held 3062.31, idle 1.22912e-05, total 0.000419999, surplus 0, supply 0.00042, cap 7407.27, recovery True, alice 0, bob 0, status 1, rate 100, tcr 1.4215, block 16354087, stale False, recorded 0.00042, locked 0, gain 0, pps 999997358367116666, queued 0.00012, reserved 0, borrowing True, slip 100, ratio 1.25, owed 3059.2, raw 0.000419999)

### Fill 1, anyone calls processQueue in Recovery Mode
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0x73c83b8f0c5225b878cebac1e17badada97e82ea4f5ebb935cb0b5145f04dfd2 (status 0x1, gas 293930)
- PASS: fill 1 in Recovery Mode took idle BTC only, one QueueFilled and no trove move. The receipt holds two logs, the vault's burn of 12291207699874104445 escrowed shares and QueueFilled(shares 12291207699874104445, assets 12291175135263). It paid 12291175135263 wei of the 12291175135264 idle. Trove collateral 407400000000000 wei before and after, debt 3259.200162149500369996 to 3259.200165247898466238 MUSD (one block of interest), no Mezo contract emitted anything
- PASS: fill 1 kept the value per share for queued and staying holders. convertToAssets(1e24) 999997351307195238 at block 16354094, 999997350576859523 at the fill's own checkpoint, 999997350576861976 after it at block 16354095, the fill paid 999997350576778164 per 1e24 shares (12291175135263 wei for 12291207699874104445 shares). The fill moved the value per share by 2453 wei, all rounding in the vault's favour. Between the two blocks it moved -730335715 wei, which is the change in totalAssets between them (-306741 wei of BTC, the same for every share)
- NOTE: the -306741 wei between the two blocks is the trove's interest for one block (3.0984e-6 MUSD of debt, at 10M and 1% slippage), which lowers raw and so every share

### The guardian pauses borrowing with a real transaction, then its unwind is tried by eth_call in Recovery Mode
- `pauseBorrowing()` https://explorer.test.mezo.org/tx/0x95ae6e2ee190a322bab50e77d2e888aae63b9c0349256e0b51167560fd4da9c5 (status 0x1, gas 25064)
- PASS: guardian pauseBorrowing went through, borrowing is off and the trove is untouched (price 1e+07, active True, coll 0.0004074, debt 3259.2, held 3062.31, idle 1e-18, total 0.000407708, surplus 0, supply 0.000407709, cap 7407.27, recovery True, alice 0, bob 0, status 1, rate 100, tcr 1.4215, block 16354135, stale False, recorded 0.000407708, locked 0, gain 0, pps 999997308445028362, queued 0.000107709, reserved 1.22912e-05, borrowing False, slip 100, ratio 1.25, owed 3059.2, raw 0.000407708)
- PASS: guardian unwind reverts inside Mezo, closeTrove is refused in Recovery Mode (reverted: execution reverted: BorrowerOps: Operation not permitted during Recovery Mode)
- PASS: a stranger cannot pause borrowing (reverted: execution reverted: NotGuardian)
- PASS: the keeper cannot unwind (reverted: execution reverted: NotGuardian)

### Fill 2, Bob deposits 0.00002 BTC in Recovery Mode and the keeper rebalances while the request waits
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xfc528968e706612adf36d62ea44b9b4c9b41bc596bf8a815d29eed0fa2fe7125 (status 0x1, gas 152163)
- `rebalance()` https://explorer.test.mezo.org/tx/0x563f5e351e143aac28fa4366040614447086649a48c725d153720fc9d8a1593b (status 0x1, gas 746615)
- PASS: state after the Recovery Mode rebalance (price 1e+07, active True, coll 0.0004074, debt 2000, held 1803.11, idle 1e-18, total 0.000407708, surplus 0, supply 0.000407709, cap 7407.27, recovery False, alice 0, bob 0.000319691, status 1, rate 100, tcr 1.86818, block 16354155, stale False, recorded 0.000407708, locked 0, gain 0, pps 999997290267019706, queued 8.77087e-05, reserved 3.22912e-05, borrowing False, slip 100, ratio 2.037, owed 1800, raw 0.000407708)
- PASS: the rebalance's fill took idle BTC only, one QueueFilled(shares 20000054139405606874, assets 20000000000000), exactly the 20000000000000 wei Bob had just deposited (idle 20000000000001 before, 1 after). Collateral stayed 407400000000000 wei, nothing was released for the queue
- PASS: fill 2 kept the value per share for queued and staying holders. convertToAssets(1e24) 999997293993329591 at block 16354149, 999997293037097324 at the fill's own checkpoint, 999997293037099777 after it at block 16354150, the fill paid 999997293037047324 per 1e24 shares (20000000000000 wei for 20000054139405606874 shares). The fill moved the value per share by 2453 wei, all rounding in the vault's favour. Between the two blocks it moved -956232267 wei, which is the change in totalAssets between them (-408989 wei of BTC, the same for every share)
- NOTE: the same rebalance also ran the v5 band rule, the trove was at 125% (under minCR) so it repaid 1259.200402791752511458 MUSD from savings with no collateral change (debt 3259.2 to 2000, the loan floor, ratio 1.25 to 2.037). A pure repayment is allowed in Recovery Mode and it lifted the whole system out (TCR 1.4215 to 1.8682), as docs/v6-spec.md 10.4 expects. So the rebalance moved the trove's debt, but nothing in it was caused by the queue. The guardian checks ran first for that reason, while the system was still in Recovery Mode

### Fill 3, BTC back to 20M, anyone calls processQueue, it frees collateral and finishes the request
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x8ca1989f56522a7a3baab6af7f65f3e37aaf8106414ca31295b5cbe8ceb22b88 (status 0x1, gas 28841)
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0xce54ed83d2454a80a29e4aa5e4e2964025ffd3473284be0c8ea449331e86b1d0 (status 0x1, gas 681161)
- PASS: back at 20M processQueue freed collateral and finished the request. QueueFilled(shares 87708738160720288681, assets 87675403980344) took the last 1 wei of idle and a withdrawColl of 87675403980343 wei (collateral 407400000000000 to 319724596019657, debt 2000.00008 MUSD unchanged), queue.pending() 0 afterwards. The trove stays open at 319.7%
- PASS: fill 3 kept the value per share for queued and staying holders. convertToAssets(1e24) 999619944821598459 at block 16354180, 999619944590757226 at the fill's own checkpoint, 999619944590758629 after it at block 16354181, the fill paid 999619944590752108 per 1e24 shares (87675403980344 wei for 87708738160720288681 shares). The fill moved the value per share by 1403 wei, all rounding in the vault's favour. Between the two blocks it moved -230841233 wei, which is the change in totalAssets between them (-94116 wei of BTC, the same for every share)

### Anyone claims request 1, Alice is paid what the three fills set aside
- `claim(uint256[])` https://explorer.test.mezo.org/tx/0x96748f24cd7d36a9a79d18928292d4797cf0dfb572221331e317d3e8fa7d37bb (status 0x1, gas 54046)
- PASS: claim paid the receiver, Alice's BTC rose by 119966579115607 wei, the sum of the three fills (12291175135263 + 20000000000000 + 87675403980344), and queue.reserved() is back to 0. The claim was sent by the deployer, the BTC went to the receiver fixed at request time

## S2 on v6: BTC -60% and the vault trove is liquidated

### The owner turns borrowing back on after the guardian's pause, the keeper rebalances and the trove borrows from 319.7% back to 2.5
- `setBorrowingEnabled(bool)` https://explorer.test.mezo.org/tx/0x007ceb420d173828e725f75487894d2bfe3e350c75aced8d89d6cb16af89277f (status 0x1, gas 48172)
- `rebalance()` https://explorer.test.mezo.org/tx/0x0275ede576cb6d334cd8516d30fb92fbc9e5db8cf5dff132409b4b37d3e87000 (status 0x1, gas 728293)
- PASS: trove back at 2.5 at 20M (price 2e+07, active True, coll 0.000319725, debt 2557.8, held 2360.42, idle 0, total 0.000319855, surplus 0, supply 0.00032, cap 5813.17, recovery False, alice 0, bob 0.000319725, status 1, rate 100, tcr 2.89569, block 16354214, stale False, recorded 0.000319878, locked 0, gain 0, pps 999545580539179751, queued 0, reserved 0, borrowing True, slip 100, ratio 2.5, owed 2357.8, raw 0.000319855)

### Bob queues about 0.00001 BTC of shares before the crash, nobody fills it until after the liquidation
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc3d2e5b41532648525be14fae4c8ed65b874905a39e726c8d993ef7f2b521a2b (status 0x1, gas 182529)

### One oracle update takes BTC from 20M to 8M (-60%), the vault trove sits at 100%, the deployer trove at 136%
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x21fce6bc5bd8355fa2af19f95ba8f5e409d8438f05dd1106112b9e8667c40aa0 (status 0x1, gas 28841)
- PASS: vault trove under the 110% MCR and liquidatable (price 8e+06, active True, coll 0.000319725, debt 2557.8, held 2360.42, idle 0, total 0.000319878, surplus 0, supply 0.00032, cap 5813.17, recovery True, alice 0, bob 0, status 1, rate 100, tcr 1.15828, block 16354232, stale False, recorded 0.000319878, locked 0, gain 1.71266e-07, pps 999619931355760866, queued 1.00045e-05, reserved 0, borrowing True, slip 100, ratio 1, owed 2357.8, raw 0.00032005)

### A 30 MUSD sMUSD payout through the real receiveProtocolYield, then anyone syncs, so a lock exists before the crash
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x9f37faea65515146c72e2ed4a431213a4479673d6b71a351bc3ca9f94a55cd85 (status 0x1, gas 46406)
- `receiveProtocolYield(uint256)` https://explorer.test.mezo.org/tx/0x97122792876c96ab9a15e3af90981c6e08c010a126b4beb521fd250803cefe26 (status 0x1, gas 57714)
- PASS: the payout raised raw, it waits in pendingProfit and is not in totalAssets yet (price 8e+06, active True, coll 0.000319725, debt 2557.8, held 2370.36, idle 0, total 0.000319878, surplus 0, supply 0.00032, cap 5813.17, recovery True, alice 0, bob 0, status 1, rate 100, tcr 1.15828, block 16354243, stale False, recorded 0.000319878, locked 0, gain 1.40059e-06, pps 999619931355760866, queued 1.00045e-05, reserved 0, borrowing True, slip 100, ratio 1, owed 2357.8, raw 0.000321279)
- `sync()` https://explorer.test.mezo.org/tx/0x8b9eb6c64f621f0dba28ac5a67ac70e2f71d77e9a0e3e40aa2c01a8a46442e0c (status 0x1, gas 140677)
- PASS: sync locked the payout and the price drop gain (price 8e+06, active True, coll 0.000319725, debt 2557.8, held 2370.36, idle 0, total 0.000319878, surplus 0, supply 0.00032, cap 5813.17, recovery True, alice 0, bob 0, status 1, rate 100, tcr 1.15828, block 16354248, stale False, recorded 0.000321279, locked 1.40059e-06, gain 0, pps 999619931355760866, queued 1.00045e-05, reserved 0, borrowing True, slip 100, ratio 1, owed 2357.8, raw 0.000321279)

### A liquidator calls the real TroveManager.liquidate on the vault trove
- `liquidate(address)` https://explorer.test.mezo.org/tx/0x29c4ec70b8a44b23204110c7ac8a23c9d1caf93f47e514e2e38dcbabc55d2b94 (status 0x1, gas 428931)
- PASS: the liquidation loss exceeds the lock, totalAssets falls by exactly the excess. Raw 321279016742930 to 293331788636760 wei, a loss of 27947228106170 wei (the 200 MUSD reserve the liquidator keeps and the 1% haircut now on all 2370.357888 MUSD). The lock still standing under totalAssets was 1388134977768 wei (lockedProfit 1388138187481 less the 3209713 wei of interest since the sync). totalAssets 319890881765162 to 293331788636760, down 26559093128402 = loss - lock, and totalAssets now equals raw
- PASS: Bob's request made before the liquidation takes the same per-share loss as everyone. His 10004546324519099148 queued shares went from 10001133139153 to 9170784287174 wei (0.916974522744), convertToAssets(1e24) from 999658836567445013 to 916661684568234329 (0.916974522744)
- NOTE: right after the liquidation lockedProfit() still reads 1386581978750 wei, because Mezo's liquidate is not a vault entry point and the stored lock only nets a loss at the next checkpoint. totalAssets already ignores it (it is min(raw, recorded - lock) and raw is below both), so the share price is right, only the view lags until the sync below

### Anyone syncs after the liquidation, the checkpoint nets the loss against the lock
- `sync()` https://explorer.test.mezo.org/tx/0xf905aee221af6257cbd41cd69e0276c10b163d9505c9e5db89824b31028fbc44 (status 0x1, gas 111442)
- PASS: after the sync lockedProfit() is 0 and recorded equals raw (293331788636760). totalAssets 293331788636760 at block 16354284 and 293331788636760 at block 16354285, unchanged, with the trove gone nothing accrues and the checkpoint itself changes nothing, the sync emitted no ProfitLocked since there was no gain

### BTC back to 20M, where the pool still sits, so a harvest can sell at the oracle
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xa023f90b11e1d56bfdae89fcd9f53739adcd5d1ee0d0417e1b26a190ed93df53 (status 0x1, gas 28841)
- PASS: price restored, the vault holds MUSD only and its BTC value fell with the higher price, a loss that shows at once (price 2e+07, active False, coll 0, debt 0, held 2370.36, idle 0, total 0.000117333, surplus 0, supply 0.00032, cap 5813.17, recovery False, alice 0, bob 0, status 3, rate 100, tcr 3.39992, block 16354310, stale False, recorded 0.000293332, locked 0, gain 0, pps 366664673827295606, queued 1.00045e-05, reserved 0, borrowing True, slip 100, ratio 0, owed 0, raw 0.000117333)

### Alice, a stranger, harvests 22 MUSD of what the liquidation left behind (anyone may once the trove is closed)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0xb679285d8d19b5d32cc3294f7f269bb009554b5f8e3a39acd926202e33c11854 (status 0x1, gas 548129)
- PASS: a stranger's harvest converted MUSD left behind by the liquidation. Harvested(musdIn 22000000000000000000, btcOut 1093536096454), the oracle floor at 1% was 1089000000000 wei, the pool paid 4536096454 wei over it
- PASS: the harvest's second checkpoint locked that gain in the same transaction, ProfitLocked(gain 4538254150, locked 4538254150, unlockAt 1792910483), unlockAt = the tx time 1792906883 + 3600. Right after it lockedProfit() reads 4538254150 and pendingProfit() 0. The gain is the 4536096454 wei sale premium plus 2157696 wei from the PCV payout the vault's own sMUSD withdraw triggered
- PASS: the harvest paid Bob's waiting request from the BTC it had just bought, QueueFilled(2982387381471800588 shares, 1093536096453 wei), at a share price that leaves the locked premium out. convertToAssets(1e24) 366664673827295606 at block 16354319, 366664673827295606 at the fill's own checkpoint, 366664673827298761 after it at block 16354320, the fill paid 366664673826960305 per 1e24 shares (1093536096453 wei for 2982387381471800588 shares). The fill moved the value per share by 3155 wei, all rounding in the vault's favour. Between the two blocks it moved 0 wei, which is the change in totalAssets between them (0 wei of BTC, the same for every share)
- NOTE: pendingProfit() shows the harvest gain only inside the transaction, because harvest takes its second checkpoint right after the sale (docs/v6-spec.md 3.7) and so the gain is locked before anyone can read it. lockedProfit() is the view that shows it
- an arbitrageur pulls the pool back to the oracle after the sale
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xeb27a2412ade52ce3bb835328f2302fba3841133032aec178afd5b3e78e2ba72 (status 0x1, gas 25540)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x71b5184ea7da8b364a0f4e917602d3990009ac6a5287accaa0e602db980cac74 (status 0x1, gas 162970)
- PASS: the locked gain streams into totalAssets. From block 16354320 to 16354354 lockedProfit() went 4538254150 to 4357984610 and totalAssets rose by the same 180269540 wei, with no transaction to the vault in between

## S3 on v6: redemption against the vault trove

### Bob deposits 0.00035 BTC, the keeper rebalances, the fill pays the rest of Bob's S2 request from idle first and the spare reopens the trove at 2.5
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xb564df3e8627308447737597914bf40d7ffa68437b13b42b25f9db00af40905e (status 0x1, gas 127865)
- `rebalance()` https://explorer.test.mezo.org/tx/0x9fc33dd3dc1f2da0fbf8e9d1eae3f0a30acb5594c6fb2e953312db4a1ae51804 (status 0x1, gas 950945)
- PASS: trove reopened at 2.5 after the queue was paid (price 2e+07, active True, coll 0.000333515, debt 2668.12, held 4814.42, idle 1.39101e-05, total 0.000463567, surplus 0, supply 0.00126454, cap 6063.91, recovery False, alice 0, bob 0.000347425, status 1, rate 100, tcr 2.88636, block 16354378, stale False, recorded 0.000463669, locked 4.23444e-09, gain 0, pps 366588304310935653, queued 0, reserved 3.66832e-06, borrowing True, slip 100, ratio 2.5, owed 2468.12, raw 0.000463567)
- PASS: the rebalance paid the queue before the trove, QueueFilled(7022158943047298560 shares, 2574783621788 wei) from the idle Bob had just deposited, 366665528745588413 per 1e24 shares, the share value at its checkpoint. Request 2 is now fully filled (filledShares 130004546324519099148, its end). Only then did the same rebalance open the trove (0.000333515148358495 BTC, 2668.12 MUSD). The 2.4657 MUSD borrow fee, not bought back since the vault already held more MUSD than the loan, lowered the value per share of the holders who stay, after the request was paid

### A 100 MUSD sMUSD payout through receiveProtocolYield and a sync, so a lock larger than the coming haircut stands before the redemption
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xb124490ca7a8dfcd784e36c64a58da4f28496325213515ba645dcb6296ce0083 (status 0x1, gas 46406)
- `receiveProtocolYield(uint256)` https://explorer.test.mezo.org/tx/0x9c5ffdee11ec97319062aa94229b7803e275f99bbb59b9a22a338cdec370800e (status 0x1, gas 57714)
- `sync()` https://explorer.test.mezo.org/tx/0xd2404a945bb53ada5c3a0374a312849a3dae1f84b50b0e5d58cdfe1e11dfe142 (status 0x1, gas 138294)
- PASS: lock in place (price 2e+07, active True, coll 0.000333515, debt 2668.12, held 4864.66, idle 1.39101e-05, total 0.000463669, surplus 0, supply 0.00126454, cap 6063.91, recovery False, alice 0, bob 0.000347425, status 1, rate 100, tcr 2.88636, block 16354398, stale False, recorded 0.000466054, locked 2.38452e-06, gain 0, pps 366669297219403750, queued 0, reserved 3.66832e-06, borrowing True, slip 100, ratio 2.5, owed 2468.12, raw 0.000466054)

### Someone redeems 2468.131300164149 MUSD through the real TroveManager.redeemCollateral, the vault trove is the lowest ratio and is redeemed in full
- `redeemCollateral(uint256,address,address,address,uint256,uint256)` https://explorer.test.mezo.org/tx/0x4d86fe74ed2dc248d911898eb51c3f80eebafd8846c63457bf30399c2de2f23d (status 0x1, gas 490098)
- PASS: the lock absorbs the redemption haircut. Raw 466053965399994 to 464819904571513 wei, down 1234060828481 wei, which is the 1% haircut on the 2468.121322146991352226 MUSD of loan the redemption burned (1234060661073 wei) plus the loan's interest in that block before the redemption (167407 wei), 1234060828480 by hand, 1 wei of rounding. The standing lock was 2348013105960 wei. totalAssets 463705954888855 to 463708610261325, up 2655372470 wei (the lock's release over one block), so the share price did not drop. Collateral 333515148358495 became 210109082251146 wei of surplus in CollSurplusPool, the trove is closed by redemption (status 4)
- NOTE: the first version of this check compared the drop with the debt read one block earlier and missed that block's interest, an error in the check, not in the vault
- NOTE: totalAssets stays at recorded - lockedProfit = 466053967994815 - 2345357733490 while raw sits at 464819904571513, between the two. The haircut is only netted into the lock at the next checkpoint, which the sync below shows

### Anyone syncs, the checkpoint nets the haircut into the lock
- `sync()` https://explorer.test.mezo.org/tx/0x244ce7127ffebde9206dd60843e380acf5a406dd82ce60a31ed62dbd526c9485 (status 0x1, gas 111442)
- PASS: the sync netted the haircut into the lock. recorded 466053967994815 to 464819904571513 (raw, 1234063423302 wei lower, the haircut plus interest up to the redemption), lockedProfit 2266360402529 to 1030305449875, totalAssets 463787607592286 to 463789599121638, the 1991529352 wei difference is the one block of release between the reads. The lock left after paying the haircut keeps unlocking to its old end

### Bob queues about 0.00005 BTC, more than the 0.0000139 BTC idle, and anyone processes the queue, the fill claims the surplus collateral
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x78dcf0ac385d74ab4dc8649fac9855d7c6be37e48a4ab78e8a1936b92d769652 (status 0x1, gas 165441)
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0xf225560586a888744fcd51fdef8938a21164ec89746351522dbfa4e3963ad14e (status 0x1, gas 264216)
- PASS: the next fill claims the surplus collateral. processQueue's release called claimCollateral (CollSurplusPool's two events in the receipt), the vault's surplus went 210109082251146 to 0 wei, idle 13910068019718 + 210109082251146 - 50000683820039 paid = 174018466450825, and QueueFilled(136323956314221884832 shares, 50000683820039 wei) paid request 3 in full
- PASS: the surplus-claiming fill kept the value per share. convertToAssets(1e24) 366777453651315068 at block 16354455, 366778409106537966 at the fill's own checkpoint, 366778409106538396 after it at block 16354456, the fill paid 366778409106534415 per 1e24 shares (50000683820039 wei for 136323956314221884832 shares). The fill moved the value per share by 430 wei, all rounding in the vault's favour. Between the two blocks it moved 955455222898 wei, which is the change in totalAssets between them (1208215127 wei of BTC, the same for every share)
- requests 2 and 3 (Bob) are filled and left unclaimed for S4, claimable 3668319718241 and 50000683820039 wei, reserved 53669003538280

## S4 on v6: stale oracle

### Before the oracle goes stale, a 5 MUSD sMUSD payout leaves a pending gain, and the live price moves to 25M with no vault call, so the vault's lastPrice stays 20M
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x9277bffb1cfcfda1384cdd5aeb15179566f561fdce3683116d73772ea0eb16dc (status 0x1, gas 46394)
- `receiveProtocolYield(uint256)` https://explorer.test.mezo.org/tx/0xba3d6799502d30afdc8e44b3e210a1773dda3d051cdc0990bd55c3e141151e36 (status 0x1, gas 57702)
- PASS: the payout waits in pendingProfit (price 2e+07, active False, coll 0, debt 0, held 4867.17, idle 0.000174018, total 0.000413836, surplus 0, supply 0.00112822, cap 6063.91, recovery False, alice 0, bob 0.000174018, status 4, rate 100, tcr 3.39992, block 16354479, stale False, recorded 0.000414819, locked 9.82883e-07, gain 1.24347e-07, pps 366804646250569437, queued 0, reserved 5.3669e-05, borrowing True, slip 100, ratio 0, owed 0, raw 0.000414944)
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0xdb1d351f59cd7feade47d56854c9f47f5aec52787151ed9621275167ed5f80a2 (status 0x1, gas 28841)

### MockAggregator.setBlockTime(1792900389), two hours before the chain's time, PriceFeed.fetchPrice now reverts as stale
- `setBlockTime(uint256)` https://explorer.test.mezo.org/tx/0x0a82eaff7682ada1ee1f2a3ca41d0849c8105712165467808b67ccb19cfd222d (status 0x1, gas 45750)

### Bob's two filled requests are claimed and Bob queues a new one, with no price
- `claim(uint256[])` https://explorer.test.mezo.org/tx/0x474bc0a0c147ef67aea7a3956a30818a1d21984cb49367a884db44eb915b68d3 (status 0x1, gas 87310)
- PASS: claim works on a stale oracle, claim([2, 3]) paid Bob 53669003538280 wei (3668319718241 + 50000683820039), reserved() back to 0
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x99b8f63c74b1fca7eedc86fa76cd8aebfab06450d23635fffc58826ea8613179 (status 0x1, gas 165441)
- PASS: requestRedeem works on a stale oracle, request 4 escrowed 27261234536485130272 of Bob's shares (sized by convertToShares, which reads the vault's lastPrice)

### On the stale oracle, every entry point that prices is refused (eth_call, no transaction) and the max views read 0
- PASS: processQueue reverts on a stale oracle (reverted: execution reverted: PriceFeed: Oracle is stale.)
- PASS: rebalance reverts on a stale oracle (reverted: execution reverted: PriceFeed: Oracle is stale.)
- PASS: harvest reverts on a stale oracle, keeper or stranger (reverted: execution reverted: PriceFeed: Oracle is stale.)
- PASS: sync reverts on a stale oracle (reverted: execution reverted: PriceFeed: Oracle is stale.)
- PASS: an instant withdraw reverts on a stale oracle (reverted: execution reverted: PriceFeed: Oracle is stale.)
- PASS: maxWithdraw and maxRedeem read 0 on a stale oracle (Bob holds 1100958764788856520472 shares, maxWithdraw 0, maxRedeem 0, maxDeposit 0, all without reverting, at block 16354501)
- PASS: totalAssets and pendingProfit do not revert on the stale oracle and price at the vault's lastPrice 20000000. At block 16354506 totalAssets reads 413870469822698 and pendingProfit 124347339644. By hand at lastPrice they are 413870469822698 and 124347339644 (raw 414943568091118), at the 25M the aggregator now holds they would be 366758547763059 and 0

### setBlockTime(0) puts the oracle back on the chain time and BTC returns to 20M, then request 4 is filled and claimed the normal way
- `setBlockTime(uint256)` https://explorer.test.mezo.org/tx/0xb6629bb60416bbca36e2c78e5bb09e241321be2ccefd0399ce9c5b008eb0c2d2 (status 0x1, gas 23802)
- `setPrice(uint256)` https://explorer.test.mezo.org/tx/0x9aec5779e3563af1e376fab264dbab88d1dd2ebc8af57977a324b8f85c0bb669 (status 0x1, gas 28841)
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0x83131e2c2ac8ac535aa2558ede2ec8ab4108fd2ef4619fa8f210fb318d1e5380 (status 0x1, gas 195081)
- PASS: with a fresh price processQueue fills request 4 from idle. convertToAssets(1e24) 366844537418534827 at block 16354515, 366845608322373371 at the fill's own checkpoint, 366845608322374082 after it at block 16354516, the fill paid 366845608322344690 per 1e24 shares (10000664167155 wei for 27261234536485130272 shares). The fill moved the value per share by 711 wei, all rounding in the vault's favour. Between the two blocks it moved 1070903838544 wei, which is the change in totalAssets between them (1208215128 wei of BTC, the same for every share)
- `claim(uint256[])` https://explorer.test.mezo.org/tx/0xd29f2b47e4da9c64866b80db5fdb81557eb7893adfe8678129815a1b97234f53 (status 0x1, gas 61795)
- PASS: the first checkpoint with a fresh price, inside that processQueue, locked the pending gain, ProfitLocked(gain 124347339644, locked 1061016117146, unlockAt 1792910858), the same 124347339644 wei pendingProfit read at lastPrice while the oracle was stale
- PASS: claim([4]) paid Bob 10000664167155 wei, queue.reserved() 0 and queue.pending() 0, the queue is empty again

## S5 on v6: payouts the vault triggers itself

Staging sMUSD has pcv set, so every sMUSD deposit or withdraw first calls PCV.distributeMUSD, which pays half the MUSD the PCV holds (borrow fees and interest) to sMUSD holders. The vault holds about half of all sMUSD, so its own deposits and withdraws can pay it inside its own transaction, after that transaction's opening checkpoint.

### Bob deposits 0.0002 BTC and the keeper rebalances, the spare reopens the trove
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x1258895fc254c40f8a6e1170d355ccbf485956cec7555699062493ac97ebc03f (status 0x1, gas 127865)
- `rebalance()` https://explorer.test.mezo.org/tx/0x5c26cb7041e0de8c134a1a8dde433f40d5d81c42ca4959d5732bf2167796a699 (status 0x1, gas 872725)
- PASS: trove reopened at 2.5 (price 2e+07, active True, coll 0.00034587, debt 2766.96, held 7432.21, idle 1.81483e-05, total 0.000603938, surplus 0, supply 0.00164608, cap 6288.54, recovery False, alice 0, bob 0.000364018, status 1, rate 100, tcr 2.87836, block 16354556, stale False, recorded 0.000604943, locked 1.00493e-06, gain 0, pps 366894736713024426, queued 0, reserved 0, borrowing True, slip 100, ratio 2.5, owed 2566.96, raw 0.000604848)
- NOTE: that rebalance already triggered a payout inside its own transaction (PCV to sMUSD 1.282501385493380990 MUSD, about half of it the vault's), but the same transaction paid the 2.564391729598017982 MUSD borrow fee of the new trove, so raw ended below recorded and pendingProfit() reads 0. A payout with no fee in the same transaction is shown next

### The other borrower draws 1000 MUSD on its own trove, its 1 MUSD borrow fee goes to the PCV like every Mezo fee
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0xa3dcf4bdb2e0678fb058e09629c5363654567b88c7c25a060c7eec5e6267a5a2 (status 0x1, gas 392061)

### Bob withdraws 0.00005 BTC, more than the idle 0.0000181 BTC, so the exit repays part of the loan from savings and its own sMUSD withdraw pays out the PCV
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0xad1b0a59bb57eaaca1edb90c25f832f80953a2c5626bfef92c2d965cbc7d6e3b (status 0x1, gas 636257)
- PASS: the exit left pendingProfit above 0 (price 2e+07, active True, coll 0.000314018, debt 2512.14, held 7177.7, idle 0, total 0.000553963, surplus 0, supply 0.00150981, cap 5709.41, recovery False, alice 0, bob 0.000314018, status 1, rate 100, tcr 2.37389, block 16354575, stale False, recorded 0.000554848, locked 8.84505e-07, gain 1.50356e-08, pps 366910401988158317, queued 0, reserved 0, borrowing True, slip 100, ratio 2.5, owed 2312.14, raw 0.000554863)
- PASS: the exit left pendingProfit() at 15036146303 wei after its own transaction. Its sMUSD withdraw made the PCV pay 0.500043872923244602 MUSD to sMUSD holders after the withdraw's opening checkpoint, and the vault's 60.7468% of it is 15036146302 wei at 20M with the 1% haircut. totalAssets left it out, 603957794626216 to 553958802238862 is the 50000000000000 wei Bob took plus the lock's release

### Anyone syncs, the checkpoint locks the payout
- `sync()` https://explorer.test.mezo.org/tx/0xf8ef0366a031ef420217d2e7beb8a855b56d17f96a37ca94bde8807224e9d1e5 (status 0x1, gas 138294)
- PASS: sync locked the self-triggered payout, ProfitLocked(gain 15032836259, locked 878600787314, unlockAt 1792910870) at time 1792908012. pendingProfit 15032954475 one block before and 0 after, the gain equals raw minus recorded at the sync (554862891328316 - 554847858492057 = 15032836259). totalAssets is continuous across it, the old lock at the sync's own time (863567951055 wei left) gives 553984290541002, the vault reads 553984290541002 after the sync, a difference of 0 wei, and convertToAssets(1e24) reads 366924269217551178 after it against 366924269217551178 from the old lock, so the payout reaches the share price only through the unlock
- NOTE: the first version of this check compared convertToAssets(1e24) with the block before and allowed 1e-8, less than one block of the standing lock's release (910296505 wei of totalAssets), an error in the check, not in the vault
- PASS: harvest's second checkpoint locks a self-triggered payout in the same transaction, shown in S2 where the harvest's sMUSD withdraw paid the vault 2157696 wei through the PCV and ProfitLocked(gain 4538254150) included it

## Cleanup after the v6 phases

### The other borrower repays the 1000 MUSD it drew for S5, an arbitrageur pulls the pool to the oracle
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xdb381a43ede538b0feca9d3ad0ba871629d1f26846034a25a5fbcc35fa67aeaf (status 0x1, gas 29306)
- `adjustTrove(uint256,uint256,bool,address,address)` https://explorer.test.mezo.org/tx/0x10e4271e577c30284c3f8ff75c8e240da4f6be48d9ab74fdb06fb61dd0cf9922 (status 0x1, gas 350321)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0xf92834cf0aad5b0b89baaea34e950e5d25fd7b995df448e0256ceba1c7bef4b0 (status 0x1, gas 46418)
- `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)` https://explorer.test.mezo.org/tx/0x180f57cd2a4ca81c6036e8b74ca2f0ebdefbd9d7595e5e59223e088c0159f92f (status 0x1, gas 236961)
- PASS: state left on staging, v6 trove open at 2.5, the deployer trove open, oracle fresh at 20M, queue empty (price 2e+07, active True, coll 0.000314018, debt 2512.14, held 7177.7, idle 0, total 0.000554042, surplus 0, supply 0.00150981, cap 5709.41, recovery False, alice 0, bob 0.000314018, status 1, rate 100, tcr 2.89905, block 16354637, stale False, recorded 0.000554863, locked 8.20499e-07, gain 0, pps 366962752327028552, queued 0, reserved 0, borrowing True, slip 100, ratio 2.5, owed 2312.14, raw 0.000554863)

### State left on staging
- BTC at 20M (it read 10M before this run), MockAggregator back on the chain time after setBlockTime(0), fetchPrice fresh
- two troves, TCR 2.899. The deployer's trove is open at 339.8% (0.000341218 BTC, 2008.21 MUSD) and the v6 trove at 2.5 (0.000314018 BTC, 2512.14 MUSD)
- the v2 MUSD/BTC pool sits at the oracle with 4000.2 MUSD and 0.00020001 BTC, and the deployer holds its LP
- v6 holds Bob's 1509805529414416195249 shares (about 0.000554 BTC), about 4865 MUSD above the loan waits for harvests, the queue is empty, borrowing is on
- deployments/staging-vault.env now points at v6, the v5 pointer is kept in deployments/staging-vault-v5.env
