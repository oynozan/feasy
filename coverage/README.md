# Coverage suite

Local Foundry tests for the v8 contracts in `contracts/src`. Run from the repo root:

```sh
git submodule update --init --recursive
forge coverage --ir-minimum --no-match-coverage "(staging|coverage|contracts/lib)"
```

The vault only compiles through the IR pipeline, so coverage needs `--ir-minimum`.

Every contract around the vault is Mezo's own code, deployed and wired the way
`staging/script/DeployStaging.s.sol` deploys it on Mezo testnet:

- MUSD from mezo-org/musd, using the repo's own test hooks `MockAggregator` (price) and `InterestRateManagerTester` (rate)
- the verified `MUSDSavingsRate` (sMUSD) source
- tigris (mezo-org/tigris) for the v2 pool, the pool factory and the router. `Router`, `PoolFactory`, `Pool` and `PoolFees`, and the OpenZeppelin 4.9.0 they use, match the verified testnet source line for line (router `0x9a1f…D7E9`, factory `0x4947…Ce1A`, pool implementation `0xc56f…30f5`)
- Mezo Earn for the veBTC sleeve, the savings sleeve's gauge and the booster (veBTC, veMEZO, Voter, VaultGauge, BoostVoter, the reward and splitter contracts), using the verified testnet explorer sources in `src/earn`, unchanged. `test/SleeveBase.sol` wires them the way testnet reads.

The one stand-in is `test/Btc.sol`, for the BTC ERC-20 precompile at `0x7b7c…0000`.
That precompile is Go code inside mezod, and Mezo publishes no Solidity version of it.
The stand-in follows mezod's `precompile/erc20` package: balances are native
balances, a transfer moves native BTC without calling `receive()`, and approve and
transferFrom follow its authz rules.

MEZO is also a precompile with no source, and nothing replaces it. The main Voter
emits BTC instead. Where a test needs a MEZO-like token with code, the gauge reward
of `SavingsSleeve.harvestMezo` and the token of the booster's veMEZO lock,
`SleeveBase._lpEarn` builds a second Voter, veMEZO and BoostVoter on Mezo's own
sources around the LP token of a tigris MUSD and sMUSD pool, and points veBTC's
booster at that BoostVoter.

Each source builds with the compiler version and optimizer runs it was deployed with.
veBTC was deployed built for osaka. Here it builds for london, because osaka breaks
`forge coverage`'s source mapping.

The spread guard opens no loan before the savings sleeve has a day of sMUSD history,
so `Base.setUp` seeds sMUSD and pays one yield a day after the vault is deployed.

## Result (155 tests, v8, 2026-11-10)

All 155 pass.

| File | Lines | Statements | Branches | Functions |
| --- | --- | --- | --- | --- |
| Booster.sol | 95.65% (44/46) | 97.14% (68/70) | 100% (8/8) | 100% (5/5) |
| ProfitLock.sol | 100% (14/14) | 100% (18/18) | 100% (2/2) | 100% (3/3) |
| QueueMath.sol | 100% (13/13) | 100% (20/20) | 100% (3/3) | 100% (2/2) |
| RedeemQueue.sol | 100% (65/65) | 100% (80/80) | 100% (14/14) | 100% (14/14) |
| SavingsSleeve.sol | 97.01% (130/134) | 97.45% (191/196) | 94.74% (36/38) | 100% (19/19) |
| SystemMath.sol | 95.12% (39/41) | 94.55% (52/55) | 83.33% (10/12) | 100% (5/5) |
| Vault.sol | 98.49% (456/463) | 98.63% (650/659) | 96.55% (112/116) | 100% (72/72) |
| VeSleeve.sol | 96.18% (126/131) | 96.45% (190/197) | 87.50% (35/40) | 100% (18/18) |

Every line and branch left uncovered falls into one of three groups:

- **Excluded on purpose.** Vault 485–486, 609 and 741 are where `_repayBlocked()`
  returns true. That case depends on a Mezo-side edge case that is under
  responsible disclosure, so no test reproduces it.
- **Defensive checks no real input reaches.**
  - Vault 605 `revert Illiquid()`: with no trove, every exit and fill is capped at
    idle BTC plus surplus, and the surplus is claimed just before this check.
  - SavingsSleeve 222, SystemMath 81 and VeSleeve 260 revert when `approve`
    returns false, but MUSD, the tigris LP token and the BTC precompile return
    true or revert.
  - SavingsSleeve 111–112 reverts when the Voter's sMUSD gauge stakes another
    token. Mezo's Voter keys every gauge by its own staking token.
  - VeSleeve 141–142 and 254 guard against a Mezo Earn upgrade that breaks a call
    while `live()` still passes. None of Mezo's own Earn contracts behaves that way.
- **Lines `--ir-minimum` cannot attribute.** Vault 453, 692, 708, 743, 850 and 927,
  SavingsSleeve 134–135 and 248, and SystemMath 104–105 run in nearly every test.
  For example, Vault 692 and 850 are the `_parkMusd()` calls that end every rebalance
  and every roll, Vault 453 and 927 are the `_applyFee()` calls that
  `test_riseWaitsThirtyDays` and `test_riseRestartsDelay` assert, SavingsSleeve
  134–135 are the snapshot and restake that `test_snapshotRing` and
  `test_parkStakesTheShare` assert, and SystemMath 104–105 are the quote behind every
  MUSD buy-back. Booster 103–104 and VeSleeve 266–268 are inline assembly.

## Fixed in v8 before release

- The first fee high-water mark, raw assets per share, let an exit and a deposit
  while profit unlocked ratchet it up, so later gains paid no fee. The loss
  carry-forward `deficit` replaced it, and `test_roundTripDuringUnlockKeepsFee`
  pins the fix.
- `Booster.boost()` reverted `LockExpired` while a matured rung waited in its slot.
  It now skips ended rungs, which `test_maturedRungSkippedByBoost` pins.

## Known behaviour

`test/RebateCheckpoint.t.sol` covers the fix for an issue found by the vault
session's independent review. After the Thursday flip, the first write to veBTC
pays veBTC's global checkpoint catch-up, about 666k gas, over the sleeve's 600k
`CLAIM_GAS`. v7 skipped every live rung's rebate in that roll. v8 calls veBTC's
`checkpoint()` inside `collect()` on its own 1M budget, and reverts `LowGas` when
the caller's gas cannot fund it, so the roll claims every rebate without a keeper
checkpoint first.

The sleeve scenarios in `test/Sleeve.t.sol` and the wiring check in
`test/Wiring.t.sol` come from the vault session's lifecycle suite. The pure-math
fuzz and invariant suites for ProfitLock and QueueMath live in `contracts/test` and
run with `forge test` from `contracts/`.
