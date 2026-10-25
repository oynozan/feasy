// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultHarvestTest is Base {
    function setUp() public override {
        super.setUp();
        _depositBTC(alice, 2 ether);
        vault.rebalance();
    }

    function test_strangerCannotHarvestOpenTrove() public {
        _yield(1000e18);
        vm.prank(alice);
        vm.expectRevert(Vault.NotKeeper.selector);
        vault.harvest(type(uint256).max);
    }

    function test_nothingToHarvest() public {
        vm.startPrank(keeper);
        // The buy-back filled a little over the cushion, the first harvest sells that
        vault.harvest(type(uint256).max);
        assertEq(vault.harvest(type(uint256).max), 0);
        vm.stopPrank();
    }

    function test_keeperHarvestsIntoBtc() public {
        _yield(1000e18);
        uint256 debt = vault.trove().debt;
        uint256 idle = address(vault).balance;
        vm.prank(keeper);
        uint256 out = vault.harvest(type(uint256).max);
        assertGt(out, 0);
        assertEq(address(vault).balance, idle + out);
        assertGe(vault.savingsValue(), debt - GAS_COMP, "loan still covered");
        assertGt(vault.lockedProfit(), 0, "the sale's gain unlocks over time");
    }

    function test_ownerHarvestsChunkFromYield() public {
        _yield(1000e18);
        uint256 principal = ISavingsView(savings).balanceOf(address(vault));
        uint256 out = vault.harvest(10e18);
        assertGt(out, 0);
        assertGe(ISavingsView(savings).balanceOf(address(vault)), principal, "paid from yield");
    }

    function test_anyoneHarvestsAfterClose() public {
        _yield(1000e18);
        vm.prank(guardian);
        vault.unwind();
        assertGt(vault.savingsValue(), 0, "MUSD left after the close");
        vm.prank(alice);
        assertGt(vault.harvest(type(uint256).max), 0);
        vm.prank(alice);
        assertEq(vault.harvest(type(uint256).max), 0, "all sold");
    }
}

interface ISavingsView {
    function balanceOf(address account) external view returns (uint256);
}
