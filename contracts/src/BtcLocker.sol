// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * Feasy's liquid veBTC locker.
 *
 * BTC, or a veBTC lock someone already holds, goes into a ladder of at most
 * four veBTC locks that end on consecutive Thursdays, and the depositor gets
 * fveBTC one for one. A lock that comes in merges into the longest rung, so
 * every fveBTC stands for BTC voting at full weight. fveBTC is a plain ERC-20
 * that earns while it is held. Every rung votes all its weight for one gauge,
 * and MezoLocker's pooled veMEZO boosts the rungs up to five times.
 *
 * roll() is open to anyone. It claims every rung's fees, bribes and rebates,
 * releases the rungs that ended, pays the redemption queue first and locks
 * the rest again in the longest rung. New BTC and MUSD above what is owed is
 * income. fveMEZO holders get boostBps of it, but never more than the part of
 * the ladder's weight their boost adds, feeBps goes to the treasury, and the
 * rest streams to fveBTC holders over the next week. MEZO the rungs earn goes
 * into the veMEZO lock.
 *
 * Redeeming burns fveBTC into a first-in-first-out queue that every released
 * rung fills before anything is locked again. Locks end within four weeks, so
 * a request waits at most that long. The owner sets fees and pauses deposits
 * and has no way to move principal, rewards or locks.
 *
 * Mezo Earn is upgradeable, so every claim runs on a fixed gas budget and each
 * rung's weekly work runs on its own, as in the vault's veBTC sleeve.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IVeBTC, IVoter, IReward, IRewardsDistributor, IBoostVoter} from "./interfaces/IMezo.sol";
import {IVeBTCLocks, LockedBalance} from "./interfaces/ILocks.sol";
import {LockerRewards} from "./LockerRewards.sol";
import {MezoLocker} from "./MezoLocker.sol";

