# Feasy v6 implementation spec

v6 is a new deployment. v5 at `0x2964612e8976b4003083E6014cA39f5fD7b41f3A`
stays live and untouched. This spec merges the five Wave 2 feature designs into
one buildable contract set, resolves the conflicts between them, and gives the
storage layout, ABI, precompile budget, build order, test plan and the
decisions still owed to the user.

Everything below was checked against a compiling prototype: the merged vault,
its three libraries (`ProfitLock`, `SwapRoute`, `SystemMath`, plus the
`QueueMath` helper inside the queue) and two of the three satellite contracts
(`RedeemQueue`, `VeSleeve`) build with solc 0.8.28. `ClQuoter` exists so far
only as an interface and a Python reference port. The profit-lock math passes
two fuzz and two unit tests and `QueueMath` passes two fuzz and one unit test;
the stateful invariant run in section 10 is still to be written. Nothing in the
prototype was deployed or sent; the repo's v5 sources were not changed.

## 1. What v6 adds over v5

| # | Feature | Shape |
| --- | --- | --- |
| A | 7-day profit unlock | A rise in raw NAV that no deposit caused is locked at the next checkpoint and released linearly over `unlockPeriod`. A loss eats the lock before it touches the share price. Closes payout sniping. |
| B | Guardian and borrowing-off default | `borrowingEnabled` starts false. A `guardian` key can only `pauseBorrowing()`, `unwind()` and stop new sleeve locks (`VeSleeve.setPaused(true)`). The 24 h timelock keeps every other power. |
| C | Best-of-two swap route | Every swap quotes Mezo's v2 pool and the Slipstream (concentrated) pool and takes whichever pays more, under the same oracle minimum. A view-only `ClQuoter` gives the CL quote. |
| D | Withdrawal queue | A FIFO queue for exits larger than the instant pro-rata cap (Recovery Mode, a refused close, veBTC locks). Shares are escrowed, paid ahead of instant exits at the share price of the fill, and claimed pull-style. |
| E | veBTC sleeve | Up to four veBTC locks on consecutive Thursdays, each voting 100% for the sMUSD gauge, collected weekly by a permissionless `roll()`; only the keeper's `roll()` adds new locks. Depends on D and A. |

Kept byte-for-byte as in v5: `_release`, `_openTrove`, `_borrowToTarget`,
`_hint`, `_neighbours`, `_pullMusd`, `_parkMusd`, `_debtFloor`, `trove()`,
`savingsValue()`, the share maths, and `_repayBlocked()` with its three call
sites (`_liquid`, `_release`, `_repayToTarget`). `_closeTrove` and
`_repayToTarget` each change one call and nothing else. `_canBorrow` keeps its
rate and Recovery-Mode rules and gains the queue gate. Section 6 lists every v5
function that changes and exactly how.

## 2. Contract set and code size

v5 runtime is 22,708 bytes (measured, `cast codesize`), against the 24,576 B
EIP-170 limit. Five features cannot fit in one contract, so v6 is split:

| Contract | Role | Runtime (via-IR) |
| --- | --- | --- |
| `Vault.sol` | the ERC-4626 vault, all entry points | 24,477 B |
| `ProfitLock.sol` | pure unlock math, `internal` library inlined into the vault | 0 (inlined) |
| `SwapRoute.sol` | venue quote and swap, `public` library linked into the vault | 2,725 B |
| `SystemMath.sol` | the two system-ratio helpers, `public` library linked into the vault | 1,398 B |
| `ClQuoter.sol` | view-only Slipstream quote, deployed once, no owner, no storage | not yet written in Solidity |
| `RedeemQueue.sol` | escrow, fills, claims and the queue views, with the `internal` `QueueMath` library inlined | 4,144 B |
| `VeSleeve.sol` | the veBTC ladder and its settings | 7,560 B |

**Measured sizes (prototype with the section 5 rules, solc 0.8.28, optimizer
200 runs):**

| Build | legacy codegen | via-IR |
| --- | ---: | ---: |
| v5 | 22,708 | 20,849 |
| v6, A+B+C+D only (no sleeve) | 26,518 | 23,997 |
| v6, all five | 26,784 | 24,477 |

The A+B+C+D legacy figure predates the final fill rule and view helper, which
moved its via-IR size by -7 B.

Conclusions, all measured, not estimated:

- **v6 requires via-IR.** Legacy codegen is 2.2 KB over even with the split.
  via-IR with `evm_version = london` still emits no PUSH0 or transient storage,
  so the "runs on older Mezo nodes" property from v5 is preserved.
- **The full five-feature vault fits at 24,477 B,** 99 B under the limit, once
  `SwapRoute` and `SystemMath` are linked libraries and `ClQuoter`,
  `RedeemQueue` and `VeSleeve` are their own contracts. 99 B is thin. See the
  open question on whether to also extract the trove-adjustment helpers for
  comfortable headroom, or ship the sleeve in a second deployment (the A+B+C+D
  vault has 579 B to spare).
- **Initcode is the second limit.** The vault's constructor embeds the
  `RedeemQueue` and `VeSleeve` creation code, so the full build's initcode is
  41,901 B against the 49,152 B EIP-3860 cap (7,251 B to spare). Any growth of
  the two satellites counts against it.
- `ProfitLock` stays an `internal` library: measured as an external library it
  made the vault 78 B larger, because the delegatecall stubs cost more than the
  inlined arithmetic saves.

`foundry.toml` for v6 adds `via_ir = true`. The Sourcify verification and the
byte-for-byte reproducibility claim in SECURITY.md move to the via-IR build.
`SwapRoute` and `SystemMath` are deployed first and linked. The deploy script
checks that both linked addresses hold the expected code before the vault is
created, because the max views call them directly and an empty library address
would make every max view revert.

## 3. Conflict resolutions (the merged decisions)

1. **One NAV baseline for the unlock, not a per-source ledger.** The lock
   watches raw `_assets(s)`, which already includes idle, surplus, trove
   collateral, net MUSD and, in v6, the sleeve principal. Every gain (sMUSD
   index jumps, harvest premium, buy-back fills, price drift, donations) is
   caught with no code per source. Resolves profit-unlock open question 1.
2. **Queue escrow is priced at fill time, so a fill is just an exit.** Escrowed
   shares stay in `totalSupply` and keep their pro-rata of gains and losses. A
   fill burns them at the unlocked share price and does `recorded -= assets`,
   the same bookkeeping an instant exit does. No fixed-BTC liability, no second
   adjustment to the unlock. Resolves profit-unlock open question 5 and the
   queue's unlock interaction.
