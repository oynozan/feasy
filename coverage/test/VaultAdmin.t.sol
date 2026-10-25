// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base, IAggregator} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultAdminTest is Base {
    function test_constructorRejectsUnlockPeriod() public {
        vm.expectRevert(Vault.BadParams.selector);
        _newVault(0);
        vm.expectRevert(Vault.BadParams.selector);
        _newVault(30 days + 1);
        assertEq(_newVault(30 days).unlockPeriod(), 30 days);
    }

    function test_constructorWiring() public view {
        assertEq(address(vault.troveManager()), address(tm));
        assertEq(address(vault.musd()), address(musd));
        assertEq(vault.guardian(), guardian);
        assertEq(vault.keeper(), keeper);
        assertEq(address(queue.vault()), address(vault));
        assertEq(address(queue.btc()), BTC);
        assertEq(vault.decimals(), 24);
    }

    function test_borrowingOffAtDeploy() public {
        Vault fresh = _newVault(7 days);
        assertFalse(fresh.borrowingEnabled());
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        fresh.depositBTC{value: 2 ether}(alice);
        fresh.rebalance();
        assertFalse(fresh.trove().active, "no trove while borrowing is off");
        assertEq(fresh.maxWithdraw(alice), fresh.convertToAssets(fresh.balanceOf(alice)));
    }

    function test_receiveOnlyFromMezo() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertFalse(ok, "stray BTC refused");
    }

    function test_onlyOwnerSetters() public {
        vm.startPrank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.setKeeper(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.setGuardian(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.setBorrowingEnabled(true);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.setParams(2e18, 2.5e18, 3e18, 300, 100, 200, 0);
        vm.stopPrank();

        vm.expectEmit(address(vault));
        emit Vault.KeeperSet(alice);
        vault.setKeeper(alice);
        assertEq(vault.keeper(), alice);
        vm.expectEmit(address(vault));
        emit Vault.GuardianSet(guardian, bob);
        vault.setGuardian(bob);
        assertEq(vault.guardian(), bob);
    }

    function test_setParamsBounds() public {
        vm.expectRevert(Vault.BadParams.selector);
        vault.setParams(1.4e18, 2.5e18, 3e18, 300, 100, 200, 0);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setParams(2.5e18, 2.5e18, 3e18, 300, 100, 200, 0);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setParams(2e18, 3e18, 3e18, 300, 100, 200, 0);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setParams(2e18, 2.5e18, 3e18, 10_001, 100, 200, 0);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setParams(2e18, 2.5e18, 3e18, 300, 501, 200, 0);
        vault.setParams(1.5e18, 1.6e18, 1.7e18, 10_000, 500, 50, 7);
        assertEq(vault.minCR(), 1.5e18);
        assertEq(vault.targetCR(), 1.6e18);
        assertEq(vault.maxCR(), 1.7e18);
        assertEq(vault.bufferBps(), 10_000);
        assertEq(vault.slippageBps(), 500);
        assertEq(vault.maxBorrowRate(), 50);
        assertEq(vault.depositCap(), 7);
    }

    function test_guardianBrakes() public {
        vm.prank(alice);
        vm.expectRevert(Vault.NotGuardian.selector);
        vault.pauseBorrowing();
        vm.prank(keeper);
        vm.expectRevert(Vault.NotGuardian.selector);
        vault.unwind();

        vm.prank(guardian);
        vault.pauseBorrowing();
        assertFalse(vault.borrowingEnabled());
        vault.setBorrowingEnabled(true);
        vault.pauseBorrowing();
        assertFalse(vault.borrowingEnabled());
    }

    function test_unwindClosesTrove() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active);
        vm.prank(guardian);
        vm.expectEmit(address(vault));
        emit Vault.TroveClosed();
        vault.unwind();
        assertFalse(vault.trove().active);
        assertFalse(vault.borrowingEnabled());
        // Nothing to close the second time
        vault.unwind();
    }

    function test_guardianZeroLeavesOwner() public {
        vault.setGuardian(address(0));
        vm.prank(guardian);
        vm.expectRevert(Vault.NotGuardian.selector);
        vault.pauseBorrowing();
        vault.pauseBorrowing();
    }

    function test_noSleeveNoRoll() public {
        assertEq(address(vault.sleeve()), address(0));
        vm.prank(keeper);
        vm.expectRevert(Vault.RollWindow.selector);
        vault.roll();
    }

    function test_staleOracleViews() public {
        // Before any state change the vault has no last price and values only BTC
        vm.prank(whale);
        btc.transfer(address(vault), 1 ether);
        sys.exec(sys.aggregator(), abi.encodeCall(IAggregator.setBlockTime, (block.timestamp)));
        vm.warp(block.timestamp + 2 days);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.pendingProfit(), 1 ether);
        vm.expectRevert();
        vault.sync();
    }
}
