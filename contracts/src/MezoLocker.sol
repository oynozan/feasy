// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * Feasy's liquid veMEZO, deployed by BtcLocker.
 *
 * MEZO, or a veMEZO lock that votes nowhere, goes into one permanent veMEZO
 * lock and the depositor gets fveMEZO one for one. The lock never ends and
 * fveMEZO never redeems, so it is a liquid claim on boost income, like
 * cvxCRV. Once an epoch boost() votes the whole lock for the boost gauges of
 * BtcLocker's live rungs in proportion to their unboosted weight, so every
 * rung gets the same boost. It waits until the week's roll has released the
 * ended rung and every live rung has its gauge, so an early call cannot spend
 * the epoch's one vote before the new rung is there. harvest() pulls fveMEZO's
 * cut of the ladder's income from BtcLocker and streams it to fveMEZO holders
 * over a week, and adds any MEZO the ladder earned to the lock. Anything open
 * here is open to anyone, and nothing can take the lock out.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVoter, IBoostVoter, IRewardsDistributor} from "./interfaces/IMezo.sol";
import {IVeBTCLocks, IVeMezoLocks, LockedBalance} from "./interfaces/ILocks.sol";
import {LockerRewards} from "./LockerRewards.sol";

interface ILadder {
    function rungs(uint256 i) external view returns (uint256 id, uint128 amount, uint64 end);
    function claim() external returns (uint256 btcPaid, uint256 musdPaid);
    function paused() external view returns (bool);
}

contract MezoLocker is LockerRewards {
    using SafeERC20 for IERC20;

    uint256 private constant SLOTS = 4;
    // veMEZO's longest lock, made permanent right after it opens
    uint256 private constant MAX_LOCK = 208 weeks;
    uint256 private constant CLAIM_GAS = 600_000;

    ILadder public immutable ladder;
    IVoter public immutable voter;
    IVeBTCLocks public immutable ve;
    IBoostVoter public immutable boostVoter;
    IVeMezoLocks public immutable veMezo;
    IERC20 public immutable mezo;

    uint256 public veMezoId;

    event Deposited(address indexed sender, address indexed receiver, uint256 amount, uint256 veId);
    event Boosted(uint256 indexed rung, address gauge, uint256 boost);

    error Paused();
    error TooSmall();
    error Voted();
    error Permanent();
    error Ended();
    error NoLock();
    error NotReady();
    error RebatePending();
    error LowGas();

    constructor(IERC20 btc_, IERC20 musd_, IVoter voter_, IBoostVoter boostVoter_)
        LockerRewards(btc_, musd_, "Feasy liquid veMEZO", "fveMEZO")
    {
        ladder = ILadder(msg.sender);
        voter = voter_;
        ve = IVeBTCLocks(voter_.ve());
        boostVoter = boostVoter_;
        veMezo = IVeMezoLocks(boostVoter_.ve());
        mezo = IERC20(veMezo.token());
    }

    // BTC sent here is income for fveMEZO holders at the next harvest
    receive() external payable {}

    function deposit(uint256 amount, address receiver) external nonReentrant {
        if (ladder.paused()) revert Paused();
        if (amount == 0) revert TooSmall();
        mezo.safeTransferFrom(msg.sender, address(this), amount);
        mezo.forceApprove(address(veMezo), amount);
        uint256 id = veMezoId;
        if (id == 0) {
            id = veMezo.createLock(amount, MAX_LOCK);
            veMezo.lockPermanent(id);
            veMezoId = id;
        } else {
            veMezo.increaseAmount(id, amount);
        }
        _mint(receiver, amount);
        emit Deposited(msg.sender, receiver, amount, 0);
    }

    // Mezo merges no permanent lock and refuses an unlock in a transfer's block, so owners unlock first
    function depositLock(uint256 id, address receiver) external nonReentrant {
        if (ladder.paused()) revert Paused();
        uint256 to = veMezoId;
        if (to == 0) revert NoLock();
        veMezo.transferFrom(msg.sender, address(this), id);
        if (veMezo.voted(id)) revert Voted();
        LockedBalance memory l = veMezo.locked(id);
        if (l.isPermanent) revert Permanent();
        // An ended lock's rebase would come out as loose MEZO the depositor is never credited for
        if (l.end <= block.timestamp) revert Ended();
        // The merge burns the lock, so a rebase still owed to it has to land in it first
        if (!_rebase(id)) revert RebatePending();
        l = veMezo.locked(id);
        uint256 amount = uint256(int256(l.amount));
        if (amount == 0) revert TooSmall();
        veMezo.merge(id, to);
        _mint(receiver, amount);
        emit Deposited(msg.sender, receiver, amount, id);
    }

    // Mezo allows one veMEZO vote an epoch, between an hour after the flip and an hour before the next
    function boost() external nonReentrant {
        uint256 lock = veMezoId;
        if (lock == 0) revert NoLock();
        _rebase(lock);
        address[] memory gauges = new address[](SLOTS);
        uint256[] memory ids = new uint256[](SLOTS);
        uint256[] memory weights = new uint256[](SLOTS);
        uint256 n;
        for (uint256 i; i < SLOTS; i++) {
            (uint256 id,, uint64 end) = ladder.rungs(i);
            if (id == 0) continue;
            // An ended rung means this week's roll has not run, a missing gauge that one is still to open
            address g = boostVoter.boostableTokenIdToGauge(id);
            if (end <= block.timestamp || g == address(0)) revert NotReady();
            uint256 w = ve.unboostedVotingPowerOfNFT(id);
            if (w == 0) continue;
            gauges[n] = g;
            ids[n] = id;
            weights[n++] = w;
        }
        if (n == 0) return;
        assembly ("memory-safe") {
            mstore(gauges, n)
            mstore(ids, n)
            mstore(weights, n)
        }
        boostVoter.vote(lock, gauges, weights);
        for (uint256 k; k < n; k++) {
            boostVoter.pokeBoost(ids[k]);
            voter.poke(ids[k]);
            emit Boosted(ids[k], gauges[k], boostVoter.getBoost(ids[k]));
        }
    }

    // Pulls fveMEZO's cut from the ladder, locks the MEZO it sent and streams new BTC and MUSD to holders
    function harvest() external nonReentrant {
        ladder.claim();
        uint256 earnedMezo = mezo.balanceOf(address(this));
        uint256 lock = veMezoId;
        if (earnedMezo > 0 && lock != 0) {
            mezo.forceApprove(address(veMezo), earnedMezo);
            veMezo.increaseAmount(lock, earnedMezo);
        }
        if (totalSupply() == 0) return;
        uint256 income = _income(btc, 0);
        _takeReturned(btc, income);
        _stream(btc, income);
        income = _income(musd, 0);
        _takeReturned(musd, income);
        _stream(musd, income);
    }

    // veMEZO's rebate goes into the lock itself, false before Mezo's weekly period update
    function _rebase(uint256 id) internal returns (bool ok) {
        address distributor = veMezo.distributor();
        if (distributor == address(0)) return true;
        if (gasleft() < CLAIM_GAS + CLAIM_GAS / 63 + 50_000) revert LowGas();
        (ok,) = distributor.call{gas: CLAIM_GAS}(abi.encodeCall(IRewardsDistributor.claim, (id)));
    }
}
