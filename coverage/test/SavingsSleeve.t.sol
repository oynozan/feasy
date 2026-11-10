// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SavingsSleeve} from "vault/SavingsSleeve.sol";
import {ISavings, IPoolFactory} from "vault/interfaces/IMezo.sol";
import {SleeveBase, IPoolAdmin, IRouterLiquidity} from "./SleeveBase.sol";
import {Base} from "./Base.sol";

interface ISavingsYield {
    function yieldIndex() external view returns (uint256);
    function supplyYieldIndex(address account) external view returns (uint256);
    function claimableYield(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IGaugeView {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
}

// The sleeve on Mezo's sMUSD gauge, whose local Voter pays BTC
contract SavingsSleeveTest is SleeveBase {
    function _open() internal {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
    }

    function _asVault() internal {
        vm.prank(address(vault));
    }

    function test_wiring() public view {
        assertEq(savingsSleeve.vault(), address(vault));
        assertEq(address(savingsSleeve.savings()), savings);
        assertEq(address(savingsSleeve.gauge()), gauge, "the Pools Voter's sMUSD gauge");
        assertEq(address(savingsSleeve.mezo()), BTC, "the local Voter emits BTC");
        assertEq(address(savingsSleeve.musd()), address(musd));
        assertEq(address(savingsSleeve.btc()), BTC);
        assertEq(savingsSleeve.stakeBps(), 0, "nothing staked by default");
        (, uint64 time) = savingsSleeve.snapshots(0);
        assertEq(time, E0 - WEEK + 2 hours, "first snapshot at deployment");
    }

    function test_parkAndPullUnstaked() public {
        _open();
        uint256 parked = _parked();
        assertGt(parked, 0, "the loan's MUSD sits in sMUSD");
        assertEq(savingsSleeve.staked(), 0);
        assertEq(musd.balanceOf(address(savingsSleeve)), 0, "nothing loose");
        assertEq(savingsSleeve.value(), vault.savingsValue());

        _asVault();
        assertEq(savingsSleeve.pull(1000e18), 1000e18);
        assertEq(musd.balanceOf(address(vault)), 1000e18);
        assertEq(_parked(), parked - 1000e18, "out of principal");

        vm.startPrank(address(vault));
        musd.transfer(address(savingsSleeve), 1000e18);
        savingsSleeve.park();
        vm.stopPrank();
        assertEq(_parked(), parked, "parked again");
    }

    // MUSD already loose in the sleeve goes first and leaves sMUSD alone
    function test_pullFromLooseMusd() public {
        _open();
        uint256 parked = _parked();
        vm.prank(whale);
        musd.transfer(address(savingsSleeve), 500e18);
        _asVault();
        savingsSleeve.pull(300e18);
        assertEq(_parked(), parked);
        assertEq(musd.balanceOf(address(savingsSleeve)), 200e18, "the rest stays loose");
        assertEq(savingsSleeve.value(), parked + 200e18, "loose MUSD counts");
    }

    // A pull no larger than the accrued yield claims it and leaves principal untouched
    function test_pullFromYieldOnly() public {
        _open();
        _yield(10_000e18);
        uint256 parked = _parked();
        uint256 accrued = savingsSleeve.value() - parked;
        assertGt(accrued, 0);
        _asVault();
        assertEq(savingsSleeve.pull(accrued), accrued);
        assertEq(_parked(), parked, "principal untouched");
        assertEq(savingsSleeve.value(), parked);
    }

    function test_parkStakesTheShare() public {
        _open();
        uint256 total = _parked();
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.StakeSet(5000);
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.Staked(total / 2);
        savingsSleeve.setStake(5000);
        assertEq(savingsSleeve.staked(), total / 2, "half staked at once");
        assertEq(_parked(), total - total / 2);
        assertEq(savingsSleeve.value(), total, "staked principal still counts");

        // The larger loan's MUSD is staked at the same share on the next park
        _setPrice(130_000e18);
        vault.rebalance();
        uint256 all = _parked() + savingsSleeve.staked();
        assertGt(all, total, "borrowed more");
        assertEq(savingsSleeve.staked(), all / 2);

        // A lower share withdraws the difference
        savingsSleeve.setStake(2000);
        assertEq(savingsSleeve.staked(), all * 2000 / 10_000);
        savingsSleeve.setStake(0);
        assertEq(savingsSleeve.staked(), 0);
        assertEq(_parked(), all);
    }

    function test_valueCountsStakedPrincipalNotItsYield() public {
        _open();
        savingsSleeve.setStake(5000);
        uint256 free = _parked();
        uint256 staked = savingsSleeve.staked();
        uint256 before = savingsSleeve.value();
        assertEq(before, free + staked);
        uint256 gaugeShares = ISavings(savings).balanceOf(gauge);
        uint256 gaugeIndex = ISavingsYield(savings).supplyYieldIndex(gauge);
        uint256 index = ISavingsYield(savings).yieldIndex();

        uint256 rise = 10_000e18 * 1e18 / ISavingsYield(savings).totalSupply();
        _yield(10_000e18);
        assertEq(ISavingsYield(savings).yieldIndex(), index + rise);
        assertEq(savingsSleeve.value() - before, free * rise / 1e18, "only free sMUSD earns here");
        // The staked part's yield accrues to the gauge, which passes it to the gauge's voters
        uint256 gaugeAccrued = gaugeShares * (index + rise - gaugeIndex) / 1e18;
        assertGt(gaugeAccrued, staked * rise / 1e18, "the gauge earns on the vault's stake");
    }

    function test_pullUnstakesWhenFreeIsShort() public {
        _open();
        savingsSleeve.setStake(10_000);
        assertEq(_parked(), 0, "everything staked");
        uint256 staked = savingsSleeve.staked();
        _asVault();
        assertEq(savingsSleeve.pull(5000e18), 5000e18);
        assertEq(savingsSleeve.staked(), staked - 5000e18, "taken out of the gauge");
        assertEq(_parked(), 0);

        // The vault's own exit path reaches staked sMUSD too
        vm.startPrank(address(vault));
        musd.transfer(address(savingsSleeve), 5000e18);
        savingsSleeve.park();
        vm.stopPrank();
        uint256 debt = vault.trove().debt;
        uint256 max = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(max / 2, alice, alice);
        assertLt(vault.trove().debt, debt, "repaid from staked sMUSD");
    }

    // A pull larger than the sleeve sends everything it has
    function test_pullMoreThanHeld() public {
        _open();
        savingsSleeve.setStake(5000);
        uint256 all = savingsSleeve.value();
        _asVault();
        assertEq(savingsSleeve.pull(all + 1e18), all);
        assertEq(savingsSleeve.value(), 0);
        assertEq(savingsSleeve.staked(), 0);
    }

    // With nothing staked a large pull finds nothing in the gauge and sends the free sMUSD
    function test_pullMoreThanHeldUnstaked() public {
        _open();
        uint256 all = savingsSleeve.value();
        _asVault();
        assertEq(savingsSleeve.pull(all * 2), all);
        assertEq(_parked(), 0);
    }

    function test_onlyVaultParksAndPulls() public {
        vm.startPrank(stranger);
        vm.expectRevert(SavingsSleeve.NotVault.selector);
        savingsSleeve.park();
        vm.expectRevert(SavingsSleeve.NotVault.selector);
        savingsSleeve.pull(1);
        vm.stopPrank();
    }

    function test_setStakePermissions() public {
        address[3] memory others = [guardian, keeper, stranger];
        for (uint256 i; i < 3; i++) {
            vm.prank(others[i]);
            vm.expectRevert(SavingsSleeve.NotAllowed.selector);
            savingsSleeve.setStake(5000);
        }
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setStake(10_001);
        savingsSleeve.setStake(10_000);
        assertEq(savingsSleeve.stakeBps(), 10_000);
    }

    function test_unstakePermissions() public {
        _open();
        savingsSleeve.setStake(5000);
        vm.prank(keeper);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.unstake();
        vm.prank(stranger);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.unstake();

        uint256 all = savingsSleeve.value();
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.StakeSet(0);
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.Staked(0);
        vm.prank(guardian);
        savingsSleeve.unstake();
        assertEq(savingsSleeve.staked(), 0, "the guardian takes it all out");
        assertEq(savingsSleeve.stakeBps(), 0);
        assertEq(_parked(), all);
        vault.rebalance();
        assertEq(savingsSleeve.staked(), 0, "and it stays out");

        // Only the owner stakes again, and may also unstake with nothing staked
        savingsSleeve.setStake(5000);
        savingsSleeve.unstake();
        savingsSleeve.unstake();
        assertEq(savingsSleeve.staked(), 0);
    }

    function test_killedGaugeLeavesSmusdUnstaked() public {
        _open();
        vm.prank(team);
        voter.killGauge(gauge);
        savingsSleeve.setStake(5000);
        assertEq(savingsSleeve.staked(), 0, "the dead gauge refuses the deposit");
        assertEq(IERC20(savings).allowance(address(savingsSleeve), gauge), 0, "no allowance left");
        _setPrice(130_000e18);
        vault.rebalance();
        assertEq(savingsSleeve.staked(), 0, "park still runs");
        assertGt(_parked(), 0);

        vm.prank(team);
        voter.reviveGauge(gauge);
        vault.rebalance();
        assertApproxEqAbs(savingsSleeve.staked(), _parked(), 1, "staked on the next park");
    }

    function test_harvestMezoRoles() public {
        address[2] memory others = [guardian, stranger];
        for (uint256 i; i < 2; i++) {
            vm.prank(others[i]);
            vm.expectRevert(SavingsSleeve.NotAllowed.selector);
            savingsSleeve.harvestMezo(0);
        }
        vm.prank(keeper);
        assertEq(savingsSleeve.harvestMezo(0), 0, "nothing earned");
        assertEq(savingsSleeve.harvestMezo(0), 0, "the owner may too");
    }

    function test_setBoosterChecks() public {
        vm.prank(keeper);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setBooster(keeper, 100);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setBooster(keeper, 10_001);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setBooster(address(0), 1);
        savingsSleeve.setBooster(address(0), 0);
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.BoosterSet(carol, 2500);
        savingsSleeve.setBooster(carol, 2500);
        assertEq(savingsSleeve.booster(), carol);
        assertEq(savingsSleeve.boostBps(), 2500);
    }
}

// The sleeve on a second Voter whose sMUSD gauge pays a tigris LP token in MEZO's place
contract SavingsSleeveMezoTest is SleeveBase {
    address lpMusd;

    function setUp() public override {
        super.setUp();
        _lpEarn();
        _lpVault();
        // A day of sMUSD history for the new sleeve, with a week of Mezo's yield in it
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _yield(WEEKLY_YIELD);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active);
        savingsSleeve.setStake(10_000);
        assertGt(savingsSleeve.staked(), 0, "staked in the LP gauge");

        // An LP and MUSD pool, the reward has no BTC pair yet
        lpMusd = _pairWith(address(musd), 1000e18, 2000e18);
        _fundLpGauge(100e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _pairWith(address token, uint256 lpAmount, uint256 tokenAmount)
        internal
        returns (address pair)
    {
        pair = IPoolAdmin(factory).createPool(lp, token, false);
        vm.startPrank(whale);
        IERC20(lp).approve(address(router), lpAmount);
        IERC20(token).approve(address(router), tokenAmount);
        IRouterLiquidity(address(router))
            .addLiquidity(
                lp, token, false, lpAmount, tokenAmount, 0, 0, whale, vm.getBlockTimestamp()
            );
        vm.stopPrank();
    }

    function test_wiring() public view {
        assertEq(address(savingsSleeve.gauge()), lpGauge);
        assertEq(address(savingsSleeve.mezo()), lp, "the gauge's reward token");
        assertEq(IPoolFactory(factory).getPool(lp, BTC, false), address(0), "no direct pair");
    }

    function test_harvestMezoThroughMusd() public {
        uint256 earned = savingsSleeve.mezoEarned();
        assertGt(earned, 0, "the stake earned the gauge's reward");
        uint256 idle = address(vault).balance;
        uint256 pairLp = IERC20(lp).balanceOf(lpMusd);
        vm.expectEmit(false, false, false, false, address(savingsSleeve));
        emit SavingsSleeve.MezoHarvested(0, 0);
        vm.prank(keeper);
        uint256 out = savingsSleeve.harvestMezo(1);
        assertGt(out, 0);
        assertEq(address(vault).balance, idle + out, "BTC goes straight to the vault");
        assertEq(IERC20(lp).balanceOf(address(savingsSleeve)), 0, "no reward stays behind");
        assertGt(IERC20(lp).balanceOf(lpMusd), pairLp, "sold through the MUSD pair");
        assertEq(savingsSleeve.mezoEarned(), 0);
        assertEq(musd.balanceOf(address(savingsSleeve)), 0, "the MUSD leg passed through");
    }

    function test_harvestMezoDirectPair() public {
        address lpBtc = _pairWith(BTC, 1000e18, 0.02 ether);
        uint256 pairLp = IERC20(lp).balanceOf(lpMusd);
        uint256 directLp = IERC20(lp).balanceOf(lpBtc);
        vm.prank(keeper);
        uint256 out = savingsSleeve.harvestMezo(1);
        assertGt(out, 0);
        assertGt(IERC20(lp).balanceOf(lpBtc), directLp, "sold on the BTC pair");
        assertEq(IERC20(lp).balanceOf(lpMusd), pairLp, "the MUSD pair untouched");
    }

    function test_harvestMezoFloor() public {
        vm.prank(keeper);
        vm.expectRevert();
        savingsSleeve.harvestMezo(1000 ether);
    }

    function test_harvestMezoBoostShare() public {
        savingsSleeve.setBooster(carol, 2500);
        uint256 quarter = savingsSleeve.mezoEarned() / 4;
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.MezoBoosted(quarter);
        uint256 out = savingsSleeve.harvestMezo(1);
        assertEq(IERC20(lp).balanceOf(carol), quarter, "a quarter to the booster");
        assertGt(out, 0, "the rest sold");

        // With the whole share boosted nothing is sold
        savingsSleeve.setBooster(carol, 10_000);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        uint256 earned = savingsSleeve.mezoEarned();
        uint256 idle = address(vault).balance;
        assertEq(savingsSleeve.harvestMezo(1), 0);
        assertEq(IERC20(lp).balanceOf(carol), quarter + earned);
        assertEq(address(vault).balance, idle, "no swap");
    }
}

// A vault deployed without a voter has a sleeve that only saves and measures
contract SavingsSleeveNoGaugeTest is Base {
    function test_noGauge() public {
        vm.prank(address(vault));
        assertEq(savingsSleeve.pull(1e18), 0, "an empty sleeve sends nothing");
        assertEq(address(savingsSleeve.gauge()), address(0));
        assertEq(address(savingsSleeve.mezo()), address(0));
        assertEq(savingsSleeve.staked(), 0);
        assertEq(savingsSleeve.mezoEarned(), 0);
        vm.prank(keeper);
        assertEq(savingsSleeve.harvestMezo(0), 0);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        savingsSleeve.setStake(5000);
        assertEq(savingsSleeve.staked(), 0, "nowhere to stake");
        assertEq(_parked(), savingsSleeve.value(), "all of it saved");
        savingsSleeve.unstake();
        vm.prank(address(vault));
        savingsSleeve.pull(1000e18);
        assertEq(musd.balanceOf(address(vault)), 1000e18);
    }
}
