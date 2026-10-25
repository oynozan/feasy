// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Base, IAggregator} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultDepositTest is Base {
    function test_depositPaths() public {
        uint256 a = _depositBTC(alice, 1 ether);
        assertEq(a, vault.convertToShares(1 ether));
        assertEq(vault.recorded(), 1 ether);

        vm.deal(bob, 2 ether);
        vm.startPrank(bob);
        btc.approve(address(vault), 1 ether);
        uint256 b = vault.deposit(1 ether, bob);
        uint256 shares = vault.previewMint(1 ether);
        btc.approve(address(vault), vault.previewMint(shares));
        uint256 paid = vault.mint(shares, bob);
        vm.stopPrank();
        assertEq(b, a, "same price for the same BTC");
        assertGe(paid, 1, "mint pulled BTC");
        assertEq(vault.totalAssets(), 2 ether + paid);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_zeroShareDepositReverts() public {
        vm.expectRevert(Vault.ZeroShares.selector);
        vault.depositBTC{value: 0}(alice);
    }

    function test_depositCap() public {
        vault.setParams(2e18, 2.5e18, 3e18, 300, 100, 200, 3 ether);
        _depositBTC(alice, 1 ether);
        assertEq(vault.maxDeposit(bob), 2 ether);
        assertEq(vault.maxMint(bob), vault.convertToShares(2 ether));

        vm.deal(bob, 10 ether);
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector, bob, 2 ether + 1, 2 ether
            )
        );
        vault.depositBTC{value: 2 ether + 1}(bob);
        btc.approve(address(vault), 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector, bob, 2 ether + 1, 2 ether
            )
        );
        vault.deposit(2 ether + 1, bob);
        uint256 maxShares = vault.maxMint(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector, bob, maxShares + 1, maxShares
            )
        );
        vault.mint(maxShares + 1, bob);
        vault.mint(maxShares, bob);
        vm.stopPrank();
        assertEq(vault.maxDeposit(bob), 0);
    }

    function test_withdrawAndRedeemIdle() public {
        _depositBTC(alice, 1 ether);
        uint256 max = vault.maxWithdraw(alice);
        assertEq(max, vault.convertToAssets(vault.balanceOf(alice)));
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, max + 1, max)
        );
        vault.withdraw(max + 1, alice, alice);
        vault.withdraw(max / 2, alice, alice);
        uint256 shares = vault.maxRedeem(alice);
        assertEq(shares, vault.balanceOf(alice));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxRedeem.selector, alice, shares + 1, shares
            )
        );
        vault.redeem(shares + 1, alice, alice);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0, "no shares, nothing to take");
        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_withdrawThroughAllowance() public {
        _depositBTC(alice, 1 ether);
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(bob);
        vault.redeem(shares, bob, alice);
        assertEq(bob.balance, 1 ether);
    }

    function test_staleOracleAfterUse() public {
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        uint256 before = vault.totalAssets();
        sys.exec(sys.aggregator(), abi.encodeCall(IAggregator.setBlockTime, (block.timestamp)));
        vm.warp(block.timestamp + 61);
        // Only the profit release and the loan interest of 61 seconds move it
        assertApproxEqRel(vault.totalAssets(), before, 1e11, "falls back to the last price");
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        vm.expectRevert("PriceFeed: Oracle is stale.");
        vault.depositBTC{value: 0}(alice);
    }

    // A vault whose debt outweighs every asset it holds takes no deposits
    function test_worthlessVaultRefusesDeposits() public {
        _pause(true);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        assertLt(vault.savingsValue(), vault.trove().debt - GAS_COMP, "borrow fee not bought back");
        _setPrice(1e18);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.maxDeposit(bob), 0);
        assertEq(vault.maxMint(bob), 0);
    }
}