3. **Escrow lives at the `RedeemQueue` address, not the vault.** So
   `balanceOf(queue)` is the pending shares (plus any fBTC sent there directly)
   and the vault needs no `_update` override for escrow. `requestRedeem` lives
   on `RedeemQueue` (keeping the ERC-7540 selector off the vault and saving
   vault bytecode); it calls back `vault.escrow(owner, spender, shares)`, which
   applies the same allowance rule as `redeem` and moves the shares. Blocking a direct fBTC transfer to the queue address is
   dropped as non-essential: such shares are not `pending`, are never burned and
   stay at the queue for good (section 11).
4. **Swap venue selection is a linked library; the CL quote is a separate view
   contract.** Mezo's `QuoterV2` writes state before its callback, so it cannot
   run under `STATICCALL` and costs a precompile call; the vault cannot use it
   in a view. `ClQuoter` is our own port of the pool's swap loop reading only
   public getters. `SwapRoute.quotes` returns best-of-two and `_canBuy` uses the
   same function execution uses, so the max views and the transaction decide
   alike, as far as `ClQuoter` matches the pool. A quote above what the pool
   really pays would let `maxWithdraw` promise a closing exit that reverts, so
   `ClQuoter` is proven to the wei before anything routes through it.
   Resolves harvest-route open questions 3 and 6 (keep the v2 fallback; add the
   `isPaused()` check).
5. **Deposit cap measured on raw NAV.** Keeps v5's meaning of BTC under
   management and avoids a per-second drift that would make a stale `maxDeposit`
   revert. Resolves profit-unlock open question 2.
6. **`unlockPeriod` is a bounded constructor immutable** (1 s to 30 days). The
   live deploy uses 7 days; staging and a short test copy use 1 hour with the
   same runtime bytecode outside immutables. No setter. Resolves profit-unlock
   open question 3.
7. **rebalance does not checkpoint after its own work; harvest does.** Every
   entry point checkpoints before it prices anything, and that is what defeats
   the deposit-harvest-redeem sandwich once the trove is closed: the redeem's
   own checkpoint locks the sale premium before its shares are priced.
   rebalance leaves its buy-back spread and self-triggered payouts for the next
   checkpoint. harvest takes a second checkpoint after the sale so the premium
   starts unlocking at once, and then pays waiting requests from the BTC it just
   bought. Resolves profit-unlock open question 4.
8. **Sleeve settings (`sleeveBps`, `sleeveCap`, `lockWeeks`, `paused`) live on
   `VeSleeve`,** read by the vault through `sleeve.hold(raw)`. Saves vault
   bytecode. The owner's `setSleeve` and the guardian/keeper/owner `setPaused`
   are functions on `VeSleeve`, gated by reading the vault's `owner()`,
   `guardian()` and `keeper()`.
9. **`_canBorrow` is the merge of B and D:** borrowing is allowed only when
   `borrowingEnabled` is on, Mezo is not in Recovery Mode, Mezo's rate is at
   most `maxBorrowRate`, **and the queue is empty.** A waiting request stops new
   debt, and rebalance moves no idle BTC into the trove while one waits. The
   gate is safe against dust only because a fill that empties the queue always
   runs (section 5.1), otherwise one request worth less than 1 wei would hold it
   shut for good.
10. **Use the current Mezo Earn veBTC, not the documented one.** The docs'
    testnet table points at `0xB63f…9231` (30-day max, no sMUSD gauge). v6 wires
    the live `voter` `0x263F1Fd5…5F0D`; the constructor reads `voter.ve()`,
    `voter.gauges(sMUSD)` and `voter.gaugeToFees` and reverts if the gauge is
    zero or dead. Resolves the vebtc-sleeve "wrong system" risk.

## 4. Storage layout (v6 is not a proxy, layout is free)

New immutables on the vault:

```solidity
uint256 public immutable unlockPeriod;   // gains release linearly over this, 7 days live
ICLSwapRouter public immutable clRouter;  // zero deploys v6 with the v2 pool only
IClQuoter public immutable clQuoter;
address public immutable clPool;          // resolved in the constructor, zero if clRouter is zero
int24 public immutable clTickSpacing;
RedeemQueue public immutable queue;       // created by the constructor
VeSleeve public immutable sleeve;         // created by the constructor, zero if voter is zero
```

New constants on the vault: `MIN_FILL = 1e12` (smallest fill that does not
empty the queue), `MAX_UNLOCK_PERIOD = 30 days`, `WEEK = 7 days`, `VOTE_DELAY
= 1 hours` (veBTC's vote window edges) and `MIN_RUNG = 1e14` (smallest new
lock, which also keeps every BTC approval above zero).

New mutable state on the vault:

```solidity
address public guardian;                  // fast brake, after keeper
bool public borrowingEnabled;             // no initializer, so false at deploy (v5 was = true)
uint256 public recorded;                  // raw NAV at the last checkpoint, plus deposits minus exits
ProfitLock.Profit public profit;          // {uint128 locked, uint64 lockedAt, uint64 unlockAt}
```

Everything else keeps its v5 slot and value: `keeper`, `minCR` 2e18, `targetCR`
2.5e18, `maxCR` 3e18, `bufferBps` 300, `slippageBps` 100, `maxBorrowRate` 200,
`depositCap` max, `lastPrice`.

`RedeemQueue` storage:

```solidity
address public immutable vault;
IERC20 public immutable btc;
Request[] private _requests;   // {address owner; address receiver; uint128 end; uint128 claimed}, index 0 a sentinel
QueueMath.Fill[] private _fills;   // {uint128 shares; uint128 assets} cumulative, index 0 is (0,0)
mapping(address => uint256[]) private _ids;   // request ids by owner, read by requestsOf
uint256 public queuedShares;   // all shares ever requested
uint256 public filledShares;   // all shares ever filled, equals the last Fill.shares
uint256 public reserved;       // BTC set aside for filled, unclaimed requests
```

`VeSleeve` storage:

```solidity
address public immutable vault; IERC20 public immutable btc; IERC20 public immutable musd;
address public immutable pool; IVoter public immutable voter; IVeBTC public immutable ve;
address public immutable gauge; IReward public immutable fees; IRewardsDistributor public immutable distributor;
Rung[4] public rungs;          // {uint256 id; uint128 amount; uint64 end}, slot = end / WEEK % 4
uint256 public principal;      // BTC face value locked, counted in NAV
uint16 public sleeveBps;       // 0 = off, hard cap 2500
uint8 public lockWeeks = 4;    // 1..4
bool public paused;
uint256 public sleeveCap = type(uint256).max;
```

`State` gains one field: `uint256 sleeve`, set from `sleeve.principal()` in
`_stateAt` (a plain getter, no precompile call, cannot revert; zero when the
sleeve is not deployed).

## 5. New and changed functions, events, errors

