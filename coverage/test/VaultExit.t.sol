// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultExitTest is Base {
    function _open(address user, uint256 amount) internal {
        _depositBTC(user, amount);
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
    }

    function _withdraw(address user, uint256 assets) internal {
        vm.prank(user);
        vault.withdraw(assets, user, user);
    }

    function test_withdrawReleasesAndRepays() public {
        _open(alice, 2 ether);
        Vault.Trove memory t = vault.trove();
        _withdraw(alice, 1 ether);
        assertEq(alice.balance, 1 ether);
        assertLt(vault.trove().debt, t.debt, "repaid with savings");
        assertApproxEqRel(_ratio(), 2.5e18, 1e16, "kept at target");
    }

    function test_redeemAllCloses() public {
        _open(alice, 2 ether);
        // The MUSD cushion only turns into BTC on harvest, so it stays behind
        uint256 shares = vault.maxRedeem(alice);
        assertLt(shares, vault.balanceOf(alice));
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertFalse(vault.trove().active);
        assertApproxEqRel(alice.balance, 2 ether, 1e16);
    }

    function test_smallTroveFloorThenWithdrawColl() public {
        _open(alice, 0.07 ether);
        _withdraw(alice, 0.025 ether);
        uint256 debt = vault.trove().debt;
        assertApproxEqAbs(debt, 2000e18, 1e15, "pinned at the minimum loan");
        _withdraw(alice, 0.003 ether);
        assertEq(vault.trove().debt, debt, "collateral only");
    }

    function test_partialExitClosesSmallTrove() public {
        _depositBTC(bob, 0.03 ether);
        _open(alice, 0.07 ether);
        _withdraw(alice, 0.065 ether);
        assertFalse(vault.trove().active, "loan would fall out of the band");
        assertGt(vault.balanceOf(bob), 0);
    }

    function test_closeBuysShortfall() public {
        _pause(true);
        _open(alice, 2 ether);
        assertLt(vault.savingsValue(), vault.trove().debt - GAS_COMP);
        uint256 locked = vault.maxRedeem(alice);
        assertLt(locked, vault.balanceOf(alice), "exit limited while the gap cannot be bought");
        _pause(false);
        uint256 shares = vault.maxRedeem(alice);
        assertGt(shares, locked);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertFalse(vault.trove().active);
    }

    function test_closeWithdrawsCollateralToBuy() public {
        vault.setParams(2e18, 2.5e18, 3e18, 0, 100, 200, type(uint256).max);
        _pause(true);
        _open(alice, 2 ether);
        assertLt(address(vault).balance, 1e12, "no idle BTC");
        _pause(false);
        uint256 shares = vault.maxRedeem(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertFalse(vault.trove().active);
    }

    function test_surplusClaimedOnExit() public {
        _open(alice, 2 ether);
        _depositBTC(bob, 0.1 ether);
        _redeemVault();
        uint256 max = vault.maxWithdraw(bob);
        assertGt(max, 0);
        _withdraw(bob, max);
        assertEq(bob.balance, max);
        // More than the idle BTC, so the exit claims the surplus first
        max = vault.maxWithdraw(alice);
        assertGt(max, address(vault).balance);
        _withdraw(alice, max);
        assertEq(alice.balance, max);
    }

    function test_weakSystemKeepsCollateral() public {
        _open(alice, 20 ether);
        // The whale drops to 140%, so the rest of the system leans on the vault
        Vault.Trove memory w = _whaleTrove();
        uint256 keep = w.debt * 1.4e18 / _price();
        vm.prank(whale);
        IWithdrawColl(address(bo)).withdrawColl(w.coll - keep, address(0), address(0));
        uint256 max = vault.maxWithdraw(alice);
        assertLt(max, vault.previewRedeem(vault.balanceOf(alice)), "held back for the system");
        _withdraw(alice, max);
        assertTrue(vault.trove().active);
        assertGe(vault.trove().coll * 1e18 / 1e18, 4.9 ether, "keeps the system at CCR");
    }

    function test_recoveryLimitsExitsToIdle() public {
        _open(alice, 2 ether);
        _borrower(carol, 1000 ether, 1.55e18);
        _setPrice(90_000e18);
        uint256 idle = address(vault).balance;
        assertEq(vault.maxWithdraw(alice), idle);
        _withdraw(alice, idle);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function _whaleTrove() internal view returns (Vault.Trove memory t) {
        (uint256 coll, uint256 principal, uint256 interest,,,) = tm.getEntireDebtAndColl(whale);
        t = Vault.Trove(true, coll, principal + interest);
    }
}

interface IWithdrawColl {
    function withdrawColl(uint256 amount, address upperHint, address lowerHint) external;
}

// No whale and no pool, so the vault opens the only trove of the system
contract VaultLastTroveTest is Base {
    function _seed() internal override {}

    function test_lastTroveCannotClose() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active);
        assertEq(tm.getEntireSystemDebt(), vault.trove().debt, "vault is the last trove");
        uint256 max = vault.maxWithdraw(alice);
        assertLt(max, vault.previewRedeem(vault.balanceOf(alice)), "the trove has to stay");
        vm.prank(alice);
        vault.withdraw(max, alice, alice);
        assertTrue(vault.trove().active);
    }
}
