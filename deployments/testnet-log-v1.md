# Mezo testnet run 1 (first deployment, superseded)

- Vault deployed https://explorer.test.mezo.org/address/0x375Ef9f10cf75f138D6454F5253B8cEa65038e86 tx https://explorer.test.mezo.org/tx/0x7f4a1c505285f99cf2ed409c0c8509253023e1115022f70a04b24f5ea575b394

### Fund Alice and Bob from the deployer, deposit plus a little gas
- fund ALICE 0.0602 BTC https://explorer.test.mezo.org/tx/0xff666faa9b569fe4958b929470c3d25503051dffc46edfe44eec4651e64a352c
- fund BOB 0.030199999999999998 BTC https://explorer.test.mezo.org/tx/0xccf4d1e542c0f0c42145bf9fc40858f15e44d37603baed0409e350ba108e2553

### Testnet params, 4% slippage because the testnet pool sits ~2.6% under the oracle
- `setParams(uint256,uint256,uint256,uint256,uint256,uint16,uint256)` https://explorer.test.mezo.org/tx/0x9d6f4ea4614884f68a096801de7fd29a6f07542ebaf0098b714ea1ec8ac8dd81 (status 0x1, gas 46484)

### Alice deposits 0.06 BTC as native BTC
- `depositBTC(address)` https://explorer.test.mezo.org/tx/0x3bf6ef5065efec120a435b640edba95d96a8a373579f796adc2d9b17702a3955 (status 0x1, gas 163822)

### Bob deposits 0.03 BTC through the ERC-20 path
- `approve(address,uint256)` https://explorer.test.mezo.org/tx/0x68b9fe3851093a21a74941d6855b008d00775e4e004fb70b19bf5cba2a219c2a (status 0x1, gas 25540)
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0x57cd6f58c73efbc301332f2dcddca0deb04d769fb9a5da487ed2e8de41fbac34 (status 0x0, gas 137202)

### Bob deposits 0.03 BTC through the ERC-20 path, retried with a padded gas limit
- `deposit(uint256,address)` https://explorer.test.mezo.org/tx/0xfa2370d9cec2aa7a4b2545f5ee86c6a771529050080e429ce748e90a2a80c19f (status 0x1, gas 135069)

### Bob calls rebalance, anyone can, it opens the trove and buys back the fee
- `rebalance()` https://explorer.test.mezo.org/tx/0x8edd9e9c5d277171bc21a8470aba15a313f6127c5a5dd22b8b77ade738976f80 (status 0x1, gas 1453477)
price        80705.215130000000000000 USD/BTC
idle BTC     0.002632554667378352 (BTC token view 0.002632554667378352)
trove        active=true coll=0.087300000000000000 debt=2818.226115911841213078
ratio        2.5
savings      2620.915372912642029818 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.089964543741678889 BTC
share price  0.999606041574 BTC per 1e18 shares
ALICE        0.059976362864614396 BTC, max withdraw 0.059955036444918901
BOB        0.029988181421683927 BTC, max withdraw 0.029977518222459450

### Push protocol fees into sMUSD, then the keeper harvests
- `distributeMUSD()` https://explorer.test.mezo.org/tx/0x16ed0d35679aacc37d3eefbf14123914f658629074b52089f40679181c4b29c0 (status 0x1, gas 109126)
savings after distribute: 2664.571787834490803482
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x50afcc196ae7d1d9827fa7402e993386a9cddec6666a060d6440cebaafbc7b99 (status 0x1, gas 349832)
price        80718.165000000000000000 USD/BTC
idle BTC     0.003188053584531609 (BTC token view 0.003188053584531609)
trove        active=true coll=0.087300000000000000 debt=2818.226145382831220988
ratio        2.5004
savings      2620.844371528214052208 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.090519192372657322 BTC
share price  1.005768804141 BTC per 1e18 shares
ALICE        0.060346128248438214 BTC, max withdraw 0.060325369056354406
BOB        0.030173064110057435 BTC, max withdraw 0.030162684528177203

