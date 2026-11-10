// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * BTC savings vault on Mezo.
 *
 * Users deposit BTC for ERC-4626 shares priced in BTC. The vault owns one MUSD
 * trove backed by the pooled BTC, keeps its ratio inside a band around a
 * target, parks the borrowed MUSD in the MUSD Savings Vault (sMUSD) and
 * harvests savings income above the loan cost back into BTC.
 *
 * raw = idle BTC + trove collateral + claimable surplus collateral
 *     + BTC locked in the veBTC sleeve + (MUSD held - MUSD owed) / price
 * MUSD owed is the trove debt minus the 200 MUSD gas deposit returned on close.
 * The MUSD term is valued at the PriceFeed price with the swap slippage applied
 * against the vault, which is what converting it would cost or fetch.
 *
 * Shares are priced at totalAssets, the unlocked part of raw. Every entry
 * point takes a checkpoint first. A rise in raw that no deposit caused is
 * locked there and released linearly over unlockPeriod, and a fall uses up
 * the locked profit before it lowers the share price.
 *
 * The vault keeps MUSD held at or just above MUSD owed. rebalance buys back
 * the borrow fee and interest with BTC, harvest sells savings income above a
 * small cushion. With no MUSD gap left behind, an exit takes a clean pro rata
 * slice. Withdrawals use idle BTC first, then release collateral while
 * repaying debt from savings, and close the trove once the loan would fall
 * under Mezo's minimum or out of the ratio band. An exit larger than that
 * waits in the RedeemQueue, which is paid first in arrival order.
 *
 * Part of the BTC can sit in the VeSleeve, weekly veBTC locks that vote for
 * the sMUSD gauge and earn its MUSD fees. Locked BTC counts at face value but
 * is not liquid, so exits beyond the liquid part wait for the next roll.
 *
 * The sMUSD sits in the SavingsSleeve, which stakes a share in the sMUSD gauge
 * for MEZO and measures the realized savings rate. New debt is taken only while
 * that rate beats the loan rate. A performance fee of feeBps comes out of each
 * gain at its checkpoint once earlier losses are won back, before the rest
 * starts unlocking to holders. Those losses are kept per share, so deposits
 * and exits never erase or create them.
 *
 * unwind closes the loan, and when Mezo refuses a close in Recovery Mode it
 * repays down to the minimum loan and leaves closing set, so the first
 * rebalance after Recovery Mode finishes the close.
 *
 * Mezo allows 20 precompile calls per transaction and the oracle behind
 * PriceFeed.fetchPrice costs two, so every entry point reads the price once
 * into a State snapshot and passes it down.
 */

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ProfitLock} from "./ProfitLock.sol";
import {RedeemQueue} from "./RedeemQueue.sol";
import {VeSleeve} from "./VeSleeve.sol";
import {SavingsSleeve} from "./SavingsSleeve.sol";
import {SystemMath} from "./SystemMath.sol";
import {
    IBorrowerOperations,
    ITroveManager,
    IPriceFeed,
    ISortedTroves,
    IHintHelpers,
    ICollSurplusPool,
    IActivePool,
    IInterestRateManager,
    ISavings,
    IPoolFactory,
    IRouter,
    IVoter
} from "./interfaces/IMezo.sol";

