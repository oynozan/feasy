// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultProfitTest is Base {
    function setUp() public override {
        super.setUp();
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        // The open's borrow fee is a loss the next checkpoint records
        vault.sync();
    }

    function test_payoutLocksAndReleases() public {
        uint256 total = vault.totalAssets();
        _yield(1000e18);
        assertEq(vault.totalAssets(), total, "payout hidden until a checkpoint");
        assertEq(vault.rawAssets(), total + vault.pendingProfit());
        uint256 pending = vault.pendingProfit();
        assertGt(pending, 0);

        vm.expectEmit(false, false, false, false, address(vault));
        emit Vault.ProfitLocked(0, 0, 0);
        vault.sync();
        assertEq(vault.totalAssets(), total, "a checkpoint does not move the price");
        assertEq(vault.lockedProfit(), pending);
        (, uint64 lockedAt, uint64 unlockAt) = vault.profit();
        assertEq(lockedAt, block.timestamp);
        assertEq(unlockAt, block.timestamp + 7 days);

        vm.warp(block.timestamp + 7 days);
        assertEq(vault.lockedProfit(), 0);
        // A week of loan interest is the only other change
        assertApproxEqRel(vault.totalAssets(), total + pending, 2e14, "fully released");
    }

    function test_sniperGetsOnlyTheDeposit() public {
        uint256 shares = _depositBTC(bob, 1 ether);
        _yield(1000e18);
        shares = vault.maxRedeem(bob);
        vm.prank(bob);
        uint256 out = vault.redeem(shares, bob, bob);
        assertLe(out, 1 ether, "payout stays with the holders before it");
    }

    function test_lossUsesTheLockFirst() public {
        _yield(1000e18);
        vault.sync();
        uint256 total = vault.totalAssets();
        uint256 locked = vault.lockedProfit();
        // A wider haircut on the MUSD term is a loss the lock absorbs
        vault.setParams(2e18, 2.5e18, 3e18, 300, 110, 200, type(uint256).max);
        vault.sync();
        assertEq(vault.totalAssets(), total, "covered by locked profit");
        assertLt(vault.lockedProfit(), locked);

        // Near the end of the release little is left to absorb a 5% haircut
        vm.warp(block.timestamp + 7 days - 1 hours);
        uint256 before = vault.totalAssets();
        vault.setParams(2e18, 2.5e18, 3e18, 300, 500, 200, type(uint256).max);
        uint256 hit = vault.totalAssets();
        vault.sync();
        assertEq(vault.lockedProfit(), 0, "lock used up");
        assertEq(vault.totalAssets(), hit, "the checkpoint does not move the price");
        assertEq(vault.totalAssets(), vault.recorded(), "nothing locked");
        assertLt(hit, before, "the excess reaches the price");
    }

    function test_donationLocks() public {
        uint256 total = vault.totalAssets();
        vm.prank(whale);
        btc.transfer(address(vault), 0.5 ether);
        assertEq(vault.totalAssets(), total);
        assertEq(vault.pendingProfit(), 0.5 ether);
        vault.sync();
        assertEq(vault.lockedProfit(), 0.5 ether);
    }
}
