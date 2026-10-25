// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * veBTC ladder of the vault.
 *
 * The keeper's weekly roll sends idle BTC here. It is locked in at most four
 * veBTC rungs that end on consecutive Thursdays at 00:00 UTC, and each new
 * rung votes all its weight for the sMUSD gauge. Every roll claims the MUSD
 * fees and the BTC rebates of every rung, then resets and withdraws each
 * matured rung, and sends all BTC and MUSD back to the vault. There is no
 * owner and the NFTs never move, so locked BTC can only come back to the vault.
 *
 * Mezo Earn is upgradeable. rebalance only reads this contract's own storage,
 * every Mezo Earn call runs on a fixed gas budget, and each rung's weekly work
 * runs on its own, so one broken call costs its own rung and never the rest.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IVeBTC, IVoter, IReward, IRewardsDistributor} from "./interfaces/IMezo.sol";

interface IVaultRoles {
    function owner() external view returns (address);
    function guardian() external view returns (address);
    function keeper() external view returns (address);
}

contract VeSleeve {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Rung {
        uint256 id;
        uint128 amount;
        uint64 end;
    }

    uint256 private constant WEEK = 7 days;
    uint256 private constant SLOTS = 4;
    uint256 private constant MAX_NEW = 2;
    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_BPS = 2500;
    // Enough for a proxied view, small enough that a broken one cannot drain the caller's gas
    uint256 private constant READ_GAS = 100_000;
    // A claim measured 60k to 470k on testnet, a broken one costs at most this and its rewards
    uint256 private constant CLAIM_GAS = 600_000;
    // Two claims, reset and withdraw measured about 1.1M, a rung that needs more waits as stuck
    uint256 private constant TEND_GAS = 2_500_000;
    // A rebate claim before Mezo's weekly period update reverts, so a matured rung waits this long
    uint256 private constant CLAIM_GRACE = 1 days;
    uint256 public constant MIN_RUNG = 1e14;

    address public immutable vault;
    IERC20 public immutable btc;
    IERC20 public immutable musd;
    address public immutable pool;
    IVoter public immutable voter;
    IVeBTC public immutable ve;
    address public immutable gauge;
    IReward public immutable fees;
    IReward public immutable bribe;
    IRewardsDistributor public immutable distributor;

    Rung[4] public rungs;
    uint256 public principal;
    uint16 public sleeveBps;
    uint8 public lockWeeks = 4;
    bool public paused;
    // Mezo Earn as last checked by a roll, so rebalance never calls it
    bool public liveAtRoll;
    uint256 public sleeveCap = type(uint256).max;

    event RungStuck(uint256 indexed id);
    event SleeveSet(uint16 bps, uint256 cap, uint8 lockWeeks);
    event SleevePaused(bool paused);

    error NotVault();
    error BadSleeve();
    error NotAllowed();
    error LowGas();

    constructor(IVoter voter_, IERC20 btc_, IERC20 musd_, address pool_) {
        IVeBTC ve_ = IVeBTC(voter_.ve());
        address gauge_ = voter_.gauges(pool_);
        if (
            ve_.token() != address(btc_) || ve_.voter() != address(voter_)
                || gauge_ == address(0) || !voter_.isAlive(gauge_)
        ) revert BadSleeve();
        vault = msg.sender;
        btc = btc_;
        musd = musd_;
        pool = pool_;
        voter = voter_;
        ve = ve_;
        gauge = gauge_;
        fees = IReward(voter_.gaugeToFees(gauge_));
        bribe = IReward(voter_.gaugeToBribe(gauge_));
        distributor = IRewardsDistributor(ve_.distributor());
        liveAtRoll = true;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    // New locks only make sense while Mezo Earn still points at what the constructor checked
    function live() public view returns (bool) {
        return _read(address(ve), abi.encodeCall(IVeBTC.voter, ())) == uint160(address(voter))
            && _read(address(ve), abi.encodeCall(IVeBTC.distributor, ()))
                == uint160(address(distributor))
            && _read(address(voter), abi.encodeCall(IVoter.gauges, (pool))) == uint160(gauge)
            && _read(address(voter), abi.encodeCall(IVoter.isAlive, (gauge))) == 1;
    }

    // BTC the vault holds back for the next roll, zero while paused or once a roll saw a change
    function hold(uint256 raw) external view returns (uint256) {
        if (paused || !liveAtRoll) return 0;
        return Math.min(raw.mulDiv(sleeveBps, BPS), sleeveCap).saturatingSub(principal);
    }

    function collect() external onlyVault returns (uint256 released) {
        liveAtRoll = live();
        for (uint256 i; i < SLOTS; i++) {
            uint256 id = rungs[i].id;
            if (id == 0) continue;
            // The whole budget has to reach tend, so a short gas limit reverts instead of skipping
            if (gasleft() < TEND_GAS + TEND_GAS / 63 + 50_000) revert LowGas();
            try this.tend{gas: TEND_GAS}(i) returns (uint256 amount) {
                released += amount;
            } catch {
                emit RungStuck(id);
            }
        }
        principal -= released;
        uint256 held = musd.balanceOf(address(this));
        if (held > 0) musd.safeTransfer(vault, held);
        uint256 idle = address(this).balance;
        if (idle > 0) btc.safeTransfer(vault, idle);
    }

    // Claims run first and stick even when the release fails, withdraw burns what is unclaimed
    function tend(uint256 i) external returns (uint256) {
        if (msg.sender != address(this)) revert NotVault();
        Rung memory r = rungs[i];
        try fees.getReward{gas: CLAIM_GAS}(r.id, _list(address(musd))) {} catch {}
        try bribe.getReward{gas: CLAIM_GAS}(r.id, _list(address(musd))) {} catch {}
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
        if (msg.sender != address(this)) revert NotVault();
        if (ve.voted(id)) voter.reset(id);
        ve.withdraw(id);
    }

    // Through the vault owner's 24 hour timelock
    function setSleeve(uint16 bps, uint256 cap, uint8 lockWeeks_) external {
        if (msg.sender != IVaultRoles(vault).owner()) revert NotAllowed();
        if (bps > MAX_BPS || lockWeeks_ == 0 || lockWeeks_ > SLOTS) revert BadSleeve();
        sleeveBps = bps;
        sleeveCap = cap;
        lockWeeks = lockWeeks_;
        emit SleeveSet(bps, cap, lockWeeks_);
    }

    // The vault's guardian, keeper or owner may stop new locks, only the owner resumes them
    function setPaused(bool paused_) external {
        IVaultRoles roles = IVaultRoles(vault);
        if (
            msg.sender != roles.owner()
                && (!paused_ || (msg.sender != roles.guardian() && msg.sender != roles.keeper()))
        ) revert NotAllowed();
        paused = paused_;
        emit SleevePaused(paused_);
    }

    // Fills empty slots longest first, or tops up the longest rung when none is empty
    function lock(uint256 start) external payable onlyVault {
        uint256 count = lockWeeks;
        uint256 amount = msg.value;
        uint256[MAX_NEW] memory ends;
        uint256 n;
        for (uint256 k = count; k > 0 && n < MAX_NEW; k--) {
            uint256 end = start + k * WEEK;
            if (rungs[_slot(end)].id == 0) ends[n++] = end;
        }
        if (n == 0) {
            uint256 end = start + count * WEEK;
            Rung storage r = rungs[_slot(end)];
            // A stuck rung from an older week sits in this slot, so the lock waits
            if (r.end != end) revert BadSleeve();
            _approve(amount);
            ve.increaseAmount(r.id, amount);
            voter.poke(r.id);
            r.amount += SafeCast.toUint128(amount);
        } else {
            if (amount / n < MIN_RUNG) n = 1;
            uint256 part = amount / n;
            for (uint256 j; j < n; j++) {
                _open(ends[j], j + 1 == n ? amount - part * j : part);
            }
        }
        principal += amount;
    }

    function _open(uint256 end, uint256 value) internal {
        _approve(value);
        uint256 id = ve.createLock(value, end - block.timestamp);
        voter.vote(id, _list(pool), _one());
        rungs[_slot(end)] = Rung(id, SafeCast.toUint128(value), uint64(end));
    }

    // A killed and revived gauge loses the rung's votes on the next poke, this gives them back
    function _revote(uint256 id) internal {
        if (!liveAtRoll) return;
        uint256 start = block.timestamp - block.timestamp % WEEK;
        if (voter.votes(id, pool) > 0 || voter.lastVoted(id) >= start) return;
        if (ve.votingPowerOfNFT(id) == 0 || !voter.isAlive(gauge)) return;
        try voter.vote{gas: CLAIM_GAS}(id, _list(pool), _one()) {} catch {}
    }

    // Exactly what veBTC pulls, so no allowance outlives the lock
    function _approve(uint256 value) internal {
        if (!btc.approve(address(ve), value)) revert BadSleeve();
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

    function _list(address a) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = a;
    }

    function _one() internal pure returns (uint256[] memory weights) {
        weights = new uint256[](1);
        weights[0] = 1;
    }
}