### 5.1 Vault entry points

```solidity
constructor(Config memory c, string memory name_, string memory symbol_)
```

`Config` is one struct (avoids stack-too-deep): `btc, borrowerOperations,
hintHelpers, savings, router, poolFactory, keeper, guardian, clRouter, clQuoter,
clTickSpacing, voter, unlockPeriod`. The constructor reverts `BadParams` if
`unlockPeriod` is 0 or over 30 days, resolves `clPool` from the CL factory and
reverts if it is zero or `clQuoter` has no code, deploys `RedeemQueue` always,
deploys `VeSleeve` when `voter` is non-zero, and emits `GuardianSet(0, guardian)`.

Deposit paths (`depositBTC`, `deposit`, `mint`): read the price into `State`,
`total = _checkpoint(raw)`, check against `_maxDeposit(raw, total)`, then
`recorded += assets` before the mint. `depositBTC` keeps the zero-share revert.

Exit paths (`withdraw`, `redeem`): `total = _checkpoint(_assets(s))`, the v5 max
check and share maths against `total`, then `recorded -= assets` before
`_release(assets, s)` and `_withdraw`.

```solidity
function escrow(address owner, address spender, uint256 shares) external;   // only the queue
function processQueue(uint256 maxAssets) external returns (uint256 shares, uint256 assets);
function sync() external;             // checkpoints, starts an unlock, 2 precompile calls
function roll() external;             // weekly sleeve unlock and queue fill, new locks by the keeper only
function pauseBorrowing() external;   // guardian or owner
function unwind() external;           // guardian or owner, v5 body unchanged
function setGuardian(address) external;  // owner
```

`requestRedeem` lives only on `RedeemQueue` (section 3.3), and the sleeve's
settings and pause live only on `VeSleeve` (sections 3.8 and 5.7). The vault
has no wrapper for either.

**Queue fills.** `_fillQueue(s, total, maxAssets, release)` pays the oldest
requests at the checkpointed `total`: `shares = min(pending,
toShares(min(room, maxAssets), Floor))` and `assets = toAssets(shares, Floor)`,
then `recorded -= assets`, `_release(assets, s)`, the escrowed shares are
burned and `queue.fill{value: assets}(shares)` moves the BTC.

- `processQueue` passes `release = true` with `room = _liquid(s, total)`, so a
  fill may release collateral, repay from savings or close the trove exactly as
  an instant exit of the same size would.
- `rebalance` (after its surplus claim), `harvest` (after the sale) and `roll`
  (after collecting) pass `release = false` with `room = min(total, idle +
  surplus)`. They never move the trove for the queue, so a Mezo refusal cannot
  make them revert.
- A fill waits when it would burn no shares, or when it pays less than
  `MIN_FILL` (1e12 wei) without emptying the queue. A fill that empties the
  queue always runs, even when it pays 0 BTC. Skipping on `assets == 0` instead
  would let one request worth under 1 wei (a single share unit) keep
  `_pending()` above zero forever, and with no cancel that would shut
  `_canBorrow`, the trove top-up and new sleeve locks for good.
- Fills emit `QueueFilled` from the queue and a `Transfer` burn from the vault,
  not an ERC-4626 `Withdraw`.

**roll.** Anyone may call it except in the first hour after the Thursday 00:00
UTC flip (`RollWindow`). It collects matured rungs, parks the MUSD, checkpoints
and fills the queue from idle. It adds new locks only when the caller is the
keeper, no request waits, Mezo is not in Recovery Mode and more than an hour is
left in the epoch, for `min(sleeve.hold(raw), idle above the buffer)` and at
least `MIN_RUNG`. A permissionless lock would let anyone deposit, lock part of
that deposit into veBTC, then leave through the queue on the other holders'
liquid BTC and leave them a larger illiquid sleeve.

New views: `lockedProfit()`, `pendingProfit()`, `profit()`, `recorded()`,
`unlockPeriod()`. `pendingProfit()` reads raw through the same internal helper
as `totalAssets()`, so with a stale oracle it uses `lastPrice` too instead of
reading 0. `totalAssets`, `maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem`
change internally (section 6) but keep their signatures.

New events and errors on the vault:

```solidity
event GuardianSet(address indexed previousGuardian, address indexed newGuardian);
event ProfitLocked(uint256 gain, uint256 locked, uint256 unlockAt);
event SleeveSet(uint16 bps, uint256 cap, uint8 lockWeeks);   // on VeSleeve
error NotGuardian();
error RollWindow();
error NotQueue();
```

`ConcentratedSwap(address tokenIn, uint256 amountIn, uint256 amountOut)` is
emitted by the `SwapRoute` library. `BorrowingSet`, `Rebalanced`, `Harvested`,
`ShortfallBought`, `TroveClosed`, `KeeperSet`, `ParamsSet` are unchanged so the
app's decoders keep working.

### 5.2 ProfitLock (internal library, fuzzable with no Mezo contract)

```solidity
struct Profit { uint128 locked; uint64 lockedAt; uint64 unlockAt; }
function remaining(Profit memory p, uint256 time) internal pure returns (uint256);
function unlocked(Profit memory p, uint256 recorded, uint256 raw, uint256 time) internal pure returns (uint256);
function checkpoint(Profit memory p, uint256 recorded, uint256 raw, uint256 time, uint256 period)
    internal pure returns (Profit memory next, uint256 gain);
```

`unlocked = min(raw, recorded - remaining(time))`. `checkpoint` folds `raw -
recorded` into the lock: a gain adds to `locked` and moves `unlockAt` to the
size-weighted average of the old end and `now + period`; a loss subtracts from
`locked` and keeps `unlockAt`. Validated: continuity (`raw - next.locked`
equals the `unlocked` computed just before), `unlocked <= raw`, `locked <=
recorded`, full release within the period, loss keeps the end. `SafeCast` guards
the uint128.

### 5.3 SwapRoute (public linked library)

```solidity
struct Venues { IRouter router; address poolFactory; ICLSwapRouter clRouter; IClQuoter clQuoter; address clPool; int24 clTickSpacing; }
function quotes(Venues memory v, address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256 v2Out, uint256 clOut);
function swap(Venues memory v, address btc, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, bool skip) public returns (uint256);
```

`quotes` skips v2 when `poolFactory.isPaused()`, skips CL when `clPool` is zero,
and swallows a reverting quote as zero. `swap` takes CL only if `clOut > v2Out`
and `clOut >= minOut`, pays a BTC input as native value (never approves BTC to
the CL router), falls back to v2 on a caught CL revert, and returns 0 where
`skip` is set and neither venue can fill (the v5 `_buyShortfall` early return).
After a caught CL revert on a MUSD input it sets the MUSD allowance to the CL
router back to 0, so no approval outlives the swap. MUSD accepts a zero
approval, and BTC is never approved to the CL router, so the precompile's
zero-approval rule never applies there.

