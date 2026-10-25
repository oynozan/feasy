# Mezo testnet run 2 (final Wave 1 deployment)

- Vault deployed https://explorer.test.mezo.org/address/0x29CE356E4ea91b1986402AA2311d17d7e2178B78 tx https://explorer.test.mezo.org/tx/0xd51c6656677520fd20520c36432a03b1f69f089d25d18a9b918574666206641a

### Top up Alice and Bob from the deployer to their deposit plus a little gas

### Testnet params, 4% slippage because the testnet pool sits ~2.6% under the oracle
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0xf80f7d20ed3ecaf945601a5c65addd9fcf051cedf63904f76fe6f355425d5e2d (status 0x1, gas 46484)

### Alice deposits 0.06 BTC as native BTC
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xbcb1c774b688bf747d170a8423671549bc22e38f002700dfcb08bae497abea6f (status 0x1)

### Bob deposits 0.03 BTC through the ERC-20 path
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x5347341a6f164e33ebebc63109b6073f2225a6e12eb4d373c514eab038fde4a5 (status 0x1, gas 25540)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x37ec3c1967bcbebced3553c96ba4aface452efa602a95e17d6eea94ae60354b5 (status 0x1, gas 135069)

### Bob calls rebalance, anyone can, it opens the trove and buys back the fee
- `rebalance()` https://explorer.test.mezo.org/tx/0x091a099feb42e0283a535d8313df10ae11fdf8311604fbcc44da029b1a41109d (status 0x1, gas 1445728)
price        80629.963350000000000000 USD/BTC
idle BTC     0.002632559475717158 (BTC token view 0.002632559475717158)
trove        active=true coll=0.087300000000000000 debt=2815.598320181999999999
ratio        2.5
savings      2618.289831968525552463 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.089964605271197040 BTC
share price  0.999606725236 BTC per 1e18 shares
ALICE        0.059976403567738295 BTC, max withdraw 0.059955039650478105
BOB        0.029988201934781020 BTC, max withdraw 0.029977519825239052

### Push protocol fees into sMUSD (PCV was drained by run 1, so this payout is small)
- `distributeMUSD()` https://explorer.test.mezo.org/tx/0x0d06db83fbb8ada18f3823002884129eba255bce206136966e89e71b295763a8 (status 0x1, gas 109126)
vault savings after payout: 2618.446729271677023869 MUSD

### Bob redeems his max, the loan shrinks and stays open
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xdcc698c1f0dc5bb917205b07010d3de1e94fd42763849150f3e87f375758cb0d (status 0x1, gas 924727)
price        80663.494940000000000000 USD/BTC
idle BTC     0.000000000000000000 (BTC token view 0.000000000000000000)
trove        active=true coll=0.059955339293830213 debt=2000.000000000000000000
ratio        2.4181
savings      1802.848351094883733368 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.059989238349491735 BTC
share price  0.999627316964 BTC per 1e18 shares
ALICE        0.059977639004121626 BTC, max withdraw 0.059943746516790993
BOB        0.000011599330682669 BTC, max withdraw 0.000011592777039219

## Proof run on the final contract

### Keeper harvests the MUSD above the cushion (real harvest on the final contract)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x0f082d52ca4768761719874c9c41f3416da04869b104d65adfe287c473e77db2 (status 0x1, gas 403755)
price        80575.932920000000000000 USD/BTC
idle BTC     0.000013298016848855 (BTC token view 0.000013298016848855)
trove        active=true coll=0.059955339293830213 debt=2000.001564156132696212
ratio        2.4155
savings      1801.801565720288828908 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.059990083211690035 BTC
share price  0.999641395278 BTC per 1e18 shares
ALICE        0.059978483872236443 BTC, max withdraw 0.059957041962376868
BOB        0.000011599495037732 BTC, max withdraw 0.000011595348302199

### Alice, the last real holder, redeems her max, which closes the trove without a swap
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc4ca18a846c1159d493dcf20f9b4dedb0a7bdc54e9217135a2a14f6f27fbad73 (status 0x1, gas 494061)
price        80574.174810000000000000 USD/BTC
idle BTC     0.000012194984834707 (BTC token view 0.000012194984834707)
trove        active=false coll=0.000000000000000000 debt=0.000000000000000000
savings      1.799988254885959835 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.000033640922429044 BTC
share price  0.999641395888 BTC per 1e18 shares
ALICE        0.000022041436116401 BTC, max withdraw 0.000007990116012280
BOB        0.000011599499604876 BTC, max withdraw 0.000004204868822426

### Bob, not the keeper, harvests the leftover MUSD (open to anyone once the trove is closed)
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x885ca0ed280769686d3a42fc1dc44539ebc404c6328cae90bd08275e2066851c (status 0x1, gas 302403)

