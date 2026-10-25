// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultTroveTest is Base {
    function _open(uint256 amount) internal {
        _depositBTC(alice, amount);
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
    }

    function test_openAtTargetAndBuyBack() public {
        _depositBTC(alice, 2 ether);
        vm.expectEmit(false, false, false, false, address(vault));
        emit Vault.ShortfallBought(0, 0);
        vault.rebalance();
        assertApproxEqRel(_ratio(), 2.5e18, 1e15);
        assertGe(vault.savingsValue(), vault.trove().debt - GAS_COMP, "fee bought back");
        assertEq(btc.balanceOf(address(vault)), address(vault).balance);
    }

    function test_noOpenBelowRoom() public {
        _depositBTC(alice, 0.05 ether);
        vault.rebalance();
        assertFalse(vault.trove().active, "too small for the minimum loan");
    }

    function test_noOpenWhenRateTooHigh() public {
        _setRate(201);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertFalse(vault.trove().active);
    }

    function test_bandRepayAndBorrow() public {
        _open(2 ether);
        uint256 debt = vault.trove().debt;
        _setPrice(75_000e18);
        vault.rebalance();
        assertLt(vault.trove().debt, debt, "repaid from savings");
        assertApproxEqRel(_ratio(), 2.5e18, 1e16);

        _setPrice(130_000e18);
        vault.rebalance();
        assertApproxEqRel(_ratio(), 2.5e18, 1e16, "borrowed back to target");
    }

    function test_inBandAddsSpareOrNothing() public {
        _open(2 ether);
        Vault.Trove memory t = vault.trove();
        vault.rebalance();
        assertEq(vault.trove().coll, t.coll, "nothing to do");
        _depositBTC(bob, 0.2 ether);
        vault.rebalance();
        assertGt(vault.trove().coll, t.coll, "spare collateral added");
    }

    function test_aboveBandWithBorrowingOff() public {
        _open(2 ether);
        vault.setBorrowingEnabled(false);
        _setPrice(130_000e18);
        uint256 debt = vault.trove().debt;
        vault.rebalance();
        assertEq(vault.trove().debt, debt, "no new debt");
        _depositBTC(bob, 0.5 ether);
        vault.rebalance();
        assertEq(vault.trove().debt, debt, "still no new debt");
    }

    function test_refinanceWhenCapped() public {
        _open(2 ether);
        _depositBTC(bob, 1 ether);
        _setPrice(300_000e18);
        vault.rebalance();
        assertApproxEqRel(_ratio(), 2.5e18, 1e16, "refinanced and borrowed to target");
        assertGt(tm.getTroveMaxBorrowingCapacity(address(vault)), 400_000e18);
    }

    function test_refinanceWithoutSpare() public {
        _open(2 ether);
        _setPrice(300_000e18);
        vault.rebalance();
        assertApproxEqRel(_ratio(), 2.5e18, 1e16);
    }

    function test_cappedWhenRefinanceCostsMore() public {
        _open(2 ether);
        _setRate(150);
        _setPrice(300_000e18);
        vault.rebalance();
        uint256 cap = tm.getTroveMaxBorrowingCapacity(address(vault));
        assertApproxEqRel(vault.trove().debt, cap, 1e15, "borrowed up to capacity only");
        uint256 coll = vault.trove().coll;
        _depositBTC(bob, 0.5 ether);
        vault.rebalance();
        assertGt(vault.trove().coll, coll, "spare goes in as collateral");
    }

    function test_recoveryModeFreezesSpareAndRepays() public {
        _open(2 ether);
        _borrower(carol, 1000 ether, 1.55e18);
        _setPrice(90_000e18);
        assertTrue(tm.checkRecoveryMode(_price()), "recovery");
        uint256 coll = vault.trove().coll;
        _depositBTC(bob, 0.5 ether);
        vault.rebalance();
        assertEq(vault.trove().coll, coll, "idle BTC stays idle");
        // Only idle BTC can leave, shared pro rata
        uint256 share = address(vault).balance * vault.balanceOf(bob) / vault.totalSupply();
        assertApproxEqAbs(vault.maxWithdraw(bob), share, 1);

        _setPrice(78_000e18);
        uint256 debt = vault.trove().debt;
        vault.rebalance();
        assertLt(vault.trove().debt, debt, "pure repayment still runs");
    }

    function test_unsafeSmallTroveCloses() public {
        _open(0.07 ether);
        _setPrice(55_000e18);
        vm.expectEmit(address(vault));
        emit Vault.TroveClosed();
        vault.rebalance();
        assertFalse(vault.trove().active);
    }

    function test_unsafeSmallTroveRepaysWhenCloseCannotBeBought() public {
        _pause(true);
        _open(0.07 ether);
        uint256 debt = vault.trove().debt;
        _setPrice(55_000e18);
        vault.setParams(2e18, 2.5e18, 3e18, 10_000, 100, 200, type(uint256).max);
        vault.rebalance();
        Vault.Trove memory t = vault.trove();
        assertTrue(t.active, "kept open");
        assertLt(t.debt, debt, "repaid down to the floor");
        vault.rebalance();
        assertEq(vault.trove().debt, t.debt, "nothing left to repay");
    }

    function test_shortfallWaitsForPool() public {
        _pause(true);
        _open(2 ether);
        Vault.Trove memory t = vault.trove();
        assertLt(vault.savingsValue(), t.debt - GAS_COMP, "fee not bought back");
        _pause(false);
        vault.setParams(2e18, 2.5e18, 3e18, 0, 100, 200, type(uint256).max);
        vault.rebalance();
        assertLt(vault.savingsValue(), t.debt - GAS_COMP, "no idle BTC to buy with");
        _depositBTC(bob, 0.1 ether);
        vault.setParams(2e18, 2.5e18, 3e18, 10_000, 100, 200, type(uint256).max);
        vault.rebalance();
        assertGe(vault.savingsValue(), t.debt - GAS_COMP, "bought once BTC is idle");
    }

    function test_hintsInCrowdedList() public {
        _borrower(makeAddr("b1"), 5 ether, 2.3e18);
        _borrower(makeAddr("b2"), 5 ether, 2.6e18);
        _borrower(makeAddr("b3"), 5 ether, 3.1e18);
        _borrower(makeAddr("b4"), 5 ether, 1.9e18);
        _open(2 ether);
        _depositBTC(bob, 0.01 ether);
        vault.rebalance();
        _setPrice(118_000e18);
        vault.rebalance();
        _setPrice(80_000e18);
        vault.rebalance();
        _setPrice(95_000e18);
        _depositBTC(bob, 0.3 ether);
        vault.rebalance();
        assertTrue(vault.trove().active);
    }

    // A factory without isPaused, or one the router does not know, reads as no market
    function test_canBuyFailsClosed() public {
        address unknown = deployCode("PoolFactory.sol:PoolFactory", abi.encode(address(1)));
        address[2] memory factories = [address(musd), unknown];
        for (uint256 i; i < 2; i++) {
            factory = factories[i];
            Vault v = _newVault(7 days);
            v.setBorrowingEnabled(true);
            vm.deal(alice, 2 ether);
            vm.prank(alice);
            v.depositBTC{value: 2 ether}(alice);
            v.rebalance();
            assertTrue(v.trove().active);
            assertLt(v.savingsValue(), v.trove().debt - GAS_COMP, "nothing bought");
        }
    }

    function test_surplusClaimedOnRebalance() public {
        _open(2 ether);
        _redeemVault();
        assertFalse(vault.trove().active, "redeemed out");
        uint256 surplus = ICollSurplus(sys.collSurplusPool()).getCollateral(address(vault));
        assertGt(surplus, 0);
        uint256 total = vault.totalAssets();
        vault.rebalance();
        assertEq(ICollSurplus(sys.collSurplusPool()).getCollateral(address(vault)), 0);
        assertApproxEqRel(vault.totalAssets(), total, 1e15);
    }
}

interface ICollSurplus {
    function getCollateral(address account) external view returns (uint256);
}