### 5.4 SystemMath (public linked library)

```solidity
function systemAllowsExit(ITroveManager tm, uint256 tcoll, uint256 tdebt, uint256 price) public view returns (bool);
function systemKeep(ITroveManager tm, uint256 tcoll, uint256 tdebt, uint256 price, uint256 targetCR) public view returns (uint256);
```

The v5 bodies verbatim, pulled out purely for code size. `_liquid` calls them.

### 5.5 ClQuoter (standalone view contract, no owner, no storage)

```solidity
function quoteExactIn(address pool, bool zeroForOne, uint256 amountIn) external view returns (uint256 amountOut);
```

An exact-input port of `CLPool.swap`'s step loop reading only the pool's public
getters (`slot0`, `liquidity`, `fee` via `factory.getSwapFee`, `tickSpacing`,
`tickBitmap`, `ticks`). Returns 0 (venue unavailable) when `slot0.unlocked` is
false, `amountIn` is 0 or above int256 max, the price would reach its limit
before the input is spent, or a 24-step cap is hit. The Slipstream/Uniswap-v3
math is GPL-2.0-or-later and stays in its own file. Proven to the wei against
Mezo's on-chain `QuoterV2` (`0x8477…BfC8`) in the test plan; a Python reference
port already matched 30 of 30 live cases.

### 5.6 RedeemQueue

```solidity
function requestRedeem(uint256 shares, address receiver, address owner) external returns (uint256 id);  // calls vault.escrow
function fill(uint256 shares) external payable;   // only the vault, with the BTC as value
function claim(uint256[] calldata ids) external returns (uint256 assets);   // anyone, paid to each receiver
function pending() external view returns (uint256);
function pendingRedeem(uint256 id) / claimableRedeem(id) / getRequest(id) / requestCount() external view;
function requestsOf(address owner) external view returns (uint256[] memory ids);
function sharesAhead(uint256 id) external view returns (uint256);   // unfilled shares queued before id
function queueState() external view returns (uint256 queued, uint256 filled, uint256 reservedBtc, uint256 requests);
```

A request owns the cumulative share range `(start, end]`. A fill appends one
cumulative `Fill` and moves its BTC into `reserved`; a claim pays
`QueueMath.paid(fills, from, to)`, which binary-searches the fill that covers
each end of the range and is exact at fill boundaries. `QueueMath` is an
`internal` library that touches no token, so the split can be fuzzed without a
BTC stand-in. `MAX_CLAIMS = 16`. `claim` reverts `BadParams` for id 0 or an
unknown id instead of an array panic, so one bad id fails a keeper batch with a
clear error. No request, claim or queue view reads a price, so all of them work
with a stale oracle; the views cost 0 precompile calls and a claim costs one
BTC transfer per paid id. New error `BadReceiver` (rejects zero, the vault, the
queue, and any `0x7b7c…` system address).

`requestRedeem(uint256,address,address)` has ERC-7540's selector but not its
meaning: the second argument is the receiver and payment is pulled through
`claim`. The queue does not advertise ERC-7540 support.

### 5.7 VeSleeve

```solidity
function collect() external returns (uint256 released);   // only the vault
function lock(uint256 start) external payable;             // only the vault
function unlock(uint256 i) external returns (uint256);     // only self, inside collect's try/catch
function hold(uint256 raw) external view returns (uint256);
function live() external view returns (bool);
function setSleeve(uint16 bps, uint256 cap, uint8 lockWeeks) external;   // vault owner
function setPaused(bool) external;                                      // pause by guardian, keeper or owner, resume by owner
```

`collect` claims MUSD fees for every rung, then for each matured rung claims the
BTC rebate, resets its vote and `withdraw`s it (in that order, because burning
the NFT forfeits unclaimed rewards), and sends all BTC and MUSD back to the
vault through the BTC/MUSD ERC-20 transfers (not `receive`). `lock` splits new
BTC over the empty slots longest-first (at most two new rungs), or tops up the
longest rung with `increaseAmount` + `poke`; each new rung votes 100% for the
sMUSD gauge in the same transaction. `WEEK`-aligned ends land on Thursday 00:00
UTC. The sleeve never moves an NFT and never calls a governance function, so
locked BTC can only return to the vault.

Mezo Earn must never be able to stop the vault's safety path. `rebalance` calls
`hold()` whenever it is outside Recovery Mode with an empty queue, so `hold()`
and `live()` read
`ve.voter()`, `voter.gauges` and `voter.isAlive` through gas-capped low-level
static calls and treat a revert, a short return or an out-of-gas as "not live"
(hold 0). A plain call, or a `try` that still decodes the return data, would let
a broken or upgraded Mezo Earn contract revert `rebalance` and block repayment.
In `collect`, each rung's work runs inside a `try` on a self-call, the re-vote
reads included, so a reverting Mezo Earn view skips that rung (`RungStuck`)
instead of stopping the matured ones from coming back.

## 6. Every change to v5 code

Diffed against `contracts/src/Vault.sol`. Every v5 function not in the table
below is byte-for-byte v5: `_release`, `_openTrove`, `_borrowToTarget`,
`_hint`, `_neighbours`, `_pullMusd`, `_parkMusd`, `_debtFloor`,
`_repayBlocked`, `trove`, `savingsValue`, `_state`, `_tryState`, `_toShares`,
`_toAssets`, `_btcProceeds`, `_btcCost`, `_maxShares`, `_minDebt`,
`_decimalsOffset`, `setKeeper`, `setBorrowingEnabled` and `setParams`.

`_repayBlocked()` keeps its v5 body and its three v5 call sites (in `_liquid`,
`_release` and `_repayToTarget`), each byte-identical. No new path moves trove
collateral except through `_release`, and the queue sizes its fills with
`_liquid`, so those call sites guard queue fills exactly as they guard instant
exits.

