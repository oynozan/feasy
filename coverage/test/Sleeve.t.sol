// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {ISavings} from "vault/interfaces/IMezo.sol";
import {SleeveBase as Base, IEarnVe, IGaugeLike} from "./SleeveBase.sol";

// The v7 veBTC sleeve through whole weekly cycles on Mezo's own Earn, MUSD and tigris code
contract SleeveTest is Base {
    uint256 constant BPS = 10_000;
    uint256 constant MIN_RUNG = 1e14;
    bytes32 constant PROFIT_LOCKED = keccak256("ProfitLocked(uint256,uint256,uint256)");
    bytes32 constant QUEUE_FILLED = keccak256("QueueFilled(uint256,uint256,uint256)");

    // Sleeve on, one deposit, rebalance, then the keeper's first roll
    function _bootstrap(uint8 lockWeeks, uint256 amount) internal returns (uint256 gas) {
        sleeve.setSleeve(2500, type(uint256).max, lockWeeks);
        _depositBTC(alice, amount);
        vault.rebalance();
        gas = _roll(keeper);
    }

    // Moves to the next epoch flip, lets Mezo run its week, then to one hour and a second past it
    function _nextWeek(uint256 k, bool rebates) internal {
        vm.warp(_epoch(k) + 1 minutes);
        _mezoWeek(rebates);
        vm.warp(_epoch(k) + 1 hours + 1);
    }

    function _proceeds(uint256 musdAmount) internal view returns (uint256) {
        return musdAmount * (BPS - vault.slippageBps()) * 1e18 / (_price() * BPS);
    }

    function _fillsOf(Vm.Log[] memory logs) internal view returns (uint256 assets) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(queue) && logs[i].topics[0] == QUEUE_FILLED) {
                (, uint256 a,) = abi.decode(logs[i].data, (uint256, uint256, uint256));
                assets += a;
            }
        }
    }

    function _assertVotesForGauge(uint256 id) internal view {
        uint256 weight = voter.votes(id, savings);
        assertGt(weight, 0, "votes");
        assertEq(voter.usedWeights(id), weight, "all weight on the sMUSD gauge");
        assertEq(voter.poolVote(id, 0), savings, "pool is sMUSD");
        assertTrue(ve.voted(id), "voted");
        assertEq(ve.ownerOf(id), address(sleeve), "owned by the sleeve");
    }

    /* 1. Bootstrap */

    // The literal order, a deposit and then the keeper's roll, with no trove yet
    function test_1_bootstrap() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        uint256 raw = vault.rawAssets();
        uint256 total = vault.totalAssets();
        uint256 hold = sleeve.hold(raw);
        assertEq(hold, raw * 2500 / BPS, "hold is 25% of raw");

        uint256 gas = _roll(keeper);

        _assertBootstrap(raw, total, hold);
        assertEq(sleeve.principal(), raw / 4, "principal is exactly 25% of raw");
        assertEq(sleeve.hold(vault.rawAssets()), 0, "nothing left to hold");
        uint256 max = vault.maxWithdraw(alice);
        assertEq(max, address(vault).balance, "maxWithdraw is the idle BTC");
        assertEq(max, total - sleeve.principal(), "and only that");
        emit log_named_uint("roll gas", gas);
        emit log_named_uint("raw", raw);
        emit log_named_uint("principal", sleeve.principal());
        emit log_named_uint("maxWithdraw", max);
    }

    // The keeper's real order, rebalance first, whose MUSD buy-back spends some reserved idle
    function test_1b_bootstrapAfterRebalance() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        uint256 raw = vault.rawAssets();
        uint256 total = vault.totalAssets();
        uint256 hold = sleeve.hold(raw);
        uint256 idleCap = address(vault).balance - raw * vault.bufferBps() / BPS;
        assertLt(idleCap, hold, "buy-back spent idle that was held back");
        uint256 gas = _roll(keeper);

        _assertBootstrap(raw, total, idleCap);
        assertApproxEqRel(sleeve.principal(), raw / 4, 0.005e18, "principal within 0.5% of 25%");
        assertEq(sleeve.hold(vault.rawAssets()), hold - idleCap, "the rest waits for idle BTC");
        uint256 liquid = address(vault).balance + vault.trove().coll;
        uint256 max = vault.maxWithdraw(alice);
        assertEq(max, liquid, "maxWithdraw is idle plus trove collateral");
        assertLe(max, total - sleeve.principal(), "locked BTC is not withdrawable");
        emit log_named_uint("roll gas", gas);
        emit log_named_uint("raw", raw);
        emit log_named_uint("hold before roll", hold);
        emit log_named_uint("principal", sleeve.principal());
        emit log_named_uint("principal bps of raw", sleeve.principal() * BPS / raw);
        emit log_named_uint("maxWithdraw", max);
        emit log_named_uint("totalAssets", total);
    }

    function _assertBootstrap(uint256 raw, uint256 total, uint256 locked) internal view {
        (uint256[] memory ids, uint256[] memory amounts, uint256[] memory ends) = _rungs();
        assertEq(ids.length, 2, "two rungs");
        assertEq(ends[0], _epoch(1), "first ends next Thursday");
        assertEq(ends[1], _epoch(2), "second ends the Thursday after");
        for (uint256 i; i < 2; i++) {
            _assertVotesForGauge(ids[i]);
            assertEq(voter.votes(ids[i], savings), ve.votingPowerOfNFT(ids[i]), "full power");
            assertEq(voter.lastVoted(ids[i]), block.timestamp, "voted in this roll");
            IEarnVe.LockedBalance memory l = ve.locked(ids[i]);
            assertEq(uint256(int256(l.amount)), amounts[i], "locked amount");
            assertEq(l.end, ends[i], "lock end");
        }
        assertEq(amounts[0] + amounts[1], locked, "both rungs hold what was locked");
        assertEq(amounts[1], locked / 2, "split in two");
        assertEq(sleeve.principal(), locked, "principal is the lock");
        assertEq(vault.rawAssets(), raw, "raw unchanged by the lock");
        assertEq(vault.totalAssets(), total, "totalAssets unchanged by the lock");
        assertEq(address(sleeve).balance, 0, "sleeve keeps no BTC");
    }

    /* 2. Fees */

    function test_2_fees() public {
        _bootstrap(2, 1 ether);
        (uint256[] memory ids,,) = _rungs();
        uint256 posted = fees.tokenRewardsPerEpoch(address(musd), E0);
        assertGt(posted, 0, "Mezo's distribute posted E0 fees");

        // A protocol bribes the gauge in MUSD for E0, anyone may
        vm.prank(whale);
        musd.transfer(bob, 500e18);
        vm.startPrank(bob);
        musd.approve(address(bribe), 500e18);
        bribe.notifyRewardAmount(address(musd), 500e18);
        vm.stopPrank();

        _nextWeek(1, true);
        assertGt(fees.tokenRewardsPerEpoch(address(musd), _epoch(1)), 0, "E1 fees posted too");

        (uint256 feeTotal, uint256 bribeTotal) = _earnedShares(ids, posted);
        (uint256 id1,) = _rungAt(_epoch(1));
        uint256 rebate1 = distributor.claimable(id1);

        uint256 parked = ISavings(savings).balanceOf(address(vault));
        uint256 rawBefore = vault.rawAssets();
        uint256 totalBefore = vault.totalAssets();
        uint256 lockedBefore = vault.lockedProfit();
        uint256 recordedBefore = vault.recorded();
        vm.recordLogs();
        _roll(keeper);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i; i < ids.length; i++) {
            assertEq(fees.earned(address(musd), ids[i]), 0, "fees claimed");
            assertEq(bribe.earned(address(musd), ids[i]), 0, "bribe claimed");
        }
        uint256 musdIn = feeTotal + bribeTotal;
        assertEq(musd.balanceOf(address(sleeve)), 0, "sleeve passed the MUSD on");
        assertEq(musd.balanceOf(address(vault)), 0, "vault holds no loose MUSD");
        assertEq(
            ISavings(savings).balanceOf(address(vault)) - parked, musdIn, "MUSD parked in sMUSD"
        );

        uint256 rawAfter = vault.rawAssets();
        uint256 gainValue = rawAfter - rawBefore - rebate1;
        assertGe(gainValue + 2, _proceeds(musdIn), "MUSD valued at least at the haircut");
        assertEq(vault.totalAssets(), totalBefore, "not priced instantly");
        assertEq(vault.pendingProfit(), 0, "checkpointed");
        assertEq(vault.recorded(), rawAfter, "recorded moved to raw");
        uint256 gainAfter = rawAfter - recordedBefore;
        assertEq(vault.lockedProfit(), lockedBefore + gainAfter, "whole gain locked");
        assertEq(_lockedGain(logs), rawAfter - recordedBefore, "ProfitLocked gain");

        uint256 lockedNow = vault.lockedProfit();
        uint256 totalNow = vault.totalAssets();
        vm.warp(block.timestamp + 7 days);
        assertEq(vault.lockedProfit(), 0, "released over the unlock period");
        assertGt(vault.totalAssets(), totalNow, "share price rose after the release");

        emit log_named_uint("E0 fees posted MUSD", posted);
        emit log_named_uint("rung fees MUSD", feeTotal);
        emit log_named_uint("rung bribes MUSD", bribeTotal);
        emit log_named_uint("fee and bribe value BTC", gainValue);
        emit log_named_uint("rung E1 rebate BTC", rebate1);
        emit log_named_uint("lockedProfit after roll", lockedNow);
        emit log_named_uint("totalAssets before and after roll", totalBefore);
    }

    // Each rung's E0 fee and bribe share, split out so the unoptimized coverage build fits the stack
    function _earnedShares(uint256[] memory ids, uint256 posted)
        internal
        view
        returns (uint256 feeTotal, uint256 bribeTotal)
    {
        uint256 supply = fees.totalSupply();
        uint256 bribeSupply = bribe.totalSupply();
        for (uint256 i; i < ids.length; i++) {
            uint256 fee = fees.earned(address(musd), ids[i]);
            assertEq(fee, fees.balanceOf(ids[i]) * posted / supply, "fee share of E0");
            assertGt(fee, 0, "rung earned fees");
            feeTotal += fee;
            uint256 b = bribe.earned(address(musd), ids[i]);
            assertEq(b, bribe.balanceOf(ids[i]) * 500e18 / bribeSupply, "bribe share of E0");
            bribeTotal += b;
        }
    }

    function _lockedGain(Vm.Log[] memory logs) internal view returns (uint256 gain) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == PROFIT_LOCKED) {
                (gain,,) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            }
        }
    }

    /* 3. Maturity with Mezo's period updated */

    function test_3_maturityAfterPeriodUpdate() public {
        _bootstrap(2, 1 ether);
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        (uint256 id2, uint256 amt2) = _rungAt(_epoch(2));
        _nextWeek(1, true);
        assertEq(chainFee.activePeriod(), _epoch(1), "Mezo updated the period");
        uint256 rebate1 = distributor.claimable(id1);
        uint256 rebate2 = distributor.claimable(id2);
        assertGt(rebate1, 0, "matured rung has a rebate");
        assertGt(rebate2, 0, "live rung has a rebate");
        uint256 idle = address(vault).balance;
        uint256 principal = sleeve.principal();

        vm.recordLogs();
        uint256 gas = _roll(keeper);
        (uint256 stuck,) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 0, "no RungStuck");

        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "matured rung deleted");
        assertEq(ve.ownerOf(id1), address(0), "NFT burned by withdraw");
        assertFalse(ve.voted(id1), "vote reset");
        assertEq(voter.votes(id1, savings), 0, "votes gone");
        assertEq(distributor.claimable(id1), 0, "rebate claimed");
        assertEq(distributor.claimable(id2), 0, "live rung rebate claimed");
        assertEq(
            uint256(int256(ve.locked(id2).amount)), amt2 + rebate2, "live rebate compounds in lock"
        );

        (uint256 id3, uint256 amt3) = _rungAt(_epoch(3));
        assertGt(id3, 0, "re-locked into the new longest slot");
        _assertVotesForGauge(id3);
        assertEq(sleeve.principal(), principal - amt1 + amt3, "principal drops by the rung");
        assertEq(address(vault).balance, idle + amt1 + rebate1 - amt3, "BTC back in idle");
        assertEq(address(sleeve).balance, 0, "sleeve swept");

        uint256 raw = vault.rawAssets();
        uint256 holdCap = raw * 2500 / BPS - amt2;
        uint256 idleCap = address(vault).balance + amt3 - raw * vault.bufferBps() / BPS;
        assertEq(amt3, holdCap < idleCap ? holdCap : idleCap, "lock sized by hold and buffer");

        // The vault's receive refuses the sleeve, so the BTC came by the token transfer
        vm.deal(address(sleeve), 1);
        vm.prank(address(sleeve));
        (bool ok,) = address(vault).call{value: 1}("");
        assertFalse(ok, "receive rejects the sleeve");

        emit log_named_uint("roll gas", gas);
        emit log_named_uint("released BTC", amt1);
        emit log_named_uint("rebate to vault BTC", rebate1);
        emit log_named_uint("rebate compounded in live rung BTC", rebate2);
        emit log_named_uint("new rung E3 BTC", amt3);
    }

    /* 4. Maturity before Mezo's period update */

    function test_4_maturityBeforePeriodUpdate() public {
        _bootstrap(2, 1 ether);
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        (uint256 id2,) = _rungAt(_epoch(2));
        _nextWeek(1, false);
        assertEq(chainFee.activePeriod(), E0, "period not updated");
        vm.prank(address(sleeve));
        vm.expectRevert(bytes4(keccak256("UpdatePeriod()")));
        distributor.claim(id1);
        uint256 fee1 = fees.earned(address(musd), id1);
        uint256 fee2 = fees.earned(address(musd), id2);
        assertGt(fee1, 0, "matured rung has fees");
        uint256 parked = ISavings(savings).balanceOf(address(vault));

        vm.recordLogs();
        _roll(keeper);
        (uint256 stuck,) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 0, "no RungStuck while the rebate waits");
        (uint256 kept,) = _rungAt(_epoch(1));
        assertEq(kept, id1, "matured rung kept");
        assertEq(ve.ownerOf(id1), address(sleeve), "still the sleeve's");
        assertEq(fees.earned(address(musd), id1), 0, "its fees still claimed");
        assertEq(ISavings(savings).balanceOf(address(vault)) - parked, fee1 + fee2, "fees parked");
        uint256 principal = sleeve.principal();
        assertGe(principal, amt1, "principal still counts it");

        _mezoRebates();
        uint256 rebate1 = distributor.claimable(id1);
        assertGt(rebate1, 0, "rebate claimable after the update");
        uint256 idle = address(vault).balance;
        vm.warp(block.timestamp + 1 hours);
        _roll(keeper);
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "released after the update");
        assertEq(ve.ownerOf(id1), address(0), "burned");
        assertEq(distributor.claimable(id1), 0, "rebate claimed first");
        (, uint256 amt3) = _rungAt(_epoch(3));
        assertEq(address(vault).balance, idle + amt1 + rebate1 - amt3, "BTC and rebate back");

        emit log_named_uint("held rung BTC", amt1);
        emit log_named_uint("its fees while held MUSD", fee1);
        emit log_named_uint("rebate after the update BTC", rebate1);
    }

    function test_4b_releasedAfterClaimGrace() public {
        _bootstrap(2, 1 ether);
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        _nextWeek(1, false);
        _roll(keeper);
        (uint256 kept,) = _rungAt(_epoch(1));
        assertEq(kept, id1, "kept inside the grace");

        // Still no update a day after the rung's end
        vm.warp(_epoch(1) + 1 days - 1);
        _roll(keeper);
        (kept,) = _rungAt(_epoch(1));
        assertEq(kept, id1, "kept one second before the grace ends");

        uint256 idle = address(vault).balance;
        uint256 principal = sleeve.principal();
        vm.warp(_epoch(1) + 1 days);
        vm.recordLogs();
        _roll(keeper);
        (uint256 stuck,) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 0, "no RungStuck");
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "released once the grace is over");
        assertEq(ve.ownerOf(id1), address(0), "burned");
        assertEq(chainFee.activePeriod(), E0, "period still not updated");
        (, uint256 amt3) = _rungAt(_epoch(3));
        assertEq(sleeve.principal(), principal - amt1 + amt3, "principal drops by the rung");
        assertEq(address(vault).balance, idle + amt1 - amt3, "principal back, rebate forfeited");
        // Once Mezo updates the period, the burned rung's last week shows what was given up
        _mezoRebates();
        emit log_named_uint("released without rebate BTC", amt1);
        emit log_named_uint("forfeited rebate BTC", distributor.claimable(id1));
    }

    /* 5. Gauge killed by the emergency council */

    function test_5_gaugeKilled() public {
        _bootstrap(2, 1 ether);
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        (uint256 id2, uint256 amt2) = _rungAt(_epoch(2));
        vm.prank(team);
        voter.killGauge(gauge);
        assertFalse(sleeve.live(), "live reads the kill");
        assertTrue(sleeve.liveAtRoll(), "not seen before a roll");

        _nextWeek(1, true);
        uint256 idle = address(vault).balance;
        _roll(keeper);
        assertFalse(sleeve.liveAtRoll(), "roll saw the kill");
        assertEq(sleeve.hold(vault.rawAssets()), 0, "hold is 0");
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "matured rung still reset and withdrawn");
        assertEq(ve.ownerOf(id1), address(0), "burned");
        (uint256[] memory ids,,) = _rungs();
        assertEq(ids.length, 1, "no new lock");
        assertEq(ids[0], id2, "live rung kept");
        assertEq(sleeve.principal(), amt2, "principal is the live rung");
        assertGt(address(vault).balance, idle + amt1 - 1, "released BTC is idle");

        vm.prank(team);
        voter.reviveGauge(gauge);
        vm.warp(block.timestamp + 1 hours);
        _roll(keeper);
        assertTrue(sleeve.liveAtRoll(), "roll saw the revival");
        (uint256 id3, uint256 amt3) = _rungAt(_epoch(3));
        assertGt(id3, 0, "locks again after the revival");
        _assertVotesForGauge(id3);
        assertGt(voter.votes(id2, savings), 0, "live rung kept its votes");
        emit log_named_uint("lock after revival BTC", amt3);
    }

    function test_5b_gaugeKilledAndPaused() public {
        _bootstrap(2, 1 ether);
        vm.prank(team);
        voter.killGauge(gauge);
        // The keeper's watch stops new locks, only the owner may resume them
        vm.prank(guardian);
        sleeve.setPaused(true);

        _nextWeek(1, true);
        _roll(keeper);
        assertFalse(sleeve.liveAtRoll(), "kill seen");
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "matured rung withdrawn while killed and paused");

        vm.prank(team);
        voter.reviveGauge(gauge);
        vm.warp(block.timestamp + 1 hours);
        _roll(keeper);
        assertTrue(sleeve.liveAtRoll(), "revival seen");
        assertEq(sleeve.hold(vault.rawAssets()), 0, "paused, still no hold");
        (uint256 none,) = _rungAt(_epoch(3));
        assertEq(none, 0, "no lock while paused");

        vm.prank(keeper);
        vm.expectRevert(bytes4(keccak256("NotAllowed()")));
        sleeve.setPaused(false);
        sleeve.setPaused(false);
        vm.warp(block.timestamp + 1 hours);
        _roll(keeper);
        (uint256 id3, uint256 amt3) = _rungAt(_epoch(3));
        assertGt(id3, 0, "locks after the owner unpauses");
        _assertVotesForGauge(id3);
        emit log_named_uint("lock after unpause BTC", amt3);
    }

    // A stranger's poke drops a rung's votes while the gauge is dead, the next roll votes again
    function test_5c_revoteAfterPokeOnKilledGauge() public {
        _bootstrap(2, 1 ether);
        (uint256 id2,) = _rungAt(_epoch(2));
        vm.prank(team);
        voter.killGauge(gauge);
        vm.prank(stranger);
        voter.poke(id2);
        assertEq(voter.votes(id2, savings), 0, "poke on a dead gauge cleared the votes");
        assertFalse(ve.voted(id2), "and the voted flag");
        vm.prank(team);
        voter.reviveGauge(gauge);

        _nextWeek(1, true);
        _roll(keeper);
        _assertVotesForGauge(id2);
        assertEq(voter.lastVoted(id2), block.timestamp, "voted again in this roll");
        assertEq(voter.votes(id2, savings), ve.votingPowerOfNFT(id2), "at today's power");
        emit log_named_uint("re-vote weight", voter.votes(id2, savings));
    }

    /* 6. Voter swap by the team */

    function test_6_voterSwap() public {
        _bootstrap(2, 1 ether);
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        (uint256 id2, uint256 amt2) = _rungAt(_epoch(2));
        address newVoter = _newVoter();
        vm.prank(team);
        ve.setVoterAndDistributor(newVoter, address(distributor));
        assertFalse(sleeve.live(), "live reads the swap");

        _nextWeek(1, true);
        uint256 fee1 = fees.earned(address(musd), id1);
        uint256 fee2 = fees.earned(address(musd), id2);
        uint256 rebate1 = distributor.claimable(id1);
        assertGt(fee1, 0, "fees to claim");
        assertGt(rebate1, 0, "rebate to claim");
        uint256 idle = address(vault).balance;
        uint256 parked = ISavings(savings).balanceOf(address(vault));
        vm.prank(address(voter));
        vm.expectRevert(bytes4(keccak256("NotVoter()")));
        ve.voting(id1, false);

        vm.recordLogs();
        _roll(keeper);
        (uint256 stuck, uint256 stuckId) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 1, "one RungStuck");
        assertEq(stuckId, id1, "for the matured rung");
        (uint256 kept,) = _rungAt(_epoch(1));
        assertEq(kept, id1, "stuck rung kept");
        assertTrue(ve.voted(id1), "old voter could not clear the flag");
        assertEq(fees.earned(address(musd), id1), 0, "its fees claimed");
        assertEq(distributor.claimable(id1), 0, "its rebate claimed");
        assertEq(ISavings(savings).balanceOf(address(vault)) - parked, fee1 + fee2, "fees parked");
        assertEq(address(vault).balance, idle + rebate1, "rebate reached the vault");
        (uint256 still,) = _rungAt(_epoch(2));
        assertEq(still, id2, "other rung unaffected");
        assertGt(voter.votes(id2, savings), 0, "other rung keeps its votes");
        assertFalse(sleeve.liveAtRoll(), "roll saw the swap");
        assertEq(sleeve.principal(), amt1 + amt2, "no new lock, nothing released");

        // Mezo adds the old voter back as a secondary voter
        vm.prank(team);
        ve.addSecondaryVoter(address(voter));
        vm.warp(block.timestamp + 1 hours);
        idle = address(vault).balance;
        vm.recordLogs();
        _roll(keeper);
        (stuck,) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 0, "no RungStuck after the fix");
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "released");
        assertEq(ve.ownerOf(id1), address(0), "burned");
        assertEq(sleeve.principal(), amt2, "principal drops by the rung");
        assertEq(address(vault).balance, idle + amt1, "BTC back, no new lock after a swap");
        assertFalse(sleeve.live(), "sleeve stays closed to new locks");
    }

    /* 7. Queue */

    function test_7_queue() public {
        _bootstrap(2, 4 ether);
        (, uint256 amt1) = _rungAt(_epoch(1));
        _depositBTC(carol, 1 ether);
        vault.rebalance();

        uint256 idle = address(vault).balance;
        uint256 shares = vault.convertToShares(idle + 0.1 ether);
        assertLt(idle, vault.convertToAssets(shares), "request is more than the vault holds idle");
        vm.prank(alice);
        uint256 rid = queue.requestRedeem(shares, alice, alice);
        uint256 hold = sleeve.hold(vault.rawAssets());
        assertGt(hold, MIN_RUNG, "a lock would follow without the request");

        vm.recordLogs();
        _roll(keeper);
        uint256 firstFill = _fillsOf(vm.getRecordedLogs());
        assertGt(firstFill, 0, "roll filled from idle");
        assertGt(queue.pending(), 0, "the rest waits");
        (uint256[] memory ids,,) = _rungs();
        assertEq(ids.length, 2, "no new lock while a request waits");

        uint256 paid = queue.claimableRedeem(rid);
        uint256 before = alice.balance;
        uint256[] memory list = new uint256[](1);
        list[0] = rid;
        queue.claim(list);
        assertEq(alice.balance - before, paid, "claim pays the first fill");
        assertEq(paid, firstFill, "all of it");

        _nextWeek(1, true);
        uint256 waiting = queue.pending();
        vm.recordLogs();
        _roll(keeper);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 secondFill = _fillsOf(logs);
        assertEq(queue.pending(), 0, "matured BTC filled the queue");
        assertGt(secondFill, 0, "second fill");
        assertLt(secondFill, amt1, "out of the released rung");
        (uint256 id3, uint256 amt3) = _rungAt(_epoch(3));
        assertGt(id3, 0, "re-lock only after the queue is empty");
        _assertVotesForGauge(id3);

        before = alice.balance;
        queue.claim(list);
        assertEq(alice.balance - before, secondFill, "claim pays the second fill");
        assertEq(queue.pendingRedeem(rid), 0, "request done");
        emit log_named_uint("request shares", shares);
        emit log_named_uint("waiting after first fill shares", waiting);
        emit log_named_uint("first fill BTC", firstFill);
        emit log_named_uint("second fill BTC", secondFill);
        emit log_named_uint("re-lock BTC", amt3);
    }

    /* 8. A four week ladder */

    function test_8_ladder() public {
        sleeve.setSleeve(2500, type(uint256).max, 4);
        uint256[6] memory gas;
        uint256[6] memory calls;
        for (uint256 k; k < 5; k++) {
            if (k > 0) _nextWeek(k, true);
            if (k < 4) {
                _depositBTC(alice, 1 ether);
                vault.rebalance();
            }
            (gas[k], calls[k]) = _measuredRoll(keeper, 0);
            (uint256[] memory ids,, uint256[] memory ends) = _rungs();
            emit log_named_uint("week", k);
            emit log_named_uint("  roll gas", gas[k]);
            emit log_named_uint("  precompile calls", calls[k]);
            emit log_named_uint("  rungs", ids.length);
            emit log_named_uint("  principal", sleeve.principal());
            uint256 start = _epoch(k);
            if (k == 0) {
                assertEq(ids.length, 2, "two new rungs at most");
                (uint256 three,) = _rungAt(start + 3 * WEEK);
                (uint256 four,) = _rungAt(start + 4 * WEEK);
                assertGt(three, 0, "three weeks");
                assertGt(four, 0, "four weeks");
            } else {
                assertEq(ids.length, 4, "full ladder");
                for (uint256 j; j < 4; j++) {
                    assertGt(ends[j], start, "only live rungs");
                    assertLe(ends[j], start + 4 * WEEK, "longest is four weeks");
                }
                (uint256 longest,) = _rungAt(start + 4 * WEEK);
                assertGt(longest, 0, "a new longest rung every week");
            }
            for (uint256 j; j < ids.length; j++) {
                _assertVotesForGauge(ids[j]);
            }
            assertLe(calls[k], 20, "under Mezo's precompile limit");
        }

        // A deposit after the week's roll fills no slot, so the longest rung is topped up
        (uint256 top, uint256 topBefore) = _rungAt(_epoch(4) + 4 * WEEK);
        _depositBTC(bob, 1 ether);
        vault.rebalance();
        (gas[5], calls[5]) = _measuredRoll(keeper, 0);
        (, uint256 topAfter) = _rungAt(_epoch(4) + 4 * WEEK);
        assertGt(topAfter, topBefore, "longest rung topped up");
        assertEq(uint256(int256(ve.locked(top).amount)), topAfter, "increaseAmount in veBTC");
        assertEq(voter.votes(top, savings), ve.votingPowerOfNFT(top), "poke moved the votes");
        emit log_named_uint("top-up roll gas", gas[5]);
        emit log_named_uint("top-up precompile calls", calls[5]);
        assertLe(calls[5], 20, "top-up under the precompile limit");
    }

    function test_8b_gapThreeWeeks() public {
        _ladder();
        // The keeper misses the rolls of weeks 5, 6 and 7, Mezo keeps its weekly routine
        for (uint256 k = 5; k < 8; k++) {
            _nextWeek(k, true);
        }
        (uint256 live,) = _rungAt(_epoch(8));
        uint256 rebate = distributor.claimable(live);
        assertGt(rebate, 0, "three weeks of rebate on the live rung");
        _gapRoll(_epoch(7), 3);

        // Its depositFor was veBTC's first write in three weeks and ran out of CLAIM_GAS
        assertEq(distributor.claimable(live), rebate, "skipped in the gap roll, not lost");
        uint256 lockedBefore = uint256(int256(ve.locked(live).amount));
        vm.warp(block.timestamp + 1 hours);
        _roll(keeper);
        assertEq(distributor.claimable(live), 0, "claimed on the next roll");
        assertEq(uint256(int256(ve.locked(live).amount)), lockedBefore + rebate, "compounded");
        emit log_named_uint("live rung rebate retried BTC", rebate);
    }

    function test_8c_gapFourMatured() public {
        _ladder();
        // Weeks 5 to 8 without a roll, every rung of the ladder has matured
        for (uint256 k = 5; k < 9; k++) {
            _nextWeek(k, true);
        }
        _gapRoll(_epoch(8), 4);
    }

    function _ladder() internal {
        sleeve.setSleeve(2500, type(uint256).max, 4);
        for (uint256 k; k < 5; k++) {
            if (k > 0) _nextWeek(k, true);
            if (k < 4) {
                _depositBTC(alice, 1 ether);
                vault.rebalance();
            }
            _roll(keeper);
        }
        (uint256[] memory ids,,) = _rungs();
        assertEq(ids.length, 4, "steady ladder");
    }

    function _gapRoll(uint256 start, uint256 matured) internal {
        (uint256[] memory ids,, uint256[] memory ends) = _rungs();
        uint256 due;
        for (uint256 j; j < ids.length; j++) {
            if (ends[j] <= block.timestamp) due++;
        }
        assertEq(due, matured, "matured rungs");
        vm.recordLogs();
        (uint256 gas, uint256 calls) = _measuredRoll(keeper, 10_000_000);
        (uint256 stuck,) = _stuckIds(vm.getRecordedLogs());
        assertEq(stuck, 0, "nothing stuck on a 10M limit");
        (uint256[] memory after_,, uint256[] memory endsAfter) = _rungs();
        for (uint256 j; j < after_.length; j++) {
            assertGt(endsAfter[j], block.timestamp, "every matured rung released");
            _assertVotesForGauge(after_[j]);
        }
        for (uint256 j; j < ids.length; j++) {
            if (ends[j] <= start) assertEq(ve.ownerOf(ids[j]), address(0), "burned");
        }
        (uint256 longest,) = _rungAt(start + 4 * WEEK);
        assertGt(longest, 0, "re-locked into the longest slot");
        assertLt(gas, 10_000_000, "fits under 10M gas");
        assertLe(calls, 20, "under Mezo's precompile limit");
        emit log_named_uint("matured rungs", matured);
        emit log_named_uint("gap roll gas", gas);
        emit log_named_uint("gap roll precompile calls", calls);
        emit log_named_uint("rungs after", after_.length);
    }

    // Gas of one roll and its precompile calls as Mezo counts them, BTC calls and two per price
    function _measuredRoll(address caller, uint256 limit)
        internal
        returns (uint256 gas, uint256 calls)
    {
        vm.startStateDiffRecording();
        vm.prank(caller);
        uint256 before = gasleft();
        if (limit == 0) vault.roll();
        else vault.roll{gas: limit}();
        gas = before - gasleft();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        (uint256 btcCalls, uint256 oracleCalls) = _precompiles(accesses);
        calls = btcCalls + oracleCalls;
    }

    /* 10. A full instant exit while MUSD owed exceeds MUSD held */

    function test_10_maxExitWithMusdGap() public {
        _setRate(200);
        _bootstrap(2, 1 ether);
        // Six weeks of interest with no yield and no roll
        vm.warp(block.timestamp + 6 weeks);
        uint256 owed = vault.trove().debt - GAS_COMP;
        uint256 held = vault.savingsValue() + musd.balanceOf(address(vault));
        assertGt(owed, held, "MUSD gap open");
        uint256 total = vault.totalAssets();
        uint256 max = vault.maxWithdraw(alice);
        uint256 liquidBtc = address(vault).balance + vault.trove().coll;
        assertEq(max, total - sleeve.principal(), "everything but the sleeve");
        assertLt(max, liquidBtc, "the BTC that buys the MUSD gap stays behind");

        uint256 before = alice.balance;
        vm.prank(alice);
        vault.withdraw(max, alice, alice);
        assertEq(alice.balance - before, max, "paid the whole instant maximum");
        assertFalse(vault.trove().active, "the exit closed the trove");
        emit log_named_uint("MUSD gap", owed - held);
        emit log_named_uint("idle plus trove BTC", liquidBtc);
        emit log_named_uint("maxWithdraw", max);
        emit log_named_uint("totalAssets", total);
        emit log_named_uint("sleeve principal", sleeve.principal());
    }

    /* 9. Stranger and keeper */

    function test_9_strangerAndKeeper() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        _roll(stranger);
        (uint256[] memory ids,,) = _rungs();
        assertEq(ids.length, 0, "a stranger's roll never locks");
        assertEq(sleeve.principal(), 0, "no principal");
        _roll(keeper);
        (ids,,) = _rungs();
        assertEq(ids.length, 2, "the keeper's roll locks");
        (uint256 id1, uint256 amt1) = _rungAt(_epoch(1));
        (uint256 id2, uint256 amt2) = _rungAt(_epoch(2));

        // A request the vault cannot pay from idle waits for the rung
        uint256 shares = vault.convertToShares(address(vault).balance + amt1 / 2);
        vm.prank(alice);
        queue.requestRedeem(shares, alice, alice);
        _nextWeek(1, true);
        uint256 waiting = queue.pending();
        assertGt(waiting, 0, "request waits");
        vm.recordLogs();
        _roll(stranger);
        uint256 filled = _fillsOf(vm.getRecordedLogs());
        assertGt(filled, 0, "stranger's roll fills the queue");
        assertEq(queue.pending(), 0, "filled from the matured rung");
        (uint256 gone,) = _rungAt(_epoch(1));
        assertEq(gone, 0, "stranger's roll collects");
        assertEq(ve.ownerOf(id1), address(0), "burned");
        (ids,,) = _rungs();
        assertEq(ids.length, 1, "but locks nothing");
        assertEq(sleeve.principal(), amt2, "principal is the live rung");
        assertGt(sleeve.hold(vault.rawAssets()), MIN_RUNG, "there was BTC to lock");

        _roll(keeper);
        (uint256 id3, uint256 amt3) = _rungAt(_epoch(3));
        assertGt(id3, 0, "the keeper's roll locks it");
        _assertVotesForGauge(id3);
        assertEq(ve.ownerOf(id2), address(sleeve), "live rung untouched");
        emit log_named_uint("stranger fill BTC", filled);
        emit log_named_uint("keeper re-lock BTC", amt3);
    }
}