### Both redeem the rest, the vault empties
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x9333a39f1bf012c08ad6471c6d492b1ece28a1534c03b73b273c34d206f1c3f2 (status 0x1, gas 117553)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x74931ba8581f20a94914e775d9a524dc1887ae75069fab16be8c2631450f654e (status 0x1, gas 117541)
price        80564.534590000000000000 USD/BTC
idle BTC     0.000000000350614426 (BTC token view 0.000000000350614426)
trove        active=false coll=0.000000000000000000 debt=0.000000000000000000
savings      0.000000000000000000 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.000000000350614426 BTC
share price  1.041852211289 BTC per 1e18 shares
ALICE        0.000000000229721477 BTC, max withdraw 0.000000000229721477
BOB        0.000000000120892948 BTC, max withdraw 0.000000000120892948
DEPLOYER 0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1 BTC=0.009599997246075694 MUSD=0.000000000000000000
ALICE 0xCea69E8C9fe8307a166F6165a9c591C3e74c780D BTC=0.060527124656544354 MUSD=0.000000000000000000
BOB 0xD323eAB315D1AE6C73A6Fe25a2854CB3DcD8B9f5 BTC=0.030362908570979033 MUSD=0.000000000000000000

## v5, the final contract

Staging found three things the v2 contract got wrong when Mezo refuses an operation, see deployments/staging-log.md. v5 fixes them and is deployed here with the same constructor arguments.

- Vault deployed https://explorer.test.mezo.org/address/0x2964612e8976b4003083E6014cA39f5fD7b41f3A tx https://explorer.test.mezo.org/tx/0xdb19a9a34c1b2ae9ebc1c98c8cabb93d1e5060071248889e683300d003b7b757
- Vault v5 https://explorer.test.mezo.org/address/0x2964612e8976b4003083E6014cA39f5fD7b41f3A, Sourcify exact match https://repo.sourcify.dev/31611/0x2964612e8976b4003083E6014cA39f5fD7b41f3A, Blockscout submission accepted
- Runtime bytecode is byte for byte the staging v5 that ran the proof phases and the local build, outside the 2976 immutable bytes

### Top up Alice and Bob from the deployer
- fund ALICE 0.015728 BTC https://explorer.test.mezo.org/tx/0x150f08829d6c682bcbe2b037d2cb23818374e8eebcb8c21979f881c64a4640f4
- fund BOB 0.003827 BTC https://explorer.test.mezo.org/tx/0xf39bfd87f1d26afb81bdfe3f2ba8dec8ca545af0f069ab42182001119f7caadc

### Params for the open, the wallets hold 0.07 BTC so maxCR sits at 2.6 until the trove is open, slippage 4% because the testnet pool sits 2.2% under the oracle
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0x38b870c38695d67f5fa044e53a46e221b074df388e18c6d1f3b17e7432eb29f0 (status 0x1, gas 49284)

### Alice deposits 0.04 BTC native, Bob 0.03 BTC through ERC-20, Bob opens the trove
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x20330c9e4c05686277ffcafa46c23f62446655cb4b3d4bcf819c1cd5b164bc01 (status 0x1, gas 163822)
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x97175f373520ed12b8a48bc44f2f223d388cbc2cf08b16deab5101d1df21abf3 (status 0x1, gas 25528)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x2d66d6ef859bdfa4ef5a6c6069d98f0714c6292282c8a3edc7d4bc9a8eeb16da (status 0x1, gas 135069)
- `rebalance()` https://explorer.test.mezo.org/tx/0xf9e4c5ce807fd2f4bb4f7ad27811550c3595eff138a0b4d28ee135fb672be085 (status 0x1, gas 1445802)
price        80448.004220000000000000 USD/BTC
idle BTC     0.002048703877136438 (BTC token view 0.002048703877136438)
trove        active=true coll=0.067900000000000000 debt=2184.967794615199999999
ratio        2.5
savings      1987.019477822623968587 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.069973186945148358 BTC
share price  0.999616956359 BTC per 1e18 shares
ALICE        0.039984678235806739 BTC, max withdraw 0.039970687929792250
BOB        0.029988508656228111 BTC, max withdraw 0.029978015947344187

### Push protocol fees into sMUSD, then harvest anything above the cushion
- `distributeMUSD()` https://explorer.test.mezo.org/tx/0xe7fe74cb748486abb8eab9cc6a00e9db3f61fbf779c8f6a0136992c71655a1da (status 0x1, gas 109126)
- savings value 1987.019477822623968587 to 1988.315785575699277786 MUSD
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0xba102af22c2668f52bc57bf6f5062bcf00518c1c81ea30c7cfc966ad3e96f455 (status 0x1, gas 349832)

### Bob withdraws 0.005 BTC, collateral is released and the loan repaid from savings
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x5ee373ebeed5967920075b9d6514f04093f34da6801dc3e5898797b986dc9fd9 (status 0x1, gas 565825)
price        80441.156590000000000000 USD/BTC
idle BTC     0.000000000000000000 (BTC token view 0.000000000000000000)
trove        active=true coll=0.064966018931761802 debt=2090.376686066814257111
ratio        2.5
savings      1892.361645819565692634 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.064989708215453454 BTC
share price  0.999852974874 BTC per 1e18 shares
ALICE        0.039994118960921559 BTC, max withdraw 0.039979540809339276
BOB        0.024995589249247346 BTC, max withdraw 0.024986478122422525