| v5 function | v6 change |
| --- | --- |
| constructor | takes `Config`, bounds `unlockPeriod`, resolves `clPool`, creates `RedeemQueue` and, when `voter` is set, `VeSleeve`, emits `GuardianSet` |
| `receive` | also accepts native BTC from `clRouter` |
| `depositBTC`, `deposit`, `mint` | checkpoint, `_maxDeposit(raw, total)`, `recorded += assets` |
| `withdraw`, `redeem` | checkpoint, `recorded -= assets` before `_release` |
| `totalAssets`, `maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem` | price at `_unlocked(raw)` |
| `_stateAt` | sets `s.sleeve = sleeve.principal()` when the sleeve exists |
| `_assets` | adds `s.sleeve` to the BTC line |
| `_liquid` | calls `SystemMath.systemAllowsExit` and `SystemMath.systemKeep`, the v5 bodies moved verbatim |
| `_systemAllowsExit`, `_systemKeep` | removed from the vault, now `SystemMath` |
| `_repayToTarget` | its one `_systemAllowsExit` call becomes `SystemMath.systemAllowsExit` |
| `_canBuy` | best of the v2 and CL quotes from `SwapRoute.quotes` |
| `_maxWithdraw`, `_maxRedeem` | return 0 for the queue address |
| `_liquidShare` | subtracts the pending shares' value (rounded up) and divides by `totalSupply() - pending` |
| `_maxDeposit` | caps on `raw` and keeps the zero-total check on `total` |
| `_closeTrove` | its `_swap` call passes `skip = false` |
| `_buyShortfall` | drops its `_canBuy` call, swaps with `skip = true`, returns on 0 |
| `_canBorrow` | adds `_pending() == 0` |
| `_swap`, `_route` | replaced by `SwapRoute.swap` through `_venues()` |
| `rebalance` | checkpoint, surplus claim, idle-only queue fill, `spare` zero while a request waits and net of `sleeve.hold(raw)` |
| `harvest` | checkpoint, then after the sale a second checkpoint and an idle-only queue fill |
| `unwind` | also callable by the guardian, body unchanged |
| `borrowingEnabled` | no initializer, so false at deploy |

With an empty queue, nothing locked, no sleeve and no CL router, the max views
and the share maths give their v5 results, except that a paused v2 factory now
reads as unable to buy.

## 7. Precompile budget per entry point

Counting model, from source, anchored to v5's measured 13 for the heaviest
rebalance. `fetchPrice` = 2 (oracle precompile). Each BorrowerOperations trove
move (`openTrove`, `addColl`, `withdrawColl`, `adjustTrove`, `refinance`,
`closeTrove`) = 2 (one internal `fetchPrice`). `claimCollateral` = 0. Each BTC
token call (`approve`, `transfer`, `transferFrom`, `balanceOf`) = 1. v2 swap:
BTC-in 5, MUSD-in 3. CL swap (native-paid): BTC-in 3, MUSD-in 1. CL quote,
`ClQuoter`, `address(this).balance`, MUSD/sMUSD/TroveManager/CollSurplusPool
reads = 0. veBTC `withdraw` and the distributor rebate = 1 each (BTC transfer).
`vote`, `reset` and `poke` = 0. `createLock` and `increaseAmount` = 2 each (the
sleeve's BTC approve 1, veBTC's transferFrom 1). Native value sent to our own
`RedeemQueue` or `VeSleeve` = 0.

Live testnet reports the limit as 20 (`maintenance.getMaxPrecompilesCallsPerExecution()`
= 20, re-read for this spec).

| Entry point | v5 worst | v6 worst | Make-up of the v6 worst case |
| --- | ---: | ---: | --- |
| `depositBTC` | 2 | 2 | price |
| `deposit`, `mint` | 3 | 3 | price + BTC transferFrom |
| `withdraw`, `redeem`, paid from idle | 3 | 3 | price + BTC out (+0 for the checkpoint) |
| `withdraw`, `redeem`, through the trove | 5 | 5 | price + adjust/withdrawColl + BTC out |
| `withdraw`, `redeem`, closing with a shortfall | 12 | 15 | price 2 + withdrawColl 2 + CL fallback to v2 swap 5+(3) + closeTrove 2 + BTC out 1 |
| `rebalance`, heaviest (add + refinance + borrow + buy-back) | 13 | 16 | 2 + 2 + 2 + 2 + buy-back with CL fallback 5+(3); queue fill from idle is 0 |
| `harvest` | 5 | 6 | price 2 + MUSD→BTC with CL fallback 3+(1); second checkpoint and idle fill 0 |
| `unwind` | 11 | 14 | as the closing exit, +3 for the CL fallback |
| `processQueue` (new), through the trove | n/a | 4 | price 2 + adjustTrove or withdrawColl 2 |
| `processQueue` (new), closing | n/a | 14 | price 2 + a `_release` that closes: withdrawColl 2 + shortfall swap with CL fallback 5+(3) + closeTrove 2; the fill itself is native value, 0 |
| `requestRedeem` (new) | n/a | 0 | escrow move only, no price |
| `claim(16)` (new) | n/a | 16 | one BTC transfer per id |
| `sync` (new) | n/a | 2 | price |
| `roll` (new) | n/a | 15 | price 2 + up to 4 matured rungs (claim 1 + withdraw 1 each = 8) + sweep 1 + up to 2 new rungs (approve 1 + createLock transferFrom 1 each = 4) |
| vault views (`totalAssets`, max*, `pendingProfit`, `convertTo*`, `preview*`) | 2 | 2 | price; `lockedProfit`, `profit`, `recorded` = 0 |
| queue views (`pending`, `pendingRedeem`, `claimableRedeem`, `getRequest`, `requestsOf`, `sharesAhead`, `queueState`) | n/a | 0 | storage only |

The CL fallback (`+3` on BTC-in paths, `+1` on harvest) is the only thing that
raises a v5 worst case. Without a fallback every v6 path equals v5, because the
CL leg is always cheaper. The ceiling is 16 of 20 (heaviest rebalance), leaving
4 calls spare on the busiest Mezo path. The limit is per transaction, so a
contract that reads two price views and then makes a closing exit in one
transaction uses 2 + 2 + 15 = 19. All of these must be proven on live testnet
with the `_budgetLeft()` probe (step 2 below); staging undercounts by 2 per
oracle read because its `PriceFeed` is a plain `MockAggregator`.

## 8. ABI and storage changes against v5 (for the app)

New ABI the dashboard needs, by contract:

- vault functions: `processQueue`, `sync`, `roll`, `pauseBorrowing`, `unwind`,
  `setGuardian`, `lockedProfit`, `pendingProfit`, `profit`, `recorded`,
  `unlockPeriod`, `guardian`, `queue`, `sleeve`.
- `RedeemQueue` functions: `requestRedeem`, `claim`, `pending`, `pendingRedeem`,
  `claimableRedeem`, `getRequest`, `requestCount`, `requestsOf`, `sharesAhead`,
  `queueState`, `MAX_CLAIMS`.
- `VeSleeve` functions: `setPaused`, `setSleeve`, `principal`, `rungs`,
  `sleeveBps`, `sleeveCap`, `lockWeeks`, `paused`, `live`, `hold`.
