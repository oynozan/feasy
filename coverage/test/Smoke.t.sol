// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "./Base.sol";

contract SmokeTest is Base {
    function test_openAndExit() public {
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
        assertApproxEqRel(_ratio(), 2.5e18, 1e15, "at target");
        uint256 max = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(max, alice, alice);
        assertEq(vault.balanceOf(alice) > 0, true);
    }
}