### Rebalance moves the harvested BTC into the trove
- `rebalance()` https://explorer.test.mezo.org/tx/0x3c9c082ac7674153112a3675c83501e5598b7fe1b67a5998c8b25d4a67b0b7be (status 0x1, gas 863179)
price        80731.677740000000000000 USD/BTC
idle BTC     0.002715575617198746 (BTC token view 0.002715575617198746)
trove        active=true coll=0.087772477967332863 debt=2818.226171281580015817
ratio        2.5144
savings      2620.844371528214052208 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.090519187188840410 BTC
share price  1.005768746543 BTC per 1e18 shares
ALICE        0.060346124792560273 BTC, max withdraw 0.060325369056354406
BOB        0.030173062561869058 BTC, max withdraw 0.030162684528177203

### Bob redeems his max, the loan shrinks and stays open
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x9696fe25f8dd35762c7df4e657fa126f4a86542b66499332ebe81b10e297cd4d (status 0x0, gas 667362)

### Bob redeems his max (retried with 0.001% room), the loan shrinks to the minimum and stays open
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x75ea6ff92f61e5312c6db6c613bf9c6fd85d06133fabeb6d9261cbb2331b3e64 (status 0x0, gas 1318723)

### Bob redeems his max with a 3x gas pad (estimates swing with the block-seeded hint)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x252f0dbb35cecb74f0644ab3f9c13481d8a1c0dc1e2485fa0215912448540e73 (status 0x1, gas 1795146)
price        80703.906460000000000000 USD/BTC
idle BTC     0.000000000000000000 (BTC token view 0.000000000000000000)
trove        active=true coll=0.060325670693819179 debt=2000.000000000000000000
ratio        2.4343
savings      1802.618047533322177226 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.060356813428231611 BTC
share price  1.005768848999 BTC per 1e18 shares
ALICE        0.060346130898069395 BTC, max withdraw 0.060314993717457462
BOB        0.000010682488273778 BTC, max withdraw 0.000010676976361716

### Alice redeems her max, which closes the trove
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xad45d9f4856be3bcc6afaf38181aba32169c35ea7b6d2a3207ad08bf73332b66 (status 0x1, gas 874188)
price        80729.375320000000000000 USD/BTC
idle BTC     0.000011280183002831 (BTC token view 0.000011280183002831)
trove        active=false coll=0.000000000000000000 debt=0.000000000000000000
savings      2.618010140610739189 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.000042412599303922 BTC
share price  1.005771842953 BTC per 1e18 shares
ALICE        0.000031729830551394 BTC, max withdraw 0.000008439027699490
BOB        0.000010682436360605 BTC, max withdraw 0.000002841155303340

### With the trove closed, the leftover MUSD is sold and both redeem the rest
- `harvest(uint256)` https://explorer.test.mezo.org/tx/0x1596ce0773eb2603271a845a5abe398557e69d375ed79bff798345042feafed3 (status 0x1, gas 361338)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0xafc01269d3a80bd36bedf9ae257ceacea8e4b31e7212980b1e05fa494f8c3517 (status 0x1, gas 122472)
- `redeem(uint256,address,address)` https://explorer.test.mezo.org/tx/0x8cc1fa31363df09305317173b454dbad4b628e659f56dfd4da04b8fd9501295f (status 0x1, gas 119684)
price        80741.780000000000000000 USD/BTC
idle BTC     0.000000000445385199 (BTC token view 0.000000000445385199)
trove        active=false coll=0.000000000000000000 debt=0.000000000000000000
savings      0.000000000000000000 MUSD, idle MUSD 0.000000000000000000
totalAssets  0.000000000445385199 BTC
share price  1.056185897054 BTC per 1e18 shares
ALICE        0.000000000333205412 BTC, max withdraw 0.000000000333205412
BOB        0.000000000112179786 BTC, max withdraw 0.000000000112179786
DEPLOYER 0x90fE1214B5b762D72549639ed711EC6F58Bf5aF1 BTC=0.009599998885328070 MUSD=0.000000000000000000
ALICE 0xCea69E8C9fe8307a166F6165a9c591C3e74c780D BTC=0.060547710549812476 MUSD=0.000000000000000000
BOB 0xD323eAB315D1AE6C73A6Fe25a2854CB3DcD8B9f5 BTC=0.030373599621954642 MUSD=0.000000000000000000