- events: the vault's `GuardianSet` and `ProfitLocked`; `ConcentratedSwap`,
  which the vault address emits but which is declared in `SwapRoute`, so it is
  decoded with the library's ABI; the queue's `RedeemRequested`, `QueueFilled`,
  `Claimed`; the sleeve's `SleeveSet`, `SleevePaused`, `RungStuck`.
- unchanged events (`Deposit`, `Withdraw`, `Transfer`, `Rebalanced`,
  `Harvested`, `ShortfallBought`, `TroveClosed`, `BorrowingSet`) so existing
  decoders keep working.

Behaviour the app must handle: `borrowingEnabled` false and no trove on a fresh
v6 (already done app-side per memory); share-price history from `totalAssets`
and `convertToAssets` becomes a 7-day ramp instead of a step; escrowed shares
sit at the queue address, so holder counts must exclude it; a backlog can make a
holder's `maxWithdraw` read 0 even with idle BTC present. A queue fill emits
`QueueFilled` and a `Transfer` from the queue to zero but no ERC-4626
`Withdraw`, so the paid state of a request comes from `Claimed`. A request
cannot be cancelled, which the app says before the user signs. Each waiting
request lowers every other holder's `maxWithdraw` until it is filled, so a max
withdraw keeps the same small margin it keeps for interest. A deposit made while
requests wait is the first BTC the queue takes, and the depositor's own instant
exit is capped like everyone else's until the backlog clears. On deploy, update
`app/src/lib/chain.ts` `vault.address` and `VAULT_FROM_BLOCK`. The vault session
messages the dashboard session at ABI freeze and at the v6 address.

## 9. Implementation order (smallest safe steps first)

Each step builds and is testable before the next. Steps 1-4 are the A+B+C+D
vault (fits with 579 B to spare); step 5 adds the sleeve (99 B to spare, see
the open question on headroom).

1. **Repo scaffolding.** Add `via_ir = true` to `contracts/foundry.toml`. Add
   `ProfitLock.sol` and fuzz it in Foundry with no fork, no Mezo contract, no
   precompile stand-in. The prototype's suite passes continuity, bounds,
   release schedule and loss-keeps-end; the stateful invariant run of section
   10 is written here.
2. **Guardian and borrowing-off (feature B).** `guardian`, `borrowingEnabled =
   false`, `onlyGuardianOrOwner`, `pauseBorrowing`, `setGuardian`, `GuardianSet`,
   `NotGuardian`, the `unwind` access change. `_canBorrow` stays v5 for now. No
   new precompile cost, no Mezo dependency beyond `unwind`'s close. Smallest
   safe change, and it is the mainnet-safety floor.
3. **Profit unlock (feature A).** `recorded`, `profit`, `_checkpoint`,
   `_unlocked`, `sync`, the checkpoint in every entry point, the `totalAssets`
   and max-view wrap, harvest's second checkpoint, `lockedProfit`/`pendingProfit`.
   `_maxDeposit` takes `raw`. Re-run the 21 preflight scenarios on this build
   (two change, last bullet of section 10.2).
4. **Best-of-two route (feature C) and the queue (feature D).** `ClQuoter` and
   `SwapRoute` first, proven to the wei against `QuoterV2`; then `QueueMath`
   (fuzzed with no token), `RedeemQueue` with its views, `escrow`,
   `requestRedeem`, `processQueue`, `_fillQueue` with the section 5.1 wait rule,
   the max-view queue term, the `_canBorrow` queue gate, `receive()` accepting
   the CL router, `SystemMath` extraction for size. This is the full A+B+C+D
   vault.
5. **veBTC sleeve (feature E).** `VeSleeve` with `setSleeve` and `setPaused`,
   the `State.sleeve` field, `roll` with the keeper-only lock step,
   `_sleeveHold`, the rebalance `spare` change. Depends on 3 and 4. Decide the
   size/headroom question first (section 12).

Scripts and harness to change alongside the code (not done in this read-only
pass): `scripts/deploy.sh` constructor args and verify signature;
`contracts/script/Preflight.sol` `deploy()` to pass the new `Config` and call
`setBorrowingEnabled(true)` before trove scenarios; `scripts/sim.sh` to enable
borrowing before Bob's open; `scripts/vault.sh` to add `request`, `process`,
`claim`, `sync`, `roll`, `pause`, `unwind` (guardian/keeper keys);
`scripts/keeper.sh` and `scripts/state.sh` to read the new views; a new
`GUARDIAN` wallet kept out of GitHub secrets; a `deployments/testnet-v6.env` so
the v5 pointers stay. `scripts/deploy.sh` deploys and links `SwapRoute` and
`SystemMath` first and checks their code (section 2).

The keeper's duties in v6: `processQueue` whenever `pending() > 0`, before its
`rebalance`, so a waiting request does not hold back borrowing longer than it
must; `claim` in batches of 16 after each fill; `sync` when `pendingProfit`
passes its threshold; `roll` once a week after the first hour of the epoch,
since only the keeper's call adds new locks; compare the veBTC, Pools Voter
and sMUSD implementation slots each pass and pause the sleeve on a change.

## 10. Test plan (Mezo testnet and staging, no mocks)

No step mocks a Mezo contract. eth_call scenarios inject only our own harness on
live state, as preflight does today. Every transaction and PASS/FAIL line goes
to `deployments/testnet-v6-log.md` or `staging-log.md`.

**1. Pure math, off-chain Foundry.** Fuzz `ProfitLock` and `QueueMath` as
`internal` libraries: continuity, `unlocked <= raw`, `locked <= recorded`,
claims over any partition of the filled range sum to the last fill (so
`reserved` never underflows), payment is monotone and exact at fill boundaries,
a zero-BTC fill keeps later claims exact, a gain releases within the period, a
loss keeps the end. A stateful invariant run drives both libraries from a
handler that models raw, recorded, supply and the queue over random time skips,
gains, losses, deposits, exits, fills and checkpoints, and checks continuity at
every checkpoint, `locked <= recorded`, and that a fill which empties the queue
always runs. No fork, no Mezo contract, no token and no precompile stand-in, so
it does not need the BTC-precompile harness the coverage session is waiting on.
`RedeemQueue`'s transfers, `escrow` and every vault path are tested only on
testnet and staging (steps 2-4). The prototype's `ProfitLock` and `QueueMath`
suites pass (`QueueMath` at 5,000 fuzz runs).

**2. Same-transaction eth_call scenarios (extend `Preflight.sol`).** Each is one
eth_call injecting only our harness on live testnet state.
- Payout snipe closed: deposit, trigger a sMUSD payout via `receiveProtocolYield`,
  redeem everything; v6 returns at most the deposit, and the same steps on v5
  code show the snipe v6 closes.
- Snipe-after-close: with the trove closed, deposit, harvest, redeem; at most the
  deposit, because the redeem's opening checkpoint locks the sale premium before
  its shares are priced.
