# Coverage suite

Local Foundry tests for the live v7 contracts in `contracts/src`. Run from the repo root:

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
- Mezo Earn for the veBTC sleeve (veBTC, Voter, VaultGauge, the reward and splitter contracts, BoostVoter), using the verified testnet explorer sources in `src/earn`, unchanged. `test/SleeveBase.sol` wires them the way testnet reads.

The one stand-in is `test/Btc.sol`, for the BTC ERC-20 precompile at `0x7b7c…0000`.
That precompile is Go code inside mezod, and Mezo publishes no Solidity version of it.
The stand-in follows mezod's `precompile/erc20` package: balances are native
balances, a transfer moves native BTC without calling `receive()`, and approve and
transferFrom follow its authz rules. MEZO, the emission token, is also a precompile
with no source, so the Voter emits BTC instead. The vault never touches emissions.

Each source builds with the compiler version and optimizer runs it was deployed with.
veBTC was deployed built for osaka. Here it builds for london, because osaka breaks
`forge coverage`'s source mapping.

## Result (92 tests, v7, 2026-10-25)

| File | Lines | Statements | Branches | Functions |
| --- | --- | --- | --- | --- |
| ProfitLock.sol | 100% (14/14) | 100% (18/18) | 100% (2/2) | 100% (3/3) |
| QueueMath.sol | 100% (13/13) | 100% (20/20) | 100% (3/3) | 100% (2/2) |
| RedeemQueue.sol | 100% (65/65) | 100% (80/80) | 100% (14/14) | 100% (14/14) |
| SystemMath.sol | 100% (11/11) | 100% (21/21) | 100% (1/1) | 100% (2/2) |
| Vault.sol | 98.43% (440/447) | 98.47% (643/653) | 94.69% (107/113) | 100% (70/70) |
| VeSleeve.sol | 95.97% (119/124) | 96.20% (177/184) | 86.11% (31/36) | 100% (17/17) |

Every line and branch left uncovered falls into one of three groups:

- **Excluded on purpose.** Vault lines 456, 457, 591 and 708 are where
  `_repayBlocked()` returns true. That case depends on a Mezo-side edge case that
  is under responsible disclosure, so no test reproduces it.
- **Defensive checks no real input reaches.**
  - Vault 587 `revert Illiquid()`: with no trove, every exit and fill is capped at
    idle BTC plus surplus, and the surplus is claimed just before this check.
  - Vault 817 and VeSleeve 244 revert when `approve` returns false, but MUSD and
    the BTC precompile return true or revert.
  - VeSleeve 134–135 and 238 guard against a Mezo Earn upgrade that breaks a
    view while `live()` still passes. None of Mezo's own Earn contracts behaves
    that way.
- **Lines `--ir-minimum` cannot attribute.** Vault 490, 663, 679, 710, 776 and 847
  run in nearly every test. For example, 663 and 847 are the `_parkMusd()` calls
  that end every rebalance and every roll, and the same tests hit those lines on v6,
  which built without IR. VeSleeve 250–252 are the inline assembly of `_read`,
  which runs on every roll.

## Known v7 behaviour

`test/RebateCheckpoint.t.sol` pins an issue found by the vault session's
independent review. After the Thursday flip, the first write to veBTC pays veBTC's
global checkpoint catch-up. When that first write is the sleeve's rebate claim, the
claim needs about 666k gas, over the sleeve's 600k `CLAIM_GAS`. The roll then skips
every live rung's rebate. The rebates stay claimable, but a rung that ended more
than a day earlier is released without them. This costs yield, never principal. The keeper calls
veBTC's permissionless `checkpoint()` before every roll, and the last test shows that
this lets the roll claim everything. The tests named `test_known_*` assert today's
behaviour, so they fail once a later version checkpoints inside `collect()`.

The sleeve scenarios in `test/Sleeve.t.sol` and the wiring check in
`test/Wiring.t.sol` come from the vault session's v7 lifecycle suite. The pure-math
fuzz and invariant suites for ProfitLock and QueueMath live in `contracts/test` and
run with `forge test` from `contracts/`.