### Default band restored, the trove sits at target inside it
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0xbed5915c2e9658769c7534ca4e41b5929da3c886dfa6656b04419e9903bb5886 (status 0x1, gas 46484)
price        80439.758370000000000000 USD/BTC
idle BTC     0.000000000000000000 (BTC token view 0.000000000000000000)
trove        active=true coll=0.064966018931761802 debt=2090.376697990266260275
ratio        2.5
savings      1892.361645819565692634 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.064989708086910210 BTC
share price  0.999852972897 BTC per 1e18 shares
ALICE        0.039994118910325867 BTC, max withdraw 0.039979540809339276
BOB        0.024995589167571968 BTC, max withdraw 0.024986478122422525

### Mezo Passport test, a Unisat wallet through Passport
- Funded the Passport account 0xee1Feb8dCeFb26E31229B17CB6758C2b2F2f642c with 0.002 BTC https://explorer.test.mezo.org/tx/0xe6b3e26725260e0a30dd9be38b5bf440480af5dc9acec212559695f35f4b93b9

### The keeper moves to its own key, so the owner key no longer signs routine upkeep
- `setKeeper(address)` https://explorer.test.mezo.org/tx/0x34e3409180fb33728f2246b5c1415bb122be044f5867786630a7a28404e3345a (status 0x1, gas 30137)
- fund KEEPER 0.0005 BTC https://explorer.test.mezo.org/tx/0x64100736f991c751a23680ad53b2261cafb577f7e55434c7ad19e4d09d147143
- Deposit 0.0002 BTC from the Passport account (OrangeKit Safe of a Unisat wallet) https://explorer.test.mezo.org/tx/0x6fe214186c7299e2bf17fcc0612372aadc261247487ee2fc189af746ff873ba5
- Withdraw 0.00005 BTC back to the Passport account, signed in Unisat https://explorer.test.mezo.org/tx/0x2c3f36588879bd10b614fcebe46fed4828411a100b29f5a5dee44ba7d922b113 (status 0x1)

### Vault ownership moves to a 24 hour timelock
- TimelockController (OpenZeppelin 5.7) deployed https://explorer.test.mezo.org/address/0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B tx https://explorer.test.mezo.org/tx/0x673145a2aef4b3b0e9cd6550c56cd3aa8f17a130e0122d083721c05c397c1f50, proposer the deployer, anyone can execute, no admin
- `transferOwnership(address)` https://explorer.test.mezo.org/tx/0xa10b6fc5c7f31ba1dffacc91df15d5432e003179254d782cc2ee8af541ee75ab (status 0x1, gas 47829)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0xf9e622a16a7c4ea675b36c2537fb10899ffc449cc9ea8a74ccc44dd234dd89ef (status 0x1, gas 56200)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0x6012157e7820a8ffb62ae24bafd6fc9a2faa977966b12ed8e09a64c3e2ac445f (status 0x1, gas 45325)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x1e930f9ccc917a3621b7b1d587754e5f178031d9a67ee31eb449126c04e9f6c0 (status 0x1, gas 56650)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0xf0a26a35900b065dea8596fb3f9451954e942b8f5609eb9368547b138b48190b (status 0x1, gas 59759)
- Handover done: the vault owner is the timelock, nothing is pending, minDelay is 86400 s (24 h), the keeper is unchanged. Timelock source is verified on Sourcify, exact match https://repo.sourcify.dev/31611/0xf95A492c30666Ab42819b5bEc0e37cdbA3236C5B. Owner calls now go through scripts/timelock.sh
- `transfer to 0xC05D15b74943e9Ed14001f26D7F4b7db3EeA5a23` https://explorer.test.mezo.org/tx/0xe150431183b4d230c55c0786acd1ab03b6d16cc0e0947d1caa27f79dfe625427 (status 0x1, gas 21000)
- `transfer to 0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE` https://explorer.test.mezo.org/tx/0x5a821447fb10bca03f950a22043f75ecde012b5e945c8da5bace86503d6698b8 (status 0x1, gas 21000)

## Vault v6, with the 7-day profit unlock, the guardian and the withdrawal queue

### Guardian wallet, kept in .env only
- GUARDIAN 0x6CC622e02846f98dCD5a0b33FC35D0F751C7f6dE, funded above with dust for gas

### Deploy, owner DEPLOYER, keeper KEEPER, guardian GUARDIAN, unlock 7 days, borrowing off
- Vault deployed https://explorer.test.mezo.org/address/0xb7A15aB24483Dfe92056F73279ECF11CE00675db (queue 0x4e580155d4d7957874cA88803646141E98f90cb6, block 16353457) tx https://explorer.test.mezo.org/tx/0xfd2ad943617c7ea7cbda29f8d88f7de5a48f3cf603766e2a2a0a69860210477d
- Sourcify exact match for the vault https://repo.sourcify.dev/31611/0xb7A15aB24483Dfe92056F73279ECF11CE00675db and the queue https://repo.sourcify.dev/31611/0x4e580155d4d7957874cA88803646141E98f90cb6

### Alice moves from v5, then a rebalance on v6 with borrowing off
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x6388b31d59fdf2bb6c413f47629596b8f4ce9db2568a59be4c54d59ffaaf4f31 (status 0x1, gas 519168)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x9435aef0cdfe4f089112af233747337c0e455d0a372b1154543b958e850746ba (status 0x1, gas 208624)
- `rebalance()` https://explorer.test.mezo.org/tx/0x5c3de872bd8745f1c2fc4126307731329660ee264c02d4a52b59fee468e811d7 (status 0x1, gas 182470)