- Donation: a BTC ERC-20 transfer does not move `totalAssets`; `pendingProfit`
  equals it; after `sync`, `lockedProfit` equals it and `unlockAt = now + period`.
- Continuity: `totalAssets`, `convertToAssets(1e24)`, `maxWithdraw`, `maxRedeem`
  are identical just before and just after a checkpoint (sync and every entry
  point).
- Exact max views: after a payout and a sync with a finite cap,
  `deposit(maxDeposit)`, `mint(maxMint)`, `withdraw(maxWithdraw)`,
  `redeem(maxRedeem)` succeed and `max + 1` reverts.
- Loss netting: raise `slippageBps` (harness owns its vault); while the lock
  covers the loss `totalAssets` holds and after sync `lockedProfit` is lower by
  exactly the loss; a loss over the lock lowers `totalAssets` by the excess.
- Queue: request beyond the instant cap, `processQueue` frees collateral and
  burns at the share price, `claim` pays the receiver, `reserved` returns to 0;
  arrival order and partial fills with `maxAssets`.
- Dust request: request one share unit (worth 0 wei); the next rebalance burns it
  in a 0-BTC fill, `pending()` reads 0 after it, and the same rebalance can add
  collateral and borrow. Behind a larger request it waits and goes with the
  fill that empties the queue.
- Keeper-only lock: a stranger's `roll` collects and fills but locks nothing;
  the keeper's `roll` locks `min(hold, idle above the buffer)`.
- Allowance: after a forced CL failure on a MUSD-in swap, the vault's MUSD
  allowance to the CL router reads 0.
- Route: `ClQuoter` vs `QuoterV2` to the wei for the five liquid BTC/MUSD pools
  in both directions across sizes and tick crossings; a CL-routed harvest and
  buy-back; the 1-wei-to-the-CL-router refund regression for the `receive()`
  change; a deliberately wrong quoter to prove the v2 fallback.
- Precompile budget: run each changed entry point with and without its last step
  and diff `_budgetLeft()`. Expect sync 2, depositBTC 2, deposit 3, harvest 6,
  heaviest rebalance 16, closing exit 15, processQueue 4 through the trove and
  14 closing, claim(16) 16, roll 15.
- Re-run all 21 existing scenarios on v6; scenario 10's "both gained" becomes
  "the payout does not move totalAssets and pendingProfit > 0", scenario 20's
  victim keeps at least the deposit while the donation stays locked.

**3. Live testnet, real transactions.** A fresh v6, deployer-owned until the
timelock handover.
- Role matrix by eth_call: guardian cannot set params/keeper/guardian/borrowing
  or transfer ownership; keeper and strangers cannot pause borrowing or unwind;
  guardian can pause borrowing and unwind; guardian and keeper can pause the
  sleeve but not resume it; only the owner can `setSleeve` or resume.
- Borrowing off at deploy: deposit then rebalance opens no trove; a holder's
  `maxWithdraw` equals their full balance.
- Enable borrowing through the real 24 h timelock, rebalance opens at 2.5, a real
  sMUSD payout, keeper harvest + sync, and an eight-day hourly share-price log:
  v5 jumps at the payout, v6 ramps linearly to the same gain plus the harvest
  premium over 7 days. A wallet that deposits just before the payout and redeems
  just after gets back at most its deposit plus its pro-rata share of the profit
  that was already unlocking while it held.
- Queue: request, processQueue, claim with real transactions; a 16-id claim;
  `requestsOf`, `sharesAhead` and `queueState` agree with the events.
- veBTC (short-period copy first): deposit, two keeper `roll`s in one epoch to
  bootstrap the ladder, check NFTs owned by the sleeve, ends on Thursdays, votes on the
  sMUSD gauge, pro-rata `maxWithdraw`; after the Thursday flip, `roll` claims real
  MUSD, resets and withdraws the matured rung, re-locks, and the keeper harvests
  the claimed MUSD into BTC; an exit beyond liquid funded by the next `roll`.
- A short-period copy (`unlockPeriod` 3600, deployer-owned) proves the 7-day ramp
  to the wei in an hour, since testnet cannot move time.

**4. Staging (Mezo's own MUSD code, real BTC precompile and DEX router).** Reset
`MockAggregator` first (it reads 10,000,000 USD/BTC). Keep the deployer's own
trove open throughout so the vault trove is never the last one.
- Self-triggered sMUSD payouts (staging sMUSD has `pcv` set): a rebalance or exit
  leaves `pendingProfit > 0`, the next checkpoint locks it, harvest's second
  checkpoint locks it in the same transaction.
- Recovery Mode (-50%): exits limited to idle exactly as v5 while the release
  continues; the queue fills from idle only (one `QueueFilled`, no Mezo call);
  the guardian's `unwind` reverts inside Mezo while `pauseBorrowing` works;
  rebalance's pure repayment lifts the system out, then `processQueue` frees
  collateral.
- The 150% line: fills stop at the line that holds the rest of the system at CCR
  and Mezo accepts it.
- Liquidation (-60%): the loss exceeds the lock, `totalAssets` falls by the
  excess, `lockedProfit` is 0, and the post-liquidation harvest's gain streams;
  pending shares take the loss like every share.
- Redemption against the vault trove: the haircut is absorbed by the lock, the
  surplus is claimed inside the fill.
- Stale oracle (`setBlockTime` old): `requestRedeem` and `claim` still work;
  `processQueue`, `rebalance`, `harvest`, `roll` revert, so matured rungs wait
  for a fresh price; max views return 0; `totalAssets` and `pendingProfit` use
  `lastPrice`.
- A private staging copy of Mezo Earn (built from the verified testnet sources)
  for gauge kill/revive, a voter swap, and a lowered max-lock, which live testnet
  cannot trigger. This is the one open no-mocks question (section 12).

**5. Review.** Diff v6 against v5 and confirm only the functions named in section
6 changed and `_repayBlocked()` with its uses is byte-identical. Re-run Slither
and triage the new timestamp findings (ProfitLock) and the harvest-second-checkpoint
reentrancy finding (both by design: every entry point that moves BTC or MUSD is
`nonReentrant`, and `escrow` only moves shares and only for the queue). Update
README.md (the yield-timing row, the Recovery-Mode queue, the guardian, borrowing
off by default) and SECURITY.md (the guardian role row, the new events, `sync`,
the CL router in the "BTC/MUSD leaves only to" lists, the via-IR build).

## 11. Risks carried into v6

- **Value shifts between cohorts over a day held, not per day.** Everyone earns
  the same rate per day, but a payout that accrued while one cohort held is
  released to whoever holds in the week after. Visible on big one-off gains. The
  app must keep `lockedProfit`/`pendingProfit` and the raw-vs-share-price gap on
  screen.
- **Small losses go unseen for a while.** Interest, a fee or a haircut smaller
  than the lock leaves the share price flat and only slows the release.
- **A gain is hidden until a checkpoint runs.** The keeper must `sync` when
  `pendingProfit` is non-trivial; `roll` and harvest checkpoint anyway.
- **Queue liquidity is first-come within arrival order,** and a waiting request
  stops new borrowing, trove top-ups and new sleeve locks. A long freeze can
  make instant `maxWithdraw` read 0 for everyone behind the queue.
- **The queue is a better exit than an instant one whenever liquidity is
  short.** A fill pays full share value out of all liquid BTC, while an
  instant exit is capped at its pro-rata share of what the queue leaves. With
  a sleeve, or with collateral held at the system line, a full exit therefore
  goes through the queue, each request lowers every other holder's instant cap
  until it is filled, and in a long restricted state the earliest requesters
  take the liquid BTC while later holders keep the illiquid part. Value per
  share stays equal, only the order of liquidity changes. This replaces v5's
  rule that liquidity is shared pro rata (open question 9).
- **A deposit just before the keeper's `roll` can still size a new lock,**
  then leave through the queue. Only the keeper can add locks, so this needs a
  front-run of the keeper's weekly call; `sleeveCap` bounds it (open question
  10).
