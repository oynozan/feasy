// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base, ILiquidations} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

interface IWhaleTrove {
    function withdrawColl(uint256 amount, address upperHint, address lowerHint) external;
    function addColl(address upperHint, address lowerHint) external payable;
}

interface IPCVLike {
    function distributeMUSD() external;
}

contract UnwindBase is Base {
    function _minDebt() internal view returns (uint256) {
        return bo.minNetDebt() + GAS_COMP;
    }

    function _unwind() internal {
        vm.prank(guardian);
        vault.unwind();
    }

    // A large borrower near the line, a 10% drop then puts the system in Recovery Mode
    function _nearTheLine() internal {
        _borrower(carol, 1000 ether, 1.55e18);
        // Its borrow fee reaches sMUSD now, before the vault holds any
        IPCVLike(sys.pcv()).distributeMUSD();
    }

    function _recovery() internal {
        _setPrice(90_000e18);
        assertTrue(tm.checkRecoveryMode(_price()), "recovery");
    }
}

contract RecoveryUnwindTest is UnwindBase {
    function setUp() public override {
        super.setUp();
        _nearTheLine();
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
    }

    function test_unwindInRecoveryRepaysToMinimum() public {
        _recovery();
        Vault.Trove memory before = vault.trove();
        uint256 raw = vault.rawAssets();
        vm.expectEmit(address(vault));
        emit Vault.BorrowingSet(false);
        _unwind();
        Vault.Trove memory t = vault.trove();
        assertTrue(t.active, "Mezo refuses the close, so the trove stays");
        assertEq(t.debt, _minDebt(), "repaid down to the minimum loan");
        assertEq(t.coll, before.coll, "no collateral leaves in Recovery Mode");
        assertTrue(vault.closing());
        assertFalse(vault.borrowingEnabled());
        assertApproxEqAbs(vault.rawAssets(), raw, 1e6, "repaying from savings moves no value");
        assertEq(musd.balanceOf(address(vault)), 0, "every pulled MUSD went to the loan");
    }

    function test_rebalanceInRecoveryKeepsClosing() public {
        _recovery();
        _unwind();
        Vault.Trove memory t = vault.trove();
        _depositBTC(bob, 0.5 ether);
        uint256 idle = address(vault).balance;
        vault.rebalance();
        assertTrue(vault.closing(), "still waiting for Mezo");
        assertEq(vault.trove().coll, t.coll, "spare BTC stays out of the trove");
        assertEq(vault.trove().debt, t.debt);
        assertEq(address(vault).balance, idle);
        // Only idle BTC can leave while Mezo is in Recovery Mode
        uint256 share = idle * vault.balanceOf(bob) / vault.totalSupply();
        assertApproxEqAbs(vault.maxWithdraw(bob), share, 1);
        vault.rebalance();
        assertTrue(vault.closing(), "every rebalance in Recovery Mode waits");
    }

    function test_closesOnceRecoveryEnds() public {
        _recovery();
        _unwind();
        _setPrice(PRICE);
        assertFalse(tm.checkRecoveryMode(_price()));
        vm.expectEmit(address(vault));
        emit Vault.TroveClosed();
        vault.rebalance();
        assertFalse(vault.trove().active, "closed");
        assertFalse(vault.closing());

        // Anyone sells the leftover MUSD, then the whole balance leaves at once
        vm.prank(bob);
        vault.harvest(type(uint256).max);
        assertEq(vault.savingsValue(), 0, "no MUSD left");
        uint256 shares = vault.balanceOf(alice);
        assertEq(vault.maxRedeem(alice), shares, "every share is liquid");
        vm.prank(alice);
        uint256 out = vault.redeem(shares, alice, alice);
        assertApproxEqRel(out, 2 ether, 1e16, "the deposit back less the loan's costs");
        assertEq(vault.totalSupply(), 0);
    }

    function test_setBorrowingEnabledCallsOffClosing() public {
        _recovery();
        _unwind();
        vault.setBorrowingEnabled(false);
        assertTrue(vault.closing(), "turning borrowing off leaves the unwind waiting");
        vault.setBorrowingEnabled(true);
        assertFalse(vault.closing(), "turning it on calls the unwind off");

        _setPrice(PRICE);
        vault.rebalance();
        assertTrue(vault.trove().active, "kept open");
        assertApproxEqRel(_ratio(), 2.5e18, 1e16, "borrowed back to target");
    }

    // A second unwind after Recovery Mode closes at once and clears the flag itself
    function test_secondUnwindClosesDirectly() public {
        _recovery();
        _unwind();
        _setPrice(PRICE);
        vm.expectEmit(address(vault));
        emit Vault.TroveClosed();
        _unwind();
        assertFalse(vault.trove().active);
        assertFalse(vault.closing(), "no wait for a rebalance");
        vault.rebalance();
        assertFalse(vault.trove().active, "and the rebalance opens nothing");
    }

    // A trove Mezo ends while the unwind waits clears the flag on the next rebalance
    function test_closingClearsOnceTheTroveIsGone() public {
        _recovery();
        _unwind();
        // Only a crash takes even the minimum loan under 110%
        _setPrice(1000e18);
        vm.prank(bob);
        ILiquidations(address(tm)).liquidate(address(vault));
        assertFalse(vault.trove().active, "liquidated");
        assertTrue(vault.closing());
        vault.rebalance();
        assertFalse(vault.closing());
    }
}

contract UnwindEdgesTest is UnwindBase {
    // Closing the vault's trove would take the rest of the system under CCR, without Recovery Mode
    function test_unwindBelowCcrWaitsForTheSystem() public {
        _depositBTC(alice, 20 ether);
        vault.rebalance();
        (uint256 coll, uint256 principal, uint256 interest,,,) = tm.getEntireDebtAndColl(whale);
        uint256 keep = (principal + interest) * 1.4e18 / _price();
        vm.prank(whale);
        IWhaleTrove(address(bo)).withdrawColl(coll - keep, address(0), address(0));
        assertFalse(tm.checkRecoveryMode(_price()), "not in Recovery Mode");

        _unwind();
        assertTrue(vault.closing(), "Mezo would refuse the close");
        assertEq(vault.trove().debt, _minDebt());
        vault.rebalance();
        assertTrue(vault.closing(), "still under CCR without the vault");

        vm.prank(whale);
        IWhaleTrove(address(bo)).addColl{value: coll - keep}(address(0), address(0));
        vault.rebalance();
        assertFalse(vault.trove().active, "closed once the system can carry it");
        assertFalse(vault.closing());
    }

    // A MUSD gap the pool cannot fill keeps the unwind waiting after Recovery Mode
    function test_closingWaitsForBuyableGap() public {
        _nearTheLine();
        _pause(true);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertLt(vault.savingsValue(), vault.trove().debt - GAS_COMP, "borrow fee not bought");
        _recovery();
        _unwind();
        assertTrue(vault.closing());
        assertLt(vault.savingsValue(), vault.trove().debt - GAS_COMP, "the gap stays");

        _setPrice(PRICE);
        vault.rebalance();
        assertTrue(vault.closing(), "the gap cannot be bought");
        assertTrue(vault.trove().active);

        _pause(false);
        vm.expectEmit(address(vault));
        emit Vault.TroveClosed();
        vault.rebalance();
        assertFalse(vault.closing());
        assertFalse(vault.trove().active);
    }
}
