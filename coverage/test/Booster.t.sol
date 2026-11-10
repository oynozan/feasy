// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Booster, IBoostedVault} from "vault/Booster.sol";
import {VeSleeve} from "vault/VeSleeve.sol";
import {IBoostVoter} from "vault/interfaces/IMezo.sol";
import {SleeveBase, IEarnVe} from "./SleeveBase.sol";

// The vault's booster on a second veMEZO and BoostVoter that lock a tigris LP token for MEZO
contract BoosterTest is SleeveBase {
    Booster vaultBooster;

    // Two rungs of the new vault vote for the sMUSD gauge, veBTC now boosts through the LP stack
    function _setUpLp() internal {
        _lpEarn();
        _lpVault();
        vaultBooster = new Booster(IBoostedVault(address(vault)));
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        _roll(keeper);
        (uint256[] memory ids,,) = _rungs();
        assertEq(ids.length, 2, "two rungs");
    }

    function _giveLp(uint256 amount) internal {
        vm.prank(whale);
        IERC20(lp).transfer(address(vaultBooster), amount);
    }

    function _gauges() internal {
        for (uint256 i; i < 4; i++) {
            (uint256 id,,) = sleeve.rungs(i);
            if (id == 0) continue;
            vm.prank(stranger);
            address g = sleeve.addBoostGauge(i, gaugeFactory);
            assertEq(IBoostVoter(lpBooster).boostableTokenIdToGauge(id), g, "gauge of the rung");
        }
    }

    // Testnet's stack, where the booster reaches the MEZO precompile through veMEZO
    function test_wiringOnTestnetStack() public {
        Booster b = new Booster(IBoostedVault(address(vault)));
        assertEq(address(b.vault()), address(vault));
        assertEq(address(b.sleeve()), address(sleeve));
        assertEq(address(b.voter()), address(voter));
        assertEq(address(b.boostVoter()), booster);
        assertEq(address(b.veMezo()), veMezo);
        assertEq(address(b.mezo()), MEZO);
        assertEq(b.veMezoId(), 0);
    }

    function test_lockIntoOnePermanentLock() public {
        _setUpLp();
        assertEq(address(vaultBooster.mezo()), lp);
        _giveLp(5e18);
        vm.prank(stranger);
        vm.expectRevert(Booster.NotAllowed.selector);
        vaultBooster.lock();

        vm.expectEmit(address(vaultBooster));
        emit Booster.Locked(1, 5e18);
        vm.prank(keeper);
        vaultBooster.lock();
        uint256 id = vaultBooster.veMezoId();
        IEarnVe.LockedBalance memory l = IEarnVe(lpVe).locked(id);
        assertEq(uint256(int256(l.amount)), 5e18);
        assertTrue(l.isPermanent, "never decays");
        assertEq(IEarnVe(lpVe).ownerOf(id), address(vaultBooster));
        assertEq(IERC20(lp).balanceOf(address(vaultBooster)), 0);

        _giveLp(2e18);
        vaultBooster.lock();
        assertEq(vaultBooster.veMezoId(), id, "the same lock grows");
        assertEq(uint256(int256(IEarnVe(lpVe).locked(id).amount)), 7e18);
        vaultBooster.lock();
        assertEq(uint256(int256(IEarnVe(lpVe).locked(id).amount)), 7e18, "nothing to add");
    }

    function test_boostRaisesRungWeight() public {
        _setUpLp();
        (uint256[] memory ids,,) = _rungs();
        _gauges();
        vm.expectRevert(VeSleeve.BadSleeve.selector);
        sleeve.addBoostGauge(0, gaugeFactory);
        _giveLp(100e18);
        vm.prank(keeper);
        vaultBooster.lock();

        uint256[] memory power = new uint256[](2);
        uint256[] memory weight = new uint256[](2);
        for (uint256 k; k < 2; k++) {
            power[k] = ve.votingPowerOfNFT(ids[k]);
            weight[k] = voter.votes(ids[k], savings);
            assertEq(weight[k], power[k], "full power on the sMUSD gauge");
        }
        vm.prank(keeper);
        vaultBooster.boost();
        for (uint256 k; k < 2; k++) {
            assertEq(IBoostVoter(lpBooster).getBoost(ids[k]), 5e18, "the 5x cap");
            uint256 boosted = ve.votingPowerOfNFT(ids[k]);
            assertApproxEqRel(boosted, power[k] * 5, 1e12, "veBTC power at 5x");
            assertEq(voter.votes(ids[k], savings), boosted, "the Voter weight follows");
            assertGt(voter.votes(ids[k], savings), weight[k]);
        }

        // Mezo allows one veMEZO vote an epoch
        vm.prank(keeper);
        vm.expectRevert();
        vaultBooster.boost();
    }

    // A rung released at maturity loses its gauge, the next epoch's boost covers the live ones
    function test_boostNextEpoch() public {
        _setUpLp();
        _gauges();
        _giveLp(100e18);
        vaultBooster.lock();
        vaultBooster.boost();
        (uint256 matured,) = _rungAt(_epoch(1));
        (uint256 live,) = _rungAt(_epoch(2));

        vm.warp(_epoch(1) + 1 minutes);
        _mezoWeek(true);
        vm.warp(_epoch(1) + 1 hours + 1);
        _roll(keeper);
        assertEq(IBoostVoter(lpBooster).boostableTokenIdToGauge(matured), address(0), "burned");
        vaultBooster.boost();
        assertEq(IBoostVoter(lpBooster).getBoost(live), 5e18, "the live rung keeps the boost");
        assertEq(voter.votes(live, savings), ve.votingPowerOfNFT(live));
    }

    // A matured rung still waiting for its rebate is skipped, the live rung is boosted
    function test_maturedRungSkippedByBoost() public {
        _setUpLp();
        _gauges();
        _giveLp(100e18);
        vaultBooster.lock();
        vaultBooster.boost();
        (uint256 matured,) = _rungAt(_epoch(1));
        (uint256 live,) = _rungAt(_epoch(2));

        // Mezo's rebate period update is late, so the roll keeps the matured rung in its slot
        vm.warp(_epoch(1) + 1 minutes);
        _mezoWeek(false);
        vm.warp(_epoch(1) + 1 hours + 1);
        _roll(keeper);
        (uint256 kept,) = _rungAt(_epoch(1));
        assertEq(kept, matured, "the matured rung waits inside the claim grace");

        uint256 power = ve.votingPowerOfNFT(live);
        vm.prank(keeper);
        vaultBooster.boost();
        assertEq(IBoostVoter(lpBooster).getBoost(live), 5e18, "the live rung boosted again");
        assertEq(voter.votes(live, savings), ve.votingPowerOfNFT(live), "its Voter weight follows");
        assertGe(ve.votingPowerOfNFT(live), power);
    }

    function test_boostSkipsWithoutGaugesOrLock() public {
        _setUpLp();
        vm.prank(stranger);
        vm.expectRevert(Booster.NotAllowed.selector);
        vaultBooster.boost();
        vm.prank(keeper);
        vaultBooster.boost();
        _gauges();
        vaultBooster.boost();
        assertEq(vaultBooster.veMezoId(), 0, "no lock, no vote");
    }

    function test_sweepRevenueNotMezo() public {
        _setUpLp();
        vm.prank(alice);
        vault.transfer(address(vaultBooster), 1e20);
        vm.prank(keeper);
        vm.expectRevert(Booster.NotAllowed.selector);
        vaultBooster.sweep(IERC20(address(vault)), keeper, 1e20);
        _giveLp(1e18);
        vm.expectRevert(Booster.NotAllowed.selector);
        vaultBooster.sweep(IERC20(lp), address(this), 1e18);

        vm.expectEmit(address(vaultBooster));
        emit Booster.Swept(address(vault), carol, 1e20);
        vaultBooster.sweep(IERC20(address(vault)), carol, 1e20);
        assertEq(vault.balanceOf(carol), 1e20);
    }

    // Gauge rewards reach the lock through harvestMezo, with nothing sold
    function test_harvestFeedsTheLock() public {
        _setUpLp();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _yield(WEEKLY_YIELD);
        _depositBTC(bob, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active);
        savingsSleeve.setStake(10_000);
        savingsSleeve.setBooster(address(vaultBooster), 10_000);
        _fundLpGauge(10e18);
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        uint256 earned = savingsSleeve.mezoEarned();
        assertGt(earned, 0);
        vm.prank(keeper);
        assertEq(savingsSleeve.harvestMezo(0), 0, "no BTC, all of it boosts");
        assertEq(IERC20(lp).balanceOf(address(vaultBooster)), earned);
        vm.prank(keeper);
        vaultBooster.lock();
        assertEq(uint256(int256(IEarnVe(lpVe).locked(vaultBooster.veMezoId()).amount)), earned);
    }
}