contract Vault is ERC4626, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Trove {
        bool active;
        uint256 coll;
        uint256 debt;
    }

    struct State {
        uint256 price;
        uint256 idle;
        uint256 surplus;
        uint256 held;
        uint256 sleeve;
        Trove trove;
    }

    uint8 private constant TROVE_ACTIVE = 1;
    uint256 private constant BPS = 10_000;
    uint256 private constant HINT_TRIALS = 15;
    // MUSD kept above what the loan owes, about five weeks of 1% interest
    uint256 private constant CUSHION_BPS = 10;
    uint256 private constant MIN_SWAP = 1e18;
    // A smaller fill waits for more liquidity, unless it empties the queue
    uint256 private constant MIN_FILL = 1e12;
    uint256 private constant MAX_UNLOCK_PERIOD = 30 days;
    uint256 private constant WEEK = 7 days;
    // veBTC votes open an hour after the Thursday flip and close an hour before the next one
    uint256 private constant VOTE_DELAY = 1 hours;
    // Smallest new veBTC lock, the same floor VeSleeve keeps for every rung
    uint256 private constant MIN_RUNG = 1e14;
    // Two new rungs measured just under 2M gas on testnet, a lock gets this fixed budget
    uint256 private constant LOCK_GAS = 3_000_000;
    uint256 private constant MAX_FEE_BPS = 2000;
    // Longer than the 4 weeks a veBTC lock can hold an exit, so every holder can leave before a rise
    uint256 private constant FEE_DELAY = 30 days;

    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IPriceFeed public immutable priceFeed;
    ISortedTroves public immutable sortedTroves;
    IHintHelpers public immutable hintHelpers;
    ICollSurplusPool public immutable collSurplusPool;
    IInterestRateManager public immutable interestRateManager;
    IERC20 public immutable musd;
    SavingsSleeve public immutable savingsSleeve;
    IRouter public immutable router;
    address public immutable poolFactory;
    address private immutable activePool;
    uint256 private immutable gasComp;
    // Gains reach the share price linearly over this period, 7 days on the live vault
    uint256 public immutable unlockPeriod;
    RedeemQueue public immutable queue;
    VeSleeve public immutable sleeve;

    address public keeper;
    // Fast key that can only stop new borrowing or unwind, the owner keeps every other power
    address public guardian;
    uint256 public minCR = 2e18;
    uint256 public targetCR = 2.5e18;
    uint256 public maxCR = 3e18;
    uint256 public bufferBps = 300;
    uint256 public slippageBps = 100;
    uint16 public maxBorrowRate = 200;
    uint256 public depositCap = type(uint256).max;
    // Off at deployment, no trove opens until the owner turns borrowing on
    bool public borrowingEnabled;
    uint256 public lastPrice;
    // Raw assets at the last checkpoint, plus deposits and minus exits since
    uint256 public recorded;
    ProfitLock.Profit public profit;
    uint16 public feeBps;
    uint16 public nextFeeBps;
    uint64 public nextFeeAt;
    address public feeRecipient;
    // BTC lost and not yet won back, scaled with supply so it stays the same per share
    uint256 public deficit;
    // Set while a Recovery Mode unwind waits for Mezo to allow the close
    bool public closing;

    event Rebalanced(uint256 coll, uint256 debt, uint256 savings);
    event Harvested(uint256 musdIn, uint256 btcOut);
    event ShortfallBought(uint256 btcIn, uint256 musdOut);
    event TroveClosed();
    event KeeperSet(address keeper);
    event BorrowingSet(bool enabled);
    // The values are in the call and in the timelock's own events
    event ParamsSet();
    event GuardianSet(address indexed previousGuardian, address indexed newGuardian);
    event ProfitLocked(uint256 gain, uint256 locked, uint256 unlockAt);
    event FeeTaken(uint256 shares, uint256 assets);
    event FeeSet(uint16 feeBps, address recipient);

    error NotKeeper();
    error NotMezo();
    error BadParams();
    error ZeroShares();
    error Illiquid();
    error NotGuardian();
    error NotQueue();
    error RollWindow();
    error RollGas();

    constructor(
        IERC20 btc,
        IBorrowerOperations borrowerOperations_,
        IHintHelpers hintHelpers_,
        ISavings savings_,
        IRouter router_,
        address poolFactory_,
        address keeper_,
        address guardian_,
        uint256 unlockPeriod_,
        IVoter voter_,
        SavingsSleeve savingsSleeve_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(btc) Ownable(msg.sender) {
        // Deployed first at this vault's address, so the vault's own code stays under the size limit
        if (
            unlockPeriod_ == 0 || unlockPeriod_ > MAX_UNLOCK_PERIOD
                || savingsSleeve_.vault() != address(this)
                || address(savingsSleeve_.savings()) != address(savings_)
        ) revert BadParams();
        borrowerOperations = borrowerOperations_;
        troveManager = ITroveManager(borrowerOperations_.troveManager());
        priceFeed = IPriceFeed(borrowerOperations_.priceFeed());
        sortedTroves = ISortedTroves(borrowerOperations_.sortedTroves());
        collSurplusPool = ICollSurplusPool(borrowerOperations_.collSurplusPool());
        interestRateManager = IInterestRateManager(borrowerOperations_.interestRateManager());
        musd = IERC20(borrowerOperations_.musd());
        activePool = borrowerOperations_.activePool();
        gasComp = borrowerOperations_.MUSD_GAS_COMPENSATION();
        hintHelpers = hintHelpers_;
        savingsSleeve = savingsSleeve_;
        router = router_;
        poolFactory = poolFactory_;
        keeper = keeper_;
        guardian = guardian_;
        unlockPeriod = unlockPeriod_;
        queue = new RedeemQueue(btc);
        VeSleeve sleeve_;
        // A vault deployed without a voter has no sleeve and keeps all its BTC liquid
        if (address(voter_) != address(0)) {
            sleeve_ = new VeSleeve(voter_, btc, musd, address(savings_));
        }
        sleeve = sleeve_;
        emit GuardianSet(address(0), guardian_);
    }

    // Only Mezo pays native BTC in, a stray transfer would be lost to every holder
    receive() external payable {
        if (msg.sender != activePool && msg.sender != address(collSurplusPool)) revert NotMezo();
    }

    /* Deposits and withdrawals */

    function depositBTC(address receiver) external payable nonReentrant returns (uint256 shares) {
        uint256 assets = msg.value;
        uint256 raw = _assets(_state(address(this).balance - assets));
        uint256 total = _checkpoint(raw);
        uint256 maxAssets = _maxDeposit(raw, total);
        if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        shares = _toShares(assets, total, Math.Rounding.Floor);
        if (shares == 0) revert ZeroShares();
        recorded += assets;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        uint256 raw = _assets(_state(address(this).balance));
        uint256 total = _checkpoint(raw);
        uint256 maxAssets = _maxDeposit(raw, total);
        if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        shares = _toShares(assets, total, Math.Rounding.Floor);
        recorded += assets;
        _deposit(_msgSender(), receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        uint256 raw = _assets(_state(address(this).balance));
        uint256 total = _checkpoint(raw);
        uint256 maxShares = _maxShares(_maxDeposit(raw, total), total);
        if (shares > maxShares) revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        assets = _toAssets(shares, total, Math.Rounding.Ceil);
        recorded += assets;
        _deposit(_msgSender(), receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        State memory s = _state(address(this).balance);
        uint256 total = _checkpoint(_assets(s));
        uint256 maxAssets = _maxWithdraw(owner, s, total);
        if (assets > maxAssets) revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        shares = _toShares(assets, total, Math.Rounding.Ceil);
        recorded -= assets;
        _release(assets, s);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        State memory s = _state(address(this).balance);
        uint256 total = _checkpoint(_assets(s));
        uint256 maxShares = _maxRedeem(owner, s, total);
        if (shares > maxShares) revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        assets = _toAssets(shares, total, Math.Rounding.Floor);
        recorded -= assets;
        _release(assets, s);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /* Queue */

    // RedeemQueue moves the owner's shares into escrow, with the same allowance rule as redeem
    function escrow(address owner, address spender, uint256 shares) external {
        if (msg.sender != address(queue)) revert NotQueue();
        if (spender != owner) _spendAllowance(owner, spender, shares);
        _transfer(owner, address(queue), shares);
    }

    // Anyone may call, it pays the oldest requests from liquid BTC at today's share price
    function processQueue(uint256 maxAssets)
        external
        nonReentrant
        returns (uint256 shares, uint256 assets)
    {
        State memory s = _state(address(this).balance);
        (shares, assets) = _fillQueue(s, _checkpoint(_assets(s)), maxAssets, true);
    }

    // Without release the fill only takes BTC the vault holds, so it never touches the trove
    function _fillQueue(State memory s, uint256 total, uint256 maxAssets, bool release)
        internal
        returns (uint256 shares, uint256 assets)
    {
        uint256 pending = _pending();
        if (pending == 0) return (0, 0);
        uint256 room = release ? _liquid(s, total) : Math.min(total, s.idle + s.surplus);
        shares = Math.min(pending, _toShares(Math.min(room, maxAssets), total, Math.Rounding.Floor));
        assets = _toAssets(shares, total, Math.Rounding.Floor);
        // A dust request worth no BTC still goes once it is all that waits
        if (shares == 0 || (assets < MIN_FILL && shares < pending)) return (0, 0);
        recorded -= assets;
        _release(assets, s);
        _burn(address(queue), shares);
        queue.fill{value: assets}(shares);
    }

    function _pending() internal view returns (uint256) {
        return queue.pending();
    }

    /* Views */

    function totalAssets() public view override returns (uint256) {
        return _unlocked(_rawView());
    }

    function maxDeposit(address) public view override returns (uint256) {
        (bool ok, State memory s) = _tryState();
        if (!ok) return 0;
        uint256 raw = _assets(s);
        return _maxDeposit(raw, _unlocked(raw));
    }

    function maxMint(address) public view override returns (uint256) {
        (bool ok, State memory s) = _tryState();
        if (!ok) return 0;
        uint256 raw = _assets(s);
        uint256 total = _unlocked(raw);
        return _maxShares(_maxDeposit(raw, total), total);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        (bool ok, State memory s) = _tryState();
        return ok ? _maxWithdraw(owner, s, _unlocked(_assets(s))) : 0;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        (bool ok, State memory s) = _tryState();
        return ok ? _maxRedeem(owner, s, _unlocked(_assets(s))) : 0;
    }

    // Checkpointed profit the share price has not reached yet
    function lockedProfit() public view returns (uint256) {
        return ProfitLock.remaining(profit, block.timestamp);
    }

    // Everything the vault holds before the unlock, so a loss the next checkpoint nets shows at once
    function rawAssets() external view returns (uint256) {
        return _rawView();
    }

    function savingsValue() public view returns (uint256) {
        return savingsSleeve.value();
    }

    function trove() public view returns (Trove memory t) {
        if (troveManager.getTroveStatus(address(this)) != TROVE_ACTIVE) return t;
        (uint256 coll, uint256 principal, uint256 interest,,,) =
            troveManager.getEntireDebtAndColl(address(this));
        t = Trove(true, coll, principal + interest);
    }

    /* Accounting */

    function _state(uint256 idle) internal returns (State memory) {
        uint256 price = priceFeed.fetchPrice();
        lastPrice = price;
        return _stateAt(idle, price);
    }

    // ERC-4626 max views must not revert, a stale oracle reads as nothing available
    function _tryState() internal view returns (bool ok, State memory s) {
        try priceFeed.fetchPrice() returns (uint256 price) {
            return (true, _stateAt(address(this).balance, price));
        } catch {
            return (false, s);
        }
    }

    // A stale oracle falls back to the last price a state change saw, so pricing never reverts
    function _rawView() internal view returns (uint256) {
        (bool ok, State memory s) = _tryState();
        return _assets(ok ? s : _stateAt(address(this).balance, lastPrice));
    }

    function _stateAt(uint256 idle, uint256 price) internal view returns (State memory s) {
        s.price = price;
        s.idle = idle;
        s.surplus = collSurplusPool.getCollateral(address(this));
        s.held = savingsValue() + musd.balanceOf(address(this));
        if (address(sleeve) != address(0)) s.sleeve = sleeve.principal();
        s.trove = trove();
    }

    function _assets(State memory s) internal view returns (uint256) {
        uint256 btc = s.idle + s.surplus + s.trove.coll + s.sleeve;
        uint256 owed = s.trove.active ? s.trove.debt - gasComp : 0;
        // No price is seen only before the first deposit, when MUSD can only arrive as a donation
        if (s.price == 0) return btc;
        if (s.held >= owed) return btc + _btcProceeds(s.held - owed, s.price);
        uint256 cost = _btcCost(owed - s.held, s.price);
        return btc > cost ? btc - cost : 0;
    }

    function _unlocked(uint256 raw) internal view returns (uint256) {
        return ProfitLock.unlocked(profit, recorded, raw, block.timestamp);
    }

    // Returns the total shares are priced at, which the checkpoint leaves unchanged
    function _checkpoint(uint256 raw) internal returns (uint256) {
        (ProfitLock.Profit memory p, uint256 gain) =
            ProfitLock.checkpoint(profit, recorded, raw, block.timestamp, unlockPeriod);
        _applyFee();
        // A gain first wins back earlier losses, only the rest takes a fee
        uint256 covered = Math.min(gain, deficit);
        deficit = deficit + recorded.saturatingSub(raw) - covered;
        uint256 fee = totalSupply() == 0 ? 0 : (gain - covered).mulDiv(feeBps, BPS);
        p.locked -= uint128(fee);
        profit = p;
        recorded = raw;
        if (fee > 0) {
            // Priced on raw assets, so the fee shares take no part of profit still unlocking
            uint256 shares = _toShares(fee, raw - fee, Math.Rounding.Floor);
            _mint(feeRecipient, shares);
            emit FeeTaken(shares, fee);
        }
        if (gain > 0) emit ProfitLocked(gain, p.locked, p.unlockAt);
        return raw - p.locked;
    }

    // Recovery Mode blocks collateral release, and held MUSD only turns into BTC on harvest
    function _liquid(State memory s, uint256 total) internal view returns (uint256) {
        uint256 btc = s.idle + s.surplus;
        Trove memory t = s.trove;
        if (!t.active || troveManager.checkRecoveryMode(s.price)) return btc;
        uint256 owed = t.debt - gasComp;
        uint256 locked;
        // Without a close the trove stays at target above the floor and holds the system at CCR
        if (!_systemAllowsExit(t, s.price) || (s.held < owed && !_canBuy(owed - s.held, s.price))) {
            locked = Math.max(
                _debtFloor(s).mulDiv(targetCR, s.price, Math.Rounding.Ceil), _systemKeep(t, s.price)
            );
        }
        // Without repayments only collateral above the band floor at today's debt can leave
        if (_repayBlocked()) {
            locked = Math.max(locked, t.debt.mulDiv(minCR, s.price, Math.Rounding.Ceil));
        }
        // A close pays the MUSD gap in BTC, which total no longer covers once it counts the sleeve
        if (s.held < owed) locked = Math.max(locked, _btcCost(owed - s.held, s.price));
        return Math.min(total, btc + t.coll.saturatingSub(locked));
    }

    // Mezo floors pooled interest at each update, so the last trove can owe more than the pool holds
    function _repayBlocked() internal view returns (bool) {
        (,, uint256 interest,,, uint256 pending) = troveManager.getEntireDebtAndColl(address(this));
        return IActivePool(activePool).getInterest() + pending < interest;
    }

    function _systemAllowsExit(Trove memory t, uint256 price) internal view returns (bool) {
        return SystemMath.systemAllowsExit(troveManager, t.coll, t.debt, price);
    }

    function _systemKeep(Trove memory t, uint256 price) internal view returns (uint256) {
        return SystemMath.systemKeep(troveManager, t.coll, t.debt, price, targetCR);
    }

    // Lowest debt reachable without a swap, repayments only use MUSD the vault holds
    function _debtFloor(State memory s) internal view returns (uint256) {
        return Math.max(_minDebt(), s.trove.debt.saturatingSub(s.held));
    }

    function _canBuy(uint256 musdAmount, uint256 price) internal view returns (bool) {
        return SystemMath.canBuy(
            IPoolFactory(poolFactory), router, asset(), address(musd), _btcCost(musdAmount, price),
            musdAmount
        );
    }

    function _maxWithdraw(address owner, State memory s, uint256 total)
        internal
        view
        returns (uint256)
    {
        if (owner == address(queue)) return 0;
        uint256 shares = balanceOf(owner);
        return
            Math.min(_toAssets(shares, total, Math.Rounding.Floor), _liquidShare(shares, s, total));
    }

    function _maxRedeem(address owner, State memory s, uint256 total)
        internal
        view
        returns (uint256)
    {
        if (owner == address(queue)) return 0;
        uint256 shares = balanceOf(owner);
        uint256 liquid = _liquidShare(shares, s, total);
        // Converting a fully covered balance back to shares would round under it
        if (liquid >= _toAssets(shares, total, Math.Rounding.Floor)) return shares;
        return Math.min(shares, _toShares(liquid, total, Math.Rounding.Floor));
    }

    // Waiting requests are paid first, instant exits share what is left pro rata
    function _liquidShare(uint256 shares, State memory s, uint256 total)
        internal
        view
        returns (uint256)
    {
        if (shares == 0) return 0;
        uint256 liquid = _liquid(s, total);
        uint256 pending = _pending();
        if (pending > 0) liquid = liquid.saturatingSub(_toAssets(pending, total, Math.Rounding.Ceil));
        return liquid >= total ? liquid : liquid.mulDiv(shares, totalSupply() - pending);
    }

    // The cap counts every asset held, shares are priced at the unlocked total
    function _maxDeposit(uint256 raw, uint256 total) internal view returns (uint256) {
        if (total == 0 && totalSupply() > 0) return 0;
        if (depositCap == type(uint256).max) return depositCap;
        return depositCap.saturatingSub(raw);
    }

    function _maxShares(uint256 maxAssets, uint256 total) internal view returns (uint256) {
        if (maxAssets == type(uint256).max) return maxAssets;
        return _toShares(maxAssets, total, Math.Rounding.Floor);
    }

    function _toShares(uint256 assets, uint256 total, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), total + 1, rounding);
    }

    function _toAssets(uint256 shares, uint256 total, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        return shares.mulDiv(total + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _btcProceeds(uint256 musdAmount, uint256 price) internal view returns (uint256) {
        return musdAmount.mulDiv((BPS - slippageBps) * 1e18, price * BPS);
    }

    function _btcCost(uint256 musdAmount, uint256 price) internal view returns (uint256) {
        return musdAmount.mulDiv((BPS + slippageBps) * 1e18, price * BPS, Math.Rounding.Ceil);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /* Trove management */

    // Frees BTC for a withdrawal by releasing collateral and repaying debt from savings
    function _release(uint256 assets, State memory s) internal {
        if (s.idle >= assets) return;
        if (s.surplus > 0) borrowerOperations.claimCollateral();
        uint256 idle = address(this).balance;
        if (idle >= assets) return;
        Trove memory t = s.trove;
        if (!t.active) revert Illiquid();
        uint256 need = assets - idle;
        uint256 coll = t.coll.saturatingSub(need);
        uint256 debt = Math.min(t.debt, Math.max(coll.mulDiv(s.price, targetCR), _debtFloor(s)));
        if (_repayBlocked()) debt = t.debt;
        if (coll == 0 || coll.mulDiv(s.price, debt) < minCR) {
            _closeTrove(t, s.price);
            return;
        }
        (address upper, address lower) = _hint(t, coll, debt);
        if (debt == t.debt) {
            borrowerOperations.withdrawColl(need, upper, lower);
        } else {
            _pullMusd(t.debt - debt);
            borrowerOperations.adjustTrove(need, t.debt - debt, false, upper, lower);
        }
    }

    // Repays the whole loan, buying any MUSD shortfall with BTC first
    function _closeTrove(Trove memory t, uint256 price) internal {
        uint256 owed = t.debt - gasComp;
        _pullMusd(owed);
        uint256 held = musd.balanceOf(address(this));
        if (held < owed) {
            uint256 btcIn = _btcCost(owed - held, price);
            uint256 idle = address(this).balance;
            if (idle < btcIn) {
                (address upper, address lower) = _neighbours();
                borrowerOperations.withdrawColl(btcIn - idle, upper, lower);
            }
            _swap(asset(), address(musd), btcIn, owed - held);
        }
        borrowerOperations.closeTrove();
        emit TroveClosed();
    }

    // Anyone may call, it only steers the trove to the target ratio and buys back the MUSD gap
    function rebalance() external nonReentrant {
        State memory s = _state(address(this).balance);
        uint256 total = _checkpoint(_assets(s));
        if (s.surplus > 0) {
            borrowerOperations.claimCollateral();
            s.idle = address(this).balance;
            s.surplus = 0;
        }
        // Waiting requests take idle BTC before the trove can
        (, uint256 paid) = _fillQueue(s, total, type(uint256).max, false);
        s.idle -= paid;
        bool recovery = troveManager.checkRecoveryMode(s.price);
        // Recovery Mode freezes trove collateral, so idle BTC stays where users can withdraw it
        uint256 spare;
        if (!recovery && _pending() == 0) {
            uint256 raw = _assets(s);
            spare = s.idle.saturatingSub(raw.mulDiv(bufferBps, BPS) + _sleeveHold(raw));
        }
        Trove memory t = s.trove;

        if (closing) {
            // The unwind finishes on the first rebalance Mezo allows the close, spare BTC waits idle
            uint256 owed = t.active ? t.debt - gasComp : 0;
            if (
                !t.active
                    || (!recovery && _systemAllowsExit(t, s.price)
                        && (s.held >= owed || _canBuy(owed - s.held, s.price)))
            ) {
                if (t.active) _closeTrove(t, s.price);
                closing = false;
            }
        } else if (!t.active) {
            // Opening needs room above the minimum loan so small withdrawals do not close it again
            if (_canBorrow(recovery) && spare.mulDiv(s.price, maxCR) >= _minDebt()) {
                _openTrove(spare, s.price);
            }
        } else {
            uint256 coll = t.coll + spare;
            uint256 ratio = coll.mulDiv(s.price, t.debt);
            if (ratio < minCR) {
                _repayToTarget(s, coll, spare, recovery);
            } else if (ratio > maxCR && _canBorrow(recovery)) {
                _borrowToTarget(t, coll, spare, s.price);
            } else if (spare > 0) {
                (address upper, address lower) = _hint(t, coll, t.debt);
                borrowerOperations.addColl{value: spare}(upper, lower);
            }
        }

        _buyShortfall(s.price);
        _parkMusd();
        t = trove();
        emit Rebalanced(t.coll, t.debt, savingsValue());
    }

    // Oracle-bounded sale, open to anyone once the trove is gone and only MUSD is left
    function harvest(uint256 maxIn) external nonReentrant returns (uint256 btcOut) {
        State memory s = _state(address(this).balance);
        if (s.trove.active && msg.sender != keeper && msg.sender != owner()) revert NotKeeper();
        _checkpoint(_assets(s));
        uint256 owed = s.trove.active ? s.trove.debt - gasComp : 0;
        uint256 keep = owed + owed.mulDiv(CUSHION_BPS, BPS);
        uint256 amount = Math.min(s.held.saturatingSub(keep), maxIn);
        if (amount == 0) return 0;
        _pullMusd(amount);
        btcOut = _swap(address(musd), asset(), amount, _btcProceeds(amount, s.price));
        _parkMusd();
        // The sale's gain over the haircut value starts unlocking in this transaction
        s = _stateAt(address(this).balance, s.price);
        _fillQueue(s, _checkpoint(_assets(s)), type(uint256).max, false);
        emit Harvested(amount, btcOut);
    }

    function _openTrove(uint256 coll, uint256 price) internal {
        uint256 debt = coll.mulDiv(price, targetCR);
        uint256 amount = (debt - gasComp).mulDiv(1e18, 1e18 + borrowerOperations.borrowingRate());
        (address upper, address lower) = _hint(Trove(false, 0, 0), coll, debt);
        borrowerOperations.openTrove{value: coll}(amount, upper, lower);
    }

    function _repayToTarget(State memory s, uint256 coll, uint256 spare, bool recovery) internal {
        Trove memory t = s.trove;
        uint256 debt = Math.max(coll.mulDiv(s.price, targetCR), _debtFloor(s));
        // Unsafe even at the lowest reachable loan, so hold plain BTC if Mezo lets the trove close
        if (
            !recovery && !_repayBlocked() && coll.mulDiv(s.price, debt) < minCR
                && _systemAllowsExit(t, s.price)
        ) {
            uint256 owed = t.debt - gasComp;
            if (s.held >= owed || _canBuy(owed - s.held, s.price)) {
                _closeTrove(t, s.price);
                return;
            }
        }
        _repayTo(t, debt, spare);
    }

    // Repays from savings toward debt, Recovery Mode allows repayments that add no debt
    function _repayTo(Trove memory t, uint256 debt, uint256 spare) internal {
        uint256 repay = _repayBlocked() ? 0 : t.debt.saturatingSub(debt);
        _pullMusd(repay);
        repay = Math.min(repay, musd.balanceOf(address(this)));
        if (repay == 0 && spare == 0) return;
        (address upper, address lower) = _hint(t, t.coll + spare, t.debt - repay);
        borrowerOperations.adjustTrove{value: spare}(0, repay, false, upper, lower);
    }

    function _borrowToTarget(Trove memory t, uint256 coll, uint256 spare, uint256 price) internal {
        uint256 targetDebt = coll.mulDiv(price, targetCR);
        uint256 cap = troveManager.getTroveMaxBorrowingCapacity(address(this));
        // Capacity is fixed at open, refinancing resets it but moves the whole loan to today's rate
        bool cheaper =
            troveManager.getTroveInterestRate(address(this)) >= interestRateManager.interestRate();
        if (targetDebt > cap && cheaper) {
            if (spare > 0) {
                (address up, address low) = _hint(t, coll, t.debt);
                borrowerOperations.addColl{value: spare}(up, low);
                spare = 0;
            }
            (address upper, address lower) = _neighbours();
            borrowerOperations.refinance(upper, lower);
            t = trove();
            cap = troveManager.getTroveMaxBorrowingCapacity(address(this));
        }
        uint256 debt = Math.min(targetDebt, cap);
        uint256 increase = debt.saturatingSub(t.debt);
        uint256 amount = increase.mulDiv(1e18, 1e18 + borrowerOperations.borrowingRate());
        if (amount > 0) {
            (address upper, address lower) = _hint(t, coll, debt);
            borrowerOperations.adjustTrove{value: spare}(0, amount, true, upper, lower);
        } else if (spare > 0) {
            (address upper, address lower) = _hint(t, coll, t.debt);
            borrowerOperations.addColl{value: spare}(upper, lower);
        }
    }

    // Buys the MUSD gap plus a cushion so an exit never leaves the borrow fee on whoever stays
    function _buyShortfall(uint256 price) internal {
        Trove memory t = trove();
        if (!t.active) return;
        uint256 owed = t.debt - gasComp;
        uint256 held = savingsValue() + musd.balanceOf(address(this));
        if (held >= owed) return;
        uint256 amount = owed + owed.mulDiv(CUSHION_BPS, BPS) - held;
        uint256 btcIn = _btcCost(amount, price);
        if (amount < MIN_SWAP || btcIn > address(this).balance || !_canBuy(amount, price)) return;
        uint256 out = _swap(asset(), address(musd), btcIn, amount);
        emit ShortfallBought(btcIn, out);
    }

    // A waiting request stops new debt until the queue is paid, and so does a thin savings spread
    function _canBorrow(bool recovery) internal view returns (bool) {
        return borrowingEnabled && !recovery && _pending() == 0
            && interestRateManager.interestRate() <= maxBorrowRate && savingsSleeve.spreadOk();
    }

    function _minDebt() internal view returns (uint256) {
        return borrowerOperations.minNetDebt() + gasComp;
    }

    // t is the trove before the move, coll and debt where it lands
    function _hint(Trove memory t, uint256 coll, uint256 debt)
        internal
        view
        returns (address, address)
    {
        return SystemMath.hint(
            hintHelpers, sortedTroves, t.active, t.coll, t.debt, coll, debt, HINT_TRIALS
        );
    }

    function _neighbours() internal view returns (address, address) {
        return (sortedTroves.getPrev(address(this)), sortedTroves.getNext(address(this)));
    }

    function _parkMusd() internal {
        uint256 held = musd.balanceOf(address(this));
        if (held > 0) musd.safeTransfer(address(savingsSleeve), held);
        savingsSleeve.park();
    }

    // Raises the MUSD balance to amount from savings, or as close as savings allow
    function _pullMusd(uint256 amount) internal {
        uint256 held = musd.balanceOf(address(this));
        if (held < amount) savingsSleeve.pull(amount - held);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        internal
        returns (uint256)
    {
        return SystemMath.swap(router, poolFactory, tokenIn, tokenOut, amountIn, minOut);
    }

    /* Profit unlock and sleeve */

    // Anyone may call, it starts the unlock of gains made since the last entry point
    function sync() external nonReentrant {
        _checkpoint(_assets(_state(address(this).balance)));
    }

    // Anyone may collect matured rungs and pay the queue, only the keeper's call adds new locks
    function roll() external nonReentrant {
        uint256 start = block.timestamp - block.timestamp % WEEK;
        if (address(sleeve) == address(0) || block.timestamp <= start + VOTE_DELAY) {
            revert RollWindow();
        }
        sleeve.collect();
        _parkMusd();
        State memory s = _state(address(this).balance);
        _fillQueue(s, _checkpoint(_assets(s)), type(uint256).max, false);
        // A lock sized off today's assets could be steered by a deposit just before it
        if (msg.sender != keeper || _pending() > 0 || block.timestamp > start + WEEK - VOTE_DELAY) {
            return;
        }
        if (troveManager.checkRecoveryMode(s.price)) return;
        s = _stateAt(address(this).balance, s.price);
        uint256 raw = _assets(s);
        uint256 amount = Math.min(sleeve.hold(raw), s.idle.saturatingSub(raw.mulDiv(bufferBps, BPS)));
        if (amount < MIN_RUNG) return;
        // Gas estimation would otherwise settle on a limit where the lock runs out and is caught
        if (gasleft() < LOCK_GAS + LOCK_GAS / 63 + 50_000) revert RollGas();
        try sleeve.lock{value: amount, gas: LOCK_GAS}(start) {} catch {}
    }

    // Idle BTC held back for the next roll, so rebalance does not sweep it into the trove
    function _sleeveHold(uint256 raw) internal view returns (uint256) {
        return address(sleeve) == address(0) ? 0 : sleeve.hold(raw);
    }

    /* Guardian */

    // The guardian only moves the vault toward less risk, the owner may do the same
    modifier onlyGuardianOrOwner() {
        if (msg.sender != guardian && msg.sender != owner()) revert NotGuardian();
        _;
    }

    // Stops new debt and leaves the trove as it is, only the owner turns borrowing back on
    function pauseBorrowing() external onlyGuardianOrOwner {
        borrowingEnabled = false;
        emit BorrowingSet(false);
    }

    // Closes the loan and holds plain BTC until the owner enables borrowing again
    function unwind() external nonReentrant onlyGuardianOrOwner {
        borrowingEnabled = false;
        emit BorrowingSet(false);
        State memory s = _state(address(this).balance);
        Trove memory t = s.trove;
        if (!t.active) return;
        // Mezo refuses a close in Recovery Mode or below CCR, so repay to the minimum and close later
        if (troveManager.checkRecoveryMode(s.price) || !_systemAllowsExit(t, s.price)) {
            closing = true;
            _repayTo(t, _minDebt(), 0);
        } else {
            _closeTrove(t, s.price);
            closing = false;
        }
    }

    /* Owner */

    function setKeeper(address keeper_) external onlyOwner {
        keeper = keeper_;
        emit KeeperSet(keeper_);
    }

    // Zero leaves both brakes with the owner alone
    function setGuardian(address guardian_) external onlyOwner {
        address previous = guardian;
        guardian = guardian_;
        emit GuardianSet(previous, guardian_);
    }

    // Turning borrowing back on also calls off an unwind still waiting to close
    function setBorrowingEnabled(bool enabled) external onlyOwner {
        borrowingEnabled = enabled;
        emit BorrowingSet(enabled);
        if (enabled) closing = false;
    }

    // Capped in code, a rise waits FEE_DELAY and a cut applies at once
    function setFee(uint16 feeBps_, address recipient) external onlyOwner {
        if (feeBps_ > MAX_FEE_BPS || (feeBps_ > 0 && recipient == address(0))) revert BadParams();
        _applyFee();
        feeRecipient = recipient;
        if (feeBps_ > feeBps) {
            nextFeeBps = feeBps_;
            nextFeeAt = uint64(block.timestamp + FEE_DELAY);
        } else {
            feeBps = feeBps_;
            nextFeeAt = 0;
        }
        emit FeeSet(feeBps_, recipient);
    }

    // A rise set through setFee takes over once its date passes
    function _applyFee() internal {
        if (nextFeeAt != 0 && block.timestamp >= nextFeeAt) {
            feeBps = nextFeeBps;
            nextFeeAt = 0;
        }
    }

    // Mints and burns move the deficit with supply, so a leaving holder takes their part along
    function _update(address from, address to, uint256 value) internal override {
        uint256 supply = totalSupply();
        super._update(from, to, value);
        if ((from == address(0) || to == address(0)) && supply > 0) {
            deficit = deficit.mulDiv(totalSupply(), supply);
        }
    }

    function setParams(
        uint256 minCR_,
        uint256 targetCR_,
        uint256 maxCR_,
        uint256 bufferBps_,
        uint256 slippageBps_,
        uint16 maxBorrowRate_,
        uint256 depositCap_
    ) external onlyOwner {
        if (minCR_ < 1.5e18 || minCR_ >= targetCR_ || targetCR_ >= maxCR_) {
            revert BadParams();
        }
        if (bufferBps_ > BPS || slippageBps_ > 500) revert BadParams();
        minCR = minCR_;
        targetCR = targetCR_;
        maxCR = maxCR_;
        bufferBps = bufferBps_;
        slippageBps = slippageBps_;
        maxBorrowRate = maxBorrowRate_;
        depositCap = depositCap_;
        emit ParamsSet();
    }
}