### Role matrix, plain eth_call from each role address
- PASS `setBorrowingEnabled(bool)` from guardian gives OwnableUnauthorizedAccount
- PASS `setGuardian(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `setKeeper(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` from guardian gives OwnableUnauthorizedAccount
- PASS `transferOwnership(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `renounceOwnership()` from guardian gives OwnableUnauthorizedAccount
- PASS `pauseBorrowing()` from keeper gives NotGuardian
- PASS `unwind()` from keeper gives NotGuardian
- PASS `pauseBorrowing()` from stranger gives NotGuardian
- PASS `unwind()` from stranger gives NotGuardian
- PASS `pauseBorrowing()` from guardian gives ok
- PASS `unwind()` from guardian gives ok
- PASS `pauseBorrowing()` from owner gives ok
- PASS `escrow(address,address,uint256)` from stranger gives NotQueue
- PASS `fill(uint256)` from stranger gives NotVault
- PASS `sync()` from stranger gives ok
- PASS `processQueue(uint256)` from stranger gives ok

### Real transactions on the borrowing flag, guardian pause, owner enable, guardian unwind with no trove
- `pauseBorrowing()` https://explorer.test.mezo.org/tx/0xbd55ecd06375e50087728bd61a294e2b7bedb56da5aa3a4ad85178ad725595f7 (status 0x1, gas 27064)
- `setBorrowingEnabled(bool)` https://explorer.test.mezo.org/tx/0xe32add9f2c596e45e925d33d603af576fd19223864332090b26b79ff68a74071 (status 0x1, gas 48172)
- `unwind()` https://explorer.test.mezo.org/tx/0xb480dcd1d43986511a201bfe49e200a03098bb01f1b6d7c7372612e3bd20286d (status 0x1, gas 38842)

### Withdrawal queue with real transactions, Alice requests 0.004 BTC, the keeper fills and claims
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xbb2816841c80658e6e8190bea62c5a6370043b97cc24fc80b68c5a1cfca13c26 (status 0x1, gas 199617)
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0x8dce1c29e9874f5106c0b3bc76dea51a35c2bce18b05b9feb8f13a373109c919 (status 0x1, gas 205189)
- `claim(uint256[])` https://explorer.test.mezo.org/tx/0xeb14441b50410ca617c45d9406aa2f5a772b51755170f4b9504beba7ddb1d935 (status 0x1, gas 53542)

### Bob moves from v5, which closes the v5 trove
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xd3f79344f75d0b393bae0b8c1587c1ed3cf421af46dac0de9777f6d708ee797d (status 0x1, gas 119233)

### Deposits into v6, band 2.0 / 2.5 / 2.8 because the wallets hold 0.073 BTC, slippage 4%, borrowing on, the keeper opens the trove
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x6c59c072b860bd96f809079d0e27f3aefc3d390ade87bb851ab35ed07be09257 (status 0x1, gas 123001)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xde0bf40499fceb87676a93a5f1532f910ceadaf97aebb6917c69b4fca7a3ee95 (status 0x1, gas 140101)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x29d56eaab428a7485d85ef1d04dc45b1817de3623c8125851215da3ca712a2a3 (status 0x1, gas 140101)
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0xe08739577bc1210df27acf3deac192b05aec028e88f75c90f6d3c6e67927784c (status 0x1, gas 49858)
- `setBorrowingEnabled(bool)` https://explorer.test.mezo.org/tx/0x8c02632ed9d90a4e2d6790787b6be939f3dca71f9d36151013fcf5c353b9c85e (status 0x1, gas 48172)
- `rebalance()` https://explorer.test.mezo.org/tx/0xc342c4cbb21a1a8c8f287481286e5a693b1c930dbc5c518a77e16b181e303d5e (status 0x1, gas 1406670)

### Queue fill through the trove, Bob requests 0.005 BTC against 0.0021 idle
- `requestRedeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x3f9f246eab0b6ec966c2af99d2a3d5c3761d7cf86d3b8bab83f8e03982372245 (status 0x1, gas 182553)
- `processQueue(uint256)` https://explorer.test.mezo.org/tx/0x905ad114de120f2c1e76972cd4b48ba9347ca0992f112552803e50b9c6ccc58e (status 0x1, gas 618211)
- `claim(uint256[])` https://explorer.test.mezo.org/tx/0x3f86370ee13ffde7bfca90222fd21ad173b2c0af2275efeff1fd786ce0d04026 (status 0x1, gas 58283)

### Profit unlock on the live vault, a 0.0001 BTC donation, then sync
- `transfer(address,uint256)` https://explorer.test.mezo.org/tx/0x264f3ecf14c14cb321c78e4e441bca5a9353fb44988e1a2198faaaf9fd84baf4 (status 0x1, gas 25540)
- `sync()` https://explorer.test.mezo.org/tx/0xdb1818250dc6412eaa412ab6cf67857ccd3474e2745d50068df1704a7fed380f (status 0x1, gas 133485)

### Short unlock copy, the same code with a 1 hour unlock period to measure the release
- Vault deployed https://explorer.test.mezo.org/address/0x58c91F038a7d8aaD87FEF5e3c508ab4695FeD317 (queue 0x82B75a4D3E672c73c0dBb3bcd3F457c4Fa0F05f9, block 16353590) tx https://explorer.test.mezo.org/tx/0x37556a6b94598e3b791b6cf1d1cba52f3a611f11d755c00a422bbe42aee7ce22
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xd1d851b90da9c19aac84ef5b9e0eb4c9ea7c711451324c6457aa22b9f0700693 (status 0x1, gas 208624)
- `transfer(address,uint256)` https://explorer.test.mezo.org/tx/0x322337dbc4e91d208176b0cb8b284e5d4ba776618978883ec6f1d07bb9a82c6e (status 0x1, gas 25540)
- `sync()` https://explorer.test.mezo.org/tx/0xb46611331d379815e51b0e00116f721c0ca384d7aac44d1e940a2e795632bcd8 (status 0x1, gas 108715)
- Release checked against locked x (unlockAt - t) / 3600 at the same block
- PASS block 16353610, t-lockedAt 26 s, lockedProfit 49638888888888 (formula 49638888888888), totalAssets 1000361111111112 (formula 1000361111111112)

### v6 becomes the live vault, deployments/testnet.env points at it and v5 moves to deployments/testnet-v5.env

### v6 ownership moves to the same 24 hour timelock, accept scheduled now
- `transferOwnership(address)` https://explorer.test.mezo.org/tx/0x294547412968e92d29a5c61d6ecdc8462d64757b05640ff0dd9f018fc7e0c6df (status 0x1, gas 49082)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x0953de8242df638f59cd06dd0f222d9e0e676dda5dd64f634e0c883733f320fa (status 0x1, gas 56248)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x0953de8242df638f59cd06dd0f222d9e0e676dda5dd64f634e0c883733f320fa (status 0x1, gas 56248)
executable after 2026-10-26T04:55:19Z

### v5 leftover MUSD harvested into BTC now that its trove is closed, so the remaining holders can take everything
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x2dd55e26268a282874a75f6dd656e88687f596db472dfdf48add4f3557d2844a (status 0x1, gas 302403)
- PASS block 16353755, t-lockedAt 625 s, lockedProfit 41319444444444 (formula 41319444444444), totalAssets 1008680555555556 (formula 1008680555555556)
- PASS block 16353900, t-lockedAt 1229 s, lockedProfit 32930555555555 (formula 32930555555555), totalAssets 1017069444444445 (formula 1017069444444445)

## Vault v7 test copy, v6 plus the veBTC sleeve, built in a scratch workspace until proven

### Deploy, SystemMath library 0x3381F62d1Dd09Fba28700Cb42de92A4dDF8DbB9f, vault 0xa2794AC84ec413a918D1960E6b434d562579966a, queue 0x5784726d2721B16AbFebCAB7C1B483FB11f5eCb8, sleeve 0xE69A16771a26dBde5BC79Eab31F16066fAe79311, guardian wallet as owner, keeper and guardian, 1 hour unlock
- library tx https://explorer.test.mezo.org/tx/0x3da92bd6f99477e4c5af5059b66da9c3465c66cbafb339b98f38ffa59d79e428, vault tx https://explorer.test.mezo.org/tx/0x52f8f05fbb5333423c03f55bbee27e4e5b8301ebee8a9ed29fe3da4c514290b3
- Pre-deploy checks passed, veBTC 0x38E3 and the Pools Voter 0x263F point at each other, the sMUSD gauge 0xA697 is alive, max lock 2419200 s

### Sleeve 25%, 2 week ladder, Alice moves 0.0025 BTC over from v6
- `setSleeve(uint16,uint256,uint8)` https://explorer.test.mezo.org/tx/0x281e335da5000161211e8f124d9ec5744083d718e6fb1d2a3708086093eeee8c (status 0x1, gas 37188)
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x1301a84d96dc7b73cf8d3c436cef9bf10e059bfb92a5e652430a8d5d681ad2e3 (status 0x1, gas 568468)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x4e8ff7e96dab18fc27fbb33e0d8a96c64cf742bf54bfe84b0181c7ad0647e99f (status 0x1, gas 214246)

### Keeper roll, the first two veBTC rungs, each voting 100% for the sMUSD gauge
- `roll()` https://explorer.test.mezo.org/tx/0x157e09cc12c9e594da8329e0acf1cd2983561477c86fe99074cfb7481ed748b9 (status 0x1, gas 423602)
  principal 0 totalAssets 2400000000000000 [2.4e15] idle 2400000000000000 alice maxWithdraw 2400000000000000 [2.4e15] convertToAssets 2400000000000000 [2.4e15]

### Roll found no lock, gas estimation settles where the caught lock runs out of gas (roll estimate 291669, two-rung lock alone 1986384), so v7 now requires the gas up front and the copy is redeployed
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xb3dd51b5c5c2708d2df610c7e72291a960d88e7418d40261d90bdf535ebbc7d1 (status 0x1, gas 141438)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc97a236b5a1ac6a9d37ed27347d7fbf7f2e53104564e169546d3e2a443205aff (status 0x1, gas 127014)
- Redeployed vault 0xeDb4B6AAE0DcdC5Af45Cb42cf7714807CC9a075c, queue 0xdD2C50077D393E5661772348578F52553E4a121E, sleeve 0xa30C9136aed242ba6b98A27f53bc7c5c6AA91E7d, tx https://explorer.test.mezo.org/tx/0xda18b734c8e86f4af9e37f8ee606b7fb1c7898458ec5ebbfb015b408facaf2b5, code 24392 bytes
- `setSleeve(uint16,uint256,uint8)` https://explorer.test.mezo.org/tx/0xf06504c019628c0bdf37bfa3ead083e3486dc47ee1606002634c0983973de63b (status 0x1, gas 37188)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x3f44f5541e7f213b570fc87c0133fa9a386a1b938bc3ff1b21cada02bf165d05 (status 0x1, gas 214246)

### Keeper roll on the fixed copy, the first two veBTC rungs, each voting 100% for the sMUSD gauge
- `roll()` https://explorer.test.mezo.org/tx/0x15c9792b60f4515c9a2a194bfb83a3b55f3ce99a33a198825ea9851da4e59f93 (status 0x1, gas 2166188)
- slot 1, veBTC id 1720, 0.000300000000000000 BTC, ends , owner 0xa30C9136aed242ba6b98A27f53bc7c5c6AA91E7d, voted true, votes on sMUSD 40476314318336, power 40475446262784
- slot 2, veBTC id 1719, 0.000300000000000000 BTC, ends , owner 0xa30C9136aed242ba6b98A27f53bc7c5c6AA91E7d, voted true, votes on sMUSD 115476314011136, power 115475073931776
- principal 0.000600000000000000, totalAssets 0.002400000000000000, idle 0.001800000000000000, alice maxWithdraw 0.001800000000000000 of 0.002400000000000000
- slot 1 id 1720 ends 2026-10-29 00:00:00 UTC (Thursday), veBTC locked() (300000000000000 [3e14], 1793232000 [1.793e9], false, 0)
- slot 2 id 1719 ends 2026-11-05 00:00:00 UTC (Thursday), veBTC locked() (300000000000000 [3e14], 1793836800 [1.793e9], false, 0)
- PASS block 16354045, t-lockedAt 1833 s, lockedProfit 24541666666666 (formula 24541666666666), totalAssets 1025458333333334 (formula 1025458333333334)
- PASS block 16354189, t-lockedAt 2430 s, lockedProfit 16250000000000 (formula 16250000000000), totalAssets 1033750000000000 (formula 1033750000000000)
- PASS block 16354335, t-lockedAt 3038 s, lockedProfit 7805555555555 (formula 7805555555555), totalAssets 1042194444444445 (formula 1042194444444445)
- PASS block 16354479, t-lockedAt 3639 s, lockedProfit 0 (formula 0), totalAssets 1050000000000000 (formula 1050000000000000)
- PASS block 16354624, t-lockedAt 4239 s, lockedProfit 0 (formula 0), totalAssets 1050000000000000 (formula 1050000000000000)
- Result: 8 of 8 readings matched the release formula to the wei, from 26 s to 4,239 s after the lock, and totalAssets settled at exactly the 0.00105 BTC raw once the hour was over

### Review fixes, a third copy with the fixed sleeve and liquid rule, the second copy keeps its two rungs until they mature
- `withdraw(uint256,address,address)` https://explorer.test.mezo.org/tx/0x91be16f8fcdddd662d865ad3a05ae52b88cb7520b605668b29f4a75c0489f519 (status 0x1, gas 141774)
- Vault 0x8E1cB817CFd049969e71B1F5325eC2E54a4DC6a8, queue 0x8c4be3e96653E1320E0a6F636aB0B2854a146667, sleeve 0x439102c27A1313544cd386E1A28A2e97E80a89Ae, tx https://explorer.test.mezo.org/tx/0xcc48837f12ef466ccd31323b4553bed70f8e8898ee6d7fb95a128ed9c47f9f7f, vault code 24476 B, sleeve code 8055 B, sleeve.bribe 0x7D95237854f8Fa8F36c1280860E03736d0150BB1, liveAtRoll true, live true
- `setSleeve(uint16,uint256,uint8)` https://explorer.test.mezo.org/tx/0xadbe42ad8653f881ab4cf9b047eb2d03dc4308537d5289fd6a0c9d565989cfd1 (status 0x1, gas 37223)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x1d63b1ac50afcd3cebbbb54eaef8281237e2481d2f93ddd67cf8de5c284ec9bd (status 0x1, gas 214298)
- `roll()` https://explorer.test.mezo.org/tx/0x5cd10b99f5fe068a71335d3822382fea78d61c65048cd7425a0832a48cc4915a (status 0x1, gas 2502219)
- slot 1, veBTC id 1722, 0.000250000000000000 BTC, ends 2026-10-29 00:00 UTC (Thu), owner 0x439102c27A1313544cd386E1A28A2e97E80a89Ae, votes on sMUSD 33216352484316
- slot 2, veBTC id 1721, 0.000250000000000000 BTC, ends 2026-11-05 00:00 UTC (Thu), owner 0x439102c27A1313544cd386E1A28A2e97E80a89Ae, votes on sMUSD 95716352429916
- principal 0.000500000000000000, totalAssets 0.002000000000000000, rawAssets 0.002000000000000000, alice maxWithdraw 0.001500000000000000

### v6 gets its own timelock instead of waiting a day, deployed at zero delay, accept and the 24 hour delay run at once as in the v5 handover
- TimelockController (OpenZeppelin 5.7) 0x2A4327156Cd2f4472282D1A636b424a86324803E tx https://explorer.test.mezo.org/tx/, proposer the deployer, anyone can execute, no admin
- `transferOwnership(address)` https://explorer.test.mezo.org/tx/0x2c38f69c671ef32d6a42815af7a84003d2806646d2f310f94dfeec9d939bb1d4 (status 0x1, gas 31982)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x30d69f7fe3478c0a3aaa215871e2044a1ba194ec0682914273a76dc45921fc64 (status 0x1, gas 55552)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0x63f8891914f147181d526aec42549346a4ac368c1cb74eef210de8291f22e0e4 (status 0x1, gas 45326)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0xa33b203038cacafafa45b4947af6e2470bf44a1b36baaec04027cef0c0bb935e (status 0x1, gas 55990)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0xc595b448ea000f0545269b56beb9cccc3a27802093ace87ce4bae4139e87a504 (status 0x1, gas 59252)
- `cancel(bytes32)` https://explorer.test.mezo.org/tx/0x1f6aa1a69edf700d3edc6495fb1935b772f3597b67fc86f4282646c3b1e64357 (status 0x1, gas 25951)
- Handover done in minutes: v6's owner is 0x2A4327156Cd2f4472282D1A636b424a86324803E, minDelay 86400 s (24 h), nothing pending. The old timelock's scheduled accept for v6 is cancelled. Owner calls go through scripts/timelock.sh

## Vault v7, v6 plus the veBTC sleeve, deployed from the repo

### Deploy, SystemMath linked into the vault, which creates its queue and sleeve
- Vault deployed https://explorer.test.mezo.org/address/0x4DA2eb6942cF136126A630e4C968CE43474c0Db6 (queue 0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3, sleeve 0xee76C202a9e43988c55DC86816a6c14211Db209B, SystemMath 0x34df486c93DB9a2A263498df97BDDF04BF1d57f7, block 16356409) tx https://explorer.test.mezo.org/tx/0x46e0e7956df592aefaa8e6ebf961ffd1b49ed7cb94c377fa7924086a3f2bb21d
- Sourcify exact match for all four, SystemMath 0x34df486c93DB9a2A263498df97BDDF04BF1d57f7, vault 0x4DA2eb6942cF136126A630e4C968CE43474c0Db6, queue 0xB4D13C2A94f9bd165CF77eC5C92D174C51ff13C3 and sleeve 0xee76C202a9e43988c55DC86816a6c14211Db209B. The queue and the sleeve needed `--libraries` too, since linking writes the library into every contract's compiler settings

### Role matrix, plain eth_call from each role address, the 17 v6 checks plus 17 on the sleeve
- PASS `setBorrowingEnabled(bool)` from guardian gives OwnableUnauthorizedAccount
- PASS `setGuardian(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `setKeeper(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` from guardian gives OwnableUnauthorizedAccount
- PASS `transferOwnership(address)` from guardian gives OwnableUnauthorizedAccount
- PASS `renounceOwnership()` from guardian gives OwnableUnauthorizedAccount
- PASS `pauseBorrowing()` from keeper gives NotGuardian
- PASS `unwind()` from keeper gives NotGuardian
- PASS `pauseBorrowing()` from stranger gives NotGuardian
- PASS `unwind()` from stranger gives NotGuardian
- PASS `pauseBorrowing()` from guardian gives ok
- PASS `unwind()` from guardian gives ok
- PASS `pauseBorrowing()` from owner gives ok
- PASS `escrow(address,address,uint256)` from stranger gives NotQueue
- PASS `fill(uint256)` from stranger gives NotVault
- PASS `sync()` from stranger gives ok
- PASS `processQueue(uint256)` from stranger gives ok
- PASS `setSleeve(uint16,uint256,uint8)` from guardian gives NotAllowed
- PASS `setSleeve(uint16,uint256,uint8)` from keeper gives NotAllowed
- PASS `setSleeve(uint16,uint256,uint8)` from stranger gives NotAllowed
- PASS `setSleeve(uint16,uint256,uint8)` from owner gives ok
- PASS `setSleeve(uint16,uint256,uint8)` from owner gives BadSleeve
- PASS `setSleeve(uint16,uint256,uint8)` from owner gives BadSleeve
- PASS `setPaused(bool)` from guardian gives ok
- PASS `setPaused(bool)` from keeper gives ok
- PASS `setPaused(bool)` from stranger gives NotAllowed
- PASS `setPaused(bool)` from guardian gives NotAllowed
- PASS `setPaused(bool)` from keeper gives NotAllowed
- PASS `setPaused(bool)` from owner gives ok
- PASS `collect()` from stranger gives NotVault
- PASS `lock(uint256)` from stranger gives NotVault
- PASS `tend(uint256)` from stranger gives NotVault
- PASS `release(uint256)` from stranger gives NotVault
- PASS `roll()` from stranger gives ok
- 34 PASS, 0 FAIL

### The move from v6, step 1, the guardian unwinds v6 so every exit leaves as plain BTC
- `unwind()` https://explorer.test.mezo.org/tx/0x448f257eda14c4104bdd5a785a47b44e27c16a5f22db2308ab588d05760c373e (status 0x1, gas 426821)

### The move from v6, step 2, the 2.13 MUSD left in savings is harvested, then Alice and Bob leave in full and the deployer keeps 0.0001 BTC to collect the profit still unlocking until 2026-11-01
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0xf54f9ce0a7bbfcbb5a3b45f02393f8e9df9c4f55dbc4d72abdc354c839d0d011 (status 0x1, gas 411777)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x235ddaacf5387d2b712a63841dfaf76e1a4ea5da4128ba765d8957859d0dbc22 (status 0x1, gas 131446)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x08ba9134ca0b61d838c886e0bf53a63e2f4283f1e3bf40336a9f38ab0ef1f641 (status 0x1, gas 131446)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xc7d3055018f7ffb9aa83bc3553b870792b60f4fd27a07dacba6dabdc58128d37 (status 0x1, gas 136234)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xfad78ff01db64ed699e2d007f42b260d5798c7c10351ca8af3bca975dc34d6bc (status 0x1, gas 112724)

### The move from v6, step 3, Alice, Bob and the deployer deposit into v7, each keeping a little BTC for gas
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0xf04a13f3aff40398790d589a18da51a40ff82b7aa860f62c6762dd7532fd4129 (status 0x1, gas 214298)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x7b818e83c5cdee60cd7b50abfd2b5b47373b68f1d8686acb86e19c2833eddcee (status 0x1, gas 145775)
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x9d2e5a8c2575f9e701275596c0db071f66266fafdddff08e657e7161e475cc71 (status 0x1, gas 142975)

### The move from v6, step 4, band 2.0 / 2.2 / 2.4 and buffer 2% because the wallets hold 0.069 BTC, a 5% sleeve on a 4 week ladder, borrowing on, the keeper opens the trove
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0x4a1eee875f93bfcb82185d89a6a7d0b189c179bee46679241672267e41189f69 (status 0x1, gas 55490)
- `setSleeve(uint16,uint256,uint8)` https://explorer.test.mezo.org/tx/0xcb847ac03684a9d27df2230238264eba8ed8bd4d10e6722e383fdfc594c5eb9e (status 0x1, gas 37223)
- `setBorrowingEnabled(bool)` https://explorer.test.mezo.org/tx/0x39821f3c20817b5fb48d6092c55ec35177ed0465aa7a796e2e47613a15e71c11 (status 0x1, gas 48238)
- `rebalance()` https://explorer.test.mezo.org/tx/0x7b8b486b4c038dddb5c16346becd4399e10ea876ce716301e06680e4b8e46409 (status 0x1, gas 1563565)

### v7 becomes the live vault, deployments/testnet.env points at it and v6 moves to deployments/testnet-v6.env

### First roll, the keeper locks the 5% sleeve into two veBTC locks ending Thu Nov 12 and Thu Nov 19, each voting for the sMUSD gauge
- `roll()` https://explorer.test.mezo.org/tx/0x293f89eb53b0b50638ea8a833a18f0436484cbcc805092af1ec4860b9274d1cc (status 0x1, gas 2526475)
- veBTC 1724 holds 0.001694 BTC until 2026-11-19 and veBTC 1725 0.001694 BTC until 2026-11-12, both owned by the sleeve and voting all their power for the sMUSD gauge. totalAssets is unchanged by the lock, and idle BTC is back to the 2% buffer

### v7 ownership moves to its own 24 hour timelock, deployed at zero delay so the accept and the delay run at once
- TimelockController (OpenZeppelin 5.7) 0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719 tx https://explorer.test.mezo.org/tx/0xfd398a3c5640839d8dd480e49d7f5e9c671e6ddf9c8ce4dcfff06917b0116dfe, proposer the deployer, anyone can execute, no admin
- `transferOwnership(address)` https://explorer.test.mezo.org/tx/0x6f7aff7aefbd1d06d210059d931155c291d09f3950135f622c67d5a5b1fe6ede (status 0x1, gas 49148)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x3059d8b91409e16b34c1c098194ea1d1d58325b603e0596fddb4c8acd587f010 (status 0x1, gas 55552)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0x6f67eb9dc0c5c1390e1d47673b448ef232edfba66cb7b4b748997ca2036a6c7e (status 0x1, gas 45370)
- `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` https://explorer.test.mezo.org/tx/0x5f555b028cd0caf584c56f2723c2e6c8ef53606fbe5cba59e04463c1f8adc0cc (status 0x1, gas 55990)
- `execute(address,uint256,bytes,bytes32,bytes32)` https://explorer.test.mezo.org/tx/0x3e5d28fb83a1f11c4b3faa75f553b40384579fae7147ae4d741f9101508bfc96 (status 0x1, gas 59252)
- Handover done in minutes: v7's owner is 0xad37d71330152b1bC58e7f87Eba6Ab6a1fE52719, minDelay 86400 s (24 h), nothing pending, Sourcify exact match. Owner calls go through scripts/timelock.sh, with TARGET=$SLEEVE for the sleeve
