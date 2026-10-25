// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";
import {RedeemQueue} from "vault/RedeemQueue.sol";

contract VaultQueueTest is Base {
    function _request(address user, uint256 shares) internal returns (uint256 id) {
        vm.prank(user);
        id = queue.requestRedeem(shares, user, user);
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    function test_requestChecks() public {
        uint256 shares = _depositBTC(alice, 1 ether);
        vm.startPrank(alice);
        vm.expectRevert(RedeemQueue.BadParams.selector);
        queue.requestRedeem(0, alice, alice);
        vm.expectRevert(RedeemQueue.BadReceiver.selector);
        queue.requestRedeem(shares, address(0), alice);
        vm.expectRevert(RedeemQueue.BadReceiver.selector);
        queue.requestRedeem(shares, address(vault), alice);
        vm.expectRevert(RedeemQueue.BadReceiver.selector);
        queue.requestRedeem(shares, address(queue), alice);
        vm.expectRevert(RedeemQueue.BadReceiver.selector);
        queue.requestRedeem(shares, BTC, alice);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, shares)
        );
        queue.requestRedeem(shares, bob, alice);
    }

    function test_onlyQueueEscrowsOnlyVaultFills() public {
        vm.expectRevert(Vault.NotQueue.selector);
        vault.escrow(alice, alice, 1);
        vm.expectRevert(RedeemQueue.NotVault.selector);
        queue.fill(1);
        // A fill that burns no shares would misprice the next fill boundary
        vm.prank(address(vault));
        vm.expectRevert(RedeemQueue.BadParams.selector);
        queue.fill(0);
    }

    function test_operatorRequestAndIdleFill() public {
        uint256 shares = _depositBTC(alice, 1 ether);
        vm.prank(alice);
        vault.approve(bob, shares);
        vm.prank(bob);
        uint256 id = queue.requestRedeem(shares, carol, alice);
        assertEq(id, 1);
        assertEq(vault.balanceOf(address(queue)), shares);
        assertEq(queue.pending(), shares);
        assertEq(queue.requestCount(), 1);
        assertEq(queue.requestsOf(alice).length, 1);
        assertEq(queue.sharesAhead(id), 0);
        assertEq(queue.pendingRedeem(id), shares);
        assertEq(queue.claimableRedeem(id), 0);
        assertEq(vault.maxWithdraw(address(queue)), 0, "escrow cannot exit directly");
        assertEq(vault.maxRedeem(address(queue)), 0);

        vault.rebalance();
        assertEq(queue.pending(), 0, "idle BTC paid the request");
        assertEq(vault.totalSupply(), 0);
        uint256 owed = queue.claimableRedeem(id);
        assertApproxEqAbs(owed, 1 ether, 1);
        (,, uint256 reserved,) = queue.queueState();
        assertEq(reserved, owed);

        uint256 paid = queue.claim(_ids(id));
        assertEq(paid, owed);
        assertEq(carol.balance, owed, "paid to the receiver");
        assertEq(queue.reserved(), 0);
        assertEq(queue.claim(_ids(id)), 0, "nothing twice");
        RedeemQueue.Request memory r = queue.getRequest(id);
        assertEq(r.owner, alice);
        assertEq(r.receiver, carol);
    }

    function test_claimChecks() public {
        uint256[] memory many = new uint256[](17);
        vm.expectRevert(RedeemQueue.BadParams.selector);
        queue.claim(many);
        vm.expectRevert(RedeemQueue.BadParams.selector);
        queue.claim(_ids(0));
        vm.expectRevert(RedeemQueue.BadParams.selector);
        queue.claim(_ids(1));
        assertEq(queue.sharesAhead(5), 0);
        assertEq(queue.pendingRedeem(5), 0);
        assertEq(queue.claimableRedeem(5), 0);
        assertEq(queue.getRequest(5).owner, address(0));
    }

    function test_processQueueReleasesInOrder() public {
        _depositBTC(alice, 2 ether);
        _depositBTC(bob, 2 ether);
        _depositBTC(carol, 2 ether);
        vault.rebalance();
        uint256 a = _request(alice, vault.balanceOf(alice));
        uint256 b = _request(bob, vault.balanceOf(bob));
        uint256 c = _request(carol, vault.balanceOf(carol) / 2);
        assertEq(queue.sharesAhead(c), queue.pendingRedeem(a) + queue.pendingRedeem(b));
        // Waiting requests are paid first, carol's unqueued half still leaves at once
        assertApproxEqRel(
            vault.maxWithdraw(carol), vault.previewRedeem(vault.balanceOf(carol)), 1e16
        );

        (uint256 s1, uint256 a1) = vault.processQueue(1 ether);
        assertGt(s1, 0);
        assertLe(a1, 1 ether);
        assertGt(queue.claimableRedeem(a), 0);
        assertEq(queue.claimableRedeem(b), 0, "arrival order");

        vault.processQueue(type(uint256).max);
        assertEq(queue.pending(), 0);
        uint256[] memory ids = new uint256[](3);
        (ids[0], ids[1], ids[2]) = (a, b, c);
        queue.claim(ids);
        assertApproxEqRel(alice.balance, 2 ether, 1e16);
        assertApproxEqRel(bob.balance, 2 ether, 1e16);
        assertEq(queue.reserved(), 0);
        (s1, a1) = vault.processQueue(type(uint256).max);
        assertEq(s1 + a1, 0, "nothing waits");
    }

    function test_claimInsideEarlierFill() public {
        _depositBTC(alice, 2 ether);
        _depositBTC(bob, 2 ether);
        vault.rebalance();
        uint256 a = _request(alice, vault.balanceOf(alice) / 10);
        uint256 b = _request(bob, vault.balanceOf(bob));
        vault.processQueue(0.3 ether);
        vault.processQueue(type(uint256).max);
        uint256 owed = queue.claimableRedeem(a);
        assertApproxEqRel(owed, 0.2 ether, 1e16);
        assertEq(queue.claim(_ids(a)), owed);
        assertGt(queue.claim(_ids(b)), 0);
        assertEq(queue.reserved(), 0);
    }

    function test_smallFillWaits() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        uint256 id = _request(alice, vault.balanceOf(alice) / 2);
        (uint256 shares,) = vault.processQueue(1e11);
        assertEq(shares, 0, "under the minimum fill");
        (shares,) = vault.processQueue(0);
        assertEq(shares, 0, "burns nothing");
        assertEq(queue.pendingRedeem(id), queue.pending());
    }

    function test_dustRequestGoesWithRebalance() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        vm.prank(alice);
        uint256 id = queue.requestRedeem(1, alice, alice);
        assertGt(queue.pending(), 0);
        _setPrice(130_000e18);
        uint256 debt = vault.trove().debt;
        vault.rebalance();
        assertEq(queue.pending(), 0, "dust burned in a 0 BTC fill");
        assertGt(vault.trove().debt, debt, "the same rebalance still borrows");
        assertEq(queue.claim(_ids(id)), 0);
    }

    function test_queueStopsBorrowing() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        _request(alice, vault.balanceOf(alice) / 2);
        _setPrice(130_000e18);
        uint256 debt = vault.trove().debt;
        _depositBTC(bob, 0.1 ether);
        vm.prank(keeper);
        vault.rebalance();
        assertEq(vault.trove().debt, debt, "no new debt while a request waits");
    }

    function test_harvestFillsQueue() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        _request(alice, vault.balanceOf(alice) / 100);
        _yield(1000e18);
        vm.prank(keeper);
        vault.harvest(type(uint256).max);
        assertEq(queue.pending(), 0, "the sale's BTC paid the request");
    }
}