contract BtcLocker is LockerRewards, Ownable2Step {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    struct Rung {
        uint256 id;
        uint128 amount;
        uint64 end;
    }

    struct Request {
        address owner;
        uint96 amount;
        uint128 end;
        uint128 claimed;
    }

    uint256 private constant WEEK = 7 days;
    uint256 private constant SLOTS = 4;
    uint256 private constant BPS = 10_000;
    uint256 public constant MAX_BOOST_BPS = 3000;
    uint256 public constant MAX_FEE_BPS = 1000;
    uint256 public constant MIN_LOCK = 1e14;
    // Bribe tokens claimed per rung, a longer list leaves the rest to a later roll
    uint256 private constant MAX_TOKENS = 8;
    // Enough for a proxied view, small enough that a broken one cannot drain the caller's gas
    uint256 private constant READ_GAS = 100_000;
    // A claim measured 60k to 470k on testnet, a broken one costs at most this and its rewards
    uint256 private constant CLAIM_GAS = 600_000;
    // Three claims, reset and withdraw measured about 1.1M, a rung that needs more waits as stuck
    uint256 private constant TEND_GAS = 2_500_000;
    // A rebate claim before Mezo's weekly period update reverts, so a matured rung waits this long
    uint256 private constant CLAIM_GRACE = 1 days;
    // veBTC's global catch-up after the Thursday flip
    uint256 private constant CHECKPOINT_GAS = 1_000_000;

    IVeBTCLocks public immutable ve;
    IVoter public immutable voter;
    address public immutable pool;
    address public immutable gauge;
    IReward public immutable fees;
    IReward public immutable bribe;
    IRewardsDistributor public immutable distributor;
    IBoostVoter public immutable boostVoter;
    IERC20 public immutable mezo;
    MezoLocker public immutable mezoLocker;

    Rung[4] public rungs;
    // Principal inside the rungs
    uint256 public locked;
    // Principal out of the ladder, waiting for the queue or the next lock
    uint256 public idle;
    // BTC the queue has been given and not yet claimed
    uint256 public reserved;
    uint256 public queued;
    uint256 public filled;
    Request[] public requests;
    mapping(address => uint256[]) private _requestIds;

    uint16 public boostBps = 1500;
    uint16 public feeBps = 500;
    address public treasury;
    address public guardian;
    bool public paused;
    // Mezo Earn as last checked by a roll, a changed wiring stops new locks
    bool public liveAtRoll = true;

    event Deposited(address indexed sender, address indexed receiver, uint256 amount, uint256 veId);
    event RedeemRequested(uint256 indexed id, address indexed owner, uint256 amount);
    event RedeemClaimed(uint256 indexed id, address indexed owner, uint256 amount);
    event QueueFilled(uint256 amount, uint256 filled);
    event Rolled(uint256 released, uint256 relocked);
    event Harvested(address indexed token, uint256 income, uint256 boostCut, uint256 fee);
    event RungStuck(uint256 indexed id);
    event FeesSet(uint16 boostBps, uint16 feeBps, address treasury);
    event GuardianSet(address guardian);
    event PausedSet(bool paused);
    event Swept(address indexed token, uint256 amount);

    error BadLocker();
    error Paused();
    error TooSmall();
    error NoRung();
    error Voted();
    error BadLock();
    error NotAllowed();
    error LowGas();
    error RebatePending();

    constructor(IVoter voter_, IERC20 btc_, IERC20 musd_, address pool_, address treasury_)
        LockerRewards(btc_, musd_, "Feasy liquid veBTC", "fveBTC")
        Ownable(msg.sender)
    {
        IVeBTCLocks ve_ = IVeBTCLocks(voter_.ve());
        address gauge_ = voter_.gauges(pool_);
        IBoostVoter boostVoter_ = IBoostVoter(ve_.booster());
        if (
            ve_.token() != address(btc_) || ve_.voter() != address(voter_)
                || gauge_ == address(0) || !voter_.isAlive(gauge_)
                || address(boostVoter_) == address(0)
        ) revert BadLocker();
        ve = ve_;
        voter = voter_;
        pool = pool_;
        gauge = gauge_;
        fees = IReward(voter_.gaugeToFees(gauge_));
        bribe = IReward(voter_.gaugeToBribe(gauge_));
        distributor = IRewardsDistributor(ve_.distributor());
        boostVoter = boostVoter_;
        treasury = treasury_;
        guardian = msg.sender;
        mezoLocker = new MezoLocker(btc_, musd_, voter_, boostVoter_);
        mezo = mezoLocker.mezo();
    }

    // BTC sent here outside a deposit is income for the next roll
    receive() external payable {}

    /* Deposits */

    function deposit(address receiver) external payable nonReentrant returns (uint256 amount) {
        _open();
        amount = msg.value;
        if (amount < MIN_LOCK) revert TooSmall();
        _lock(amount);
        _mint(receiver, amount);
        emit Deposited(msg.sender, receiver, amount, 0);
    }

    // Takes a veBTC lock that votes nowhere and merges it into the longest rung ending with it or later
    function depositLock(uint256 id, address receiver)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _open();
        ve.transferFrom(msg.sender, address(this), id);
        if (ve.voted(id)) revert Voted();
        // The merge burns the lock, so a rebate still owed to it has to land in it first
        _gas(CHECKPOINT_GAS + CLAIM_GAS);
        try ve.checkpoint{gas: CHECKPOINT_GAS}() {} catch {}
        (bool ok,) = address(distributor).call{gas: CLAIM_GAS}(
            abi.encodeCall(IRewardsDistributor.claim, (id))
        );
        if (!ok) revert RebatePending();
        LockedBalance memory l = ve.locked(id);
        if (l.isPermanent || l.end <= block.timestamp) revert BadLock();
        amount = uint256(int256(l.amount));
        if (amount < MIN_LOCK) revert TooSmall();
        Rung storage r = rungs[_target(l.end)];
        ve.merge(id, r.id);
        r.amount += amount.toUint128();
        locked += amount;
        _poke(r.id);
        _mint(receiver, amount);
        emit Deposited(msg.sender, receiver, amount, id);
    }

    /* Redemptions */

    function requestRedeem(uint256 amount) external nonReentrant returns (uint256 id) {
        if (amount == 0) revert TooSmall();
        _burn(msg.sender, amount);
        queued += amount;
        id = requests.length;
        requests.push(Request(msg.sender, amount.toUint96(), queued.toUint128(), 0));
        _requestIds[msg.sender].push(id);
        emit RedeemRequested(id, msg.sender, amount);
        _fill();
    }

    // Anyone may push a filled request out, it only ever pays its owner
    function claimRedeem(uint256 id) external nonReentrant returns (uint256 amount) {
        amount = claimable(id);
        if (amount == 0) return 0;
        Request storage q = requests[id];
        q.claimed += amount.toUint128();
        reserved -= amount;
        btc.safeTransfer(q.owner, amount);
        emit RedeemClaimed(id, q.owner, amount);
    }

    function claimable(uint256 id) public view returns (uint256) {
        Request memory q = requests[id];
        uint256 start = q.end - q.amount + q.claimed;
        uint256 ready = Math.min(filled, q.end);
        return ready > start ? ready - start : 0;
    }

    function requestsOf(address owner_) external view returns (uint256[] memory) {
        return _requestIds[owner_];
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    /* Weekly work */

    function roll() external nonReentrant {
        liveAtRoll = live();
        // Read before any rung is released, while the weight that earned this income still stands
        uint256 share = boostShare();
        // The first veBTC write after the flip pays the catch-up, which would starve a rebate claim
        if (locked > 0) {
            _gas(CHECKPOINT_GAS);
            try ve.checkpoint{gas: CHECKPOINT_GAS}() {} catch {}
        }
        uint256 released;
        for (uint256 i; i < SLOTS; i++) {
            uint256 id = rungs[i].id;
            if (id == 0) continue;
            // The whole budget has to reach tend, so a short gas limit reverts instead of skipping
            _gas(TEND_GAS);
            try this.tend{gas: TEND_GAS}(i) returns (uint256 amount) {
                released += amount;
            } catch {
                emit RungStuck(id);
            }
        }
        locked -= released;
        idle += released;
        _fill();
        _harvest(btc, idle + reserved, share);
        _harvest(musd, 0, share);
        uint256 earnedMezo = mezo.balanceOf(address(this));
        if (earnedMezo > 0) mezo.safeTransfer(address(mezoLocker), earnedMezo);
        uint256 again = idle;
        // On its own call, so a lock Mezo refuses leaves the BTC idle and the releases standing
        if (again < MIN_LOCK || paused || !liveAtRoll) {
            again = 0;
        } else {
            try this.relock(again) {
                idle = 0;
            } catch {
                again = 0;
            }
        }
        emit Rolled(released, again);
    }

    function relock(uint256 amount) external {
        if (msg.sender != address(this)) revert NotAllowed();
        _lock(amount);
    }

    // Claims run first and stick even when the release fails, withdraw burns what is unclaimed
    function tend(uint256 i) external returns (uint256) {
        if (msg.sender != address(this)) revert NotAllowed();
        Rung memory r = rungs[i];
        try fees.getReward{gas: CLAIM_GAS}(r.id, _tokens()) {} catch {}
        try bribe.getReward{gas: CLAIM_GAS}(r.id, _bribeTokens()) {} catch {}
        bool claimed;
        try distributor.claim{gas: CLAIM_GAS}(r.id) {
            claimed = true;
        } catch {}
        if (r.end > block.timestamp) {
            _revote(r.id);
            return 0;
        }
        if (!claimed && block.timestamp < r.end + CLAIM_GRACE) return 0;
        try this.release(r.id) {
            delete rungs[i];
            return r.amount;
        } catch {
            emit RungStuck(r.id);
            return 0;
        }
    }

    // On its own call, so a release Mezo refuses leaves the claims above standing
    function release(uint256 id) external {
        if (msg.sender != address(this)) revert NotAllowed();
        if (ve.voted(id)) voter.reset(id);
        ve.withdraw(id);
    }

    // Only a lock's owner may open its boost gauge, about 2.5M gas so never inside a roll
    function addBoostGauge(uint256 i, address gaugeFactory) external returns (address) {
        uint256 id = rungs[i].id;
        if (id == 0) revert NoRung();
        return boostVoter.createBoostGauge(
            gaugeFactory, id, new address[](0), new uint256[](0)
        );
    }

    // The share of the ladder's voting weight veMEZO adds, in bps, the most fveMEZO is paid for
    function boostShare() public view returns (uint256) {
        uint256 boosted;
        uint256 plain;
        for (uint256 i; i < SLOTS; i++) {
            uint256 id = rungs[i].id;
            if (id == 0) continue;
            uint256 b = _read(address(ve), abi.encodeCall(IVeBTC.votingPowerOfNFT, (id)));
            uint256 p =
                _read(address(ve), abi.encodeCall(IVeBTCLocks.unboostedVotingPowerOfNFT, (id)));
            // A read that fails pays fveMEZO nothing rather than a guess
            if (b == type(uint256).max || p == type(uint256).max) return 0;
            boosted += b;
            plain += p;
        }
        return boosted > plain ? (boosted - plain) * BPS / boosted : 0;
    }

    // New locks only make sense while Mezo Earn still points at what the constructor checked
    function live() public view returns (bool) {
        return _read(address(ve), abi.encodeCall(IVeBTC.voter, ())) == uint160(address(voter))
            && _read(address(ve), abi.encodeCall(IVeBTC.distributor, ()))
                == uint160(address(distributor))
            && _read(address(voter), abi.encodeCall(IVoter.gauges, (pool))) == uint160(gauge)
            && _read(address(voter), abi.encodeCall(IVoter.isAlive, (gauge))) == 1;
    }

    // Bribes in any other token have no stream here, anyone may send them on to the treasury
    function sweep(IERC20 token) external nonReentrant {
        if (token == btc || token == musd || token == mezo || treasury == address(0)) {
            revert NotAllowed();
        }
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(treasury, amount);
        emit Swept(address(token), amount);
    }

    /* Owner and guardian */

    function setFees(uint16 boostBps_, uint16 feeBps_, address treasury_) external onlyOwner {
        if (boostBps_ > MAX_BOOST_BPS || feeBps_ > MAX_FEE_BPS) revert BadLocker();
        boostBps = boostBps_;
        feeBps = feeBps_;
        treasury = treasury_;
        emit FeesSet(boostBps_, feeBps_, treasury_);
    }

    function setGuardian(address guardian_) external onlyOwner {
        guardian = guardian_;
        emit GuardianSet(guardian_);
    }

    // The guardian or the owner may stop deposits, only the owner resumes them
    function setPaused(bool paused_) external {
        if (msg.sender != owner() && (!paused_ || msg.sender != guardian)) revert NotAllowed();
        paused = paused_;
        emit PausedSet(paused_);
    }

    /* Internal */

    function _open() internal view {
        if (paused || !live()) revert Paused();
    }

    // The longest rung that is free or already ends that week takes the BTC
    function _lock(uint256 amount) internal {
        uint256 start = block.timestamp - block.timestamp % WEEK;
        for (uint256 k = SLOTS; k > 0; k--) {
            uint256 end = start + k * WEEK;
            Rung storage r = rungs[_slot(end)];
            // An older rung waits in this slot for its release
            if (r.id != 0 && r.end != end) continue;
            if (!btc.approve(address(ve), amount)) revert BadLocker();
            if (r.id == 0) {
                uint256 id = ve.createLock(amount, end - block.timestamp);
                rungs[_slot(end)] = Rung(id, amount.toUint128(), uint64(end));
                _vote(id);
            } else {
                ve.increaseAmount(r.id, amount);
                r.amount += amount.toUint128();
                _poke(r.id);
            }
            locked += amount;
            return;
        }
        revert NoRung();
    }

    // The longest rung ending with the lock or later, a lock about to end would add almost no weight
    function _target(uint256 end) internal view returns (uint256) {
        uint256 last = block.timestamp - block.timestamp % WEEK + SLOTS * WEEK;
        for (uint256 e = last; e >= end; e -= WEEK) {
            Rung memory r = rungs[_slot(e)];
            if (r.id != 0 && r.end == e) return _slot(e);
        }
        revert NoRung();
    }

    function _fill() internal {
        uint256 amount = Math.min(queued - filled, idle);
        if (amount == 0) return;
        filled += amount;
        idle -= amount;
        reserved += amount;
        emit QueueFilled(amount, filled);
    }

    // Income goes to fveMEZO for the boost, the treasury, and a week's stream for fveBTC
    function _harvest(IERC20 token, uint256 principal, uint256 share) internal {
        if (totalSupply() == 0) return;
        uint256 income = _income(token, principal);
        if (income == 0) return;
        // A stream nobody held was charged when it first came in
        uint256 fresh = income - _takeReturned(token, income);
        uint256 cut =
            mezoLocker.totalSupply() > 0 ? fresh * Math.min(boostBps, share) / BPS : 0;
        uint256 fee = treasury != address(0) ? fresh * feeBps / BPS : 0;
        _credit(token, address(mezoLocker), cut);
        _credit(token, treasury, fee);
        _stream(token, income - cut - fee);
        emit Harvested(address(token), income, cut, fee);
    }

    function _vote(uint256 id) internal {
        _gas(CLAIM_GAS);
        try voter.vote{gas: CLAIM_GAS}(id, _list(pool), _one()) {} catch {}
    }

    // A rung's Voter weight follows its new size, Mezo refuses this in an epoch's first hour
    function _poke(uint256 id) internal {
        _gas(CLAIM_GAS);
        try voter.poke{gas: CLAIM_GAS}(id) {} catch {}
    }

    // A rung that could not vote when it opened, or lost its votes to a killed gauge, votes again
    function _revote(uint256 id) internal {
        if (!liveAtRoll) return;
        uint256 start = block.timestamp - block.timestamp % WEEK;
        if (voter.votes(id, pool) > 0 || voter.lastVoted(id) >= start) return;
        if (ve.votingPowerOfNFT(id) == 0 || !voter.isAlive(gauge)) return;
        try voter.vote{gas: CLAIM_GAS}(id, _list(pool), _one()) {} catch {}
    }

    // A try call gets its whole budget or the transaction reverts, so gas estimates cannot skip it
    function _gas(uint256 budget) internal view {
        if (gasleft() < budget + budget / 63 + 50_000) revert LowGas();
    }

    // One word from a view, copying no more than that word, or a value no check accepts
    function _read(address target, bytes memory data) internal view returns (uint256 word) {
        assembly ("memory-safe") {
            let ok := staticcall(READ_GAS, target, add(data, 32), mload(data), 0, 32)
            word := not(0)
            if and(ok, gt(returndatasize(), 31)) { word := mload(0) }
        }
    }

    function _slot(uint256 end) internal pure returns (uint256) {
        return end / WEEK % SLOTS;
    }

    function _tokens() internal view returns (address[] memory list) {
        list = new address[](3);
        list[0] = address(musd);
        list[1] = address(btc);
        list[2] = address(mezo);
    }

    // Every token the gauge's bribes pay, MUSD, BTC and MEZO when the list cannot be read
    function _bribeTokens() internal view returns (address[] memory list) {
        uint256 n = _read(address(bribe), abi.encodeWithSignature("rewardsListLength()"));
        if (n == type(uint256).max) return _tokens();
        n = Math.min(n, MAX_TOKENS);
        list = new address[](n);
        for (uint256 i; i < n; i++) {
            list[i] = address(uint160(_read(address(bribe), abi.encodeWithSignature("rewards(uint256)", i))));
        }
    }

    function _list(address a) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = a;
    }

    function _one() internal pure returns (uint256[] memory weights) {
        weights = new uint256[](1);
        weights[0] = 1;
    }
}