- **Max views trust `ClQuoter`.** `_canBuy` takes the better of the v2 and CL
  quotes, so a CL quote above what the pool really pays could let `maxWithdraw`
  promise a closing exit that then reverts. The 24-step cap and the wei-exact
  proof against `QuoterV2` bound it; the risk only bites when the vault holds
  less MUSD than it owes, which the buy-back keeps rare.
- **The guardian cannot unwind in Recovery Mode or when Mezo refuses the
  close.** Mezo's `closeTrove` reverts in both, so the guardian's brake there
  is `pauseBorrowing`, and anyone's `rebalance` repays toward target.
- **`roll` needs a fresh price.** During an oracle outage matured rungs stay
  uncollected until the price is back.
- **Mezo Earn is upgradeable and outside the core.** The vault reads it only
  through `VeSleeve.hold()` (in `rebalance`) and `roll`; section 5.7 keeps both
  from reverting on a broken Mezo Earn contract. What it cannot prevent is a
  lock that Mezo Earn itself refuses to release.
- **fBTC sent straight to the queue address is stuck for good.** It is not
  `pending`, is never burned, and keeps its share of NAV; other holders' value
  is unchanged and their instant cap only gets slightly more conservative.
- **No early veBTC exit.** Locked BTC waits up to `lockWeeks` weeks + 1 h plus
  however late `roll` runs. A Mezo voter swap could freeze a lock until Mezo adds
  the old voter back; `sleeveCap` and keeper monitoring of `ve.voter()` bound it.
- **A feature that moves value without adjusting `recorded` in the same
  transaction breaks the accounting.** The queue avoids this by pricing escrow
  at fill time. Any later feature must keep that rule.
- **99 B of code-size headroom on the full build.** Any later growth needs
  another extraction. See the open question.
- **Mainnet veBTC and payout cadence, and whether sMUSD's `pcv` is set on
  mainnet, were not read** (mainnet out of scope). The design works either way;
  the keeper's sync threshold and the app copy depend on it.

## 12. Open questions for the user

1. **Code-size headroom.** The full five-feature vault is 24,477 B, 99 B under
   the limit with via-IR plus the `SwapRoute` and `SystemMath` libraries.
   Options: (a) ship it as-is with thin headroom; (b) extract the
   trove-adjustment helpers `_openTrove`, `_borrowToTarget` and `_hint` into
   another library for comfortable room. `_release` and `_repayToTarget` stay
   in the vault, since they hold `_repayBlocked()` call sites that must stay
   byte-identical; (c) ship A+B+C+D first (579 B to spare) and add the sleeve in
   a second v6 deployment. Recommendation: (b) if the sleeve ships with the
   rest, else (c).
2. **Testnet BTC for a full v6 trove.** A production-copy trove that receives real
   sMUSD payouts needs about 0.065-0.077 BTC idle; the project wallets hold about
   0.0092 BTC outside v5. Where does the extra come from, or do we prove the
   payout path on staging and with eth_call scenarios and keep the live run to the
   short-period copy and donations?
3. **A private staging copy of Mezo Earn** (built from Mezo's verified testnet
   veBTC/Voter/gauge sources, with Mezo's own `TestERC20` or real testnet MEZO as
   the emissions token) is the only way to test gauge kills, voter swaps and
   max-lock changes without mocking. Is that acceptable under the no-mocks rule,
   or do those stay as reasoning?
4. **Guardian custody.** On testnet a new EOA kept out of GitHub secrets. On
   mainnet, a hardware EOA or a Safe, and at what threshold, given the guardian
   must respond fast? (Never the keeper key, which lives in Actions secrets.)
5. **CL pool and tick spacing for the testnet v6.** ts10 has the most liquidity
   near the price and wins buy-backs today; ts1 wins harvests. One immutable pool,
   or best-of-N? And which pool for mainnet, which I could not query.
6. **Ladder length and sleeve size.** `lockWeeks` 4 (most vote weight, ~25% frees
   each week, up to 4 weeks' wait) or 1-2 (less weight, faster exits)?
   `sleeveBps` on testnet, and the absolute `sleeveCap`?
7. **A timelocked owner switch to turn CL routing off**, a new owner power, or keep
   it immutable (deploy with `clRouter = 0` the only way off)?
8. **Keep harvest keeper-only while the sleeve has income?** With borrowing off and
   no trove, anyone can harvest, so sleeve income is sold through the sandbox-able
   path bounded by `slippageBps`.
9. **FIFO or shared liquidity for the queue?** As specified, fills take all
   liquid BTC in arrival order (section 11). The alternative bounds each fill
   in a restricted state to the pending shares' pro-rata part of liquid BTC,
   which keeps v5's sharing rule but makes a full exit wait for the restriction
   to end, and does not work with a sleeve, where only the queue can turn
   matured rungs into exits. Recommendation: keep FIFO, show the backlog and the
   no-cancel rule in the app before a request, and keep `sleeveCap` small.
10. **Limit how much one `roll` may lock?** Capping a roll's new lock at one
    rung's worth (`min(raw × sleeveBps, sleeveCap) / lockWeeks`) would stop a
    deposit made just before the keeper's roll from sizing a large lock, at the
    cost of filling the ladder over `lockWeeks` weeks instead of one or two
    rolls. Recommendation: take the cap if the sleeve ships in this
    deployment.
