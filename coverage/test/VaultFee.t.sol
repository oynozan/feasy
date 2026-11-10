// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base} from "./Base.sol";
import {Vault} from "vault/Vault.sol";

contract VaultFeeTest is Base {
    uint256 constant FEE_DELAY = 30 days;
    bytes32 constant FEE_TAKEN = keccak256("FeeTaken(uint256,uint256)");

    // A fee set before the deposits, so its delay is over when they arrive
    function _activeFee(uint16 bps) internal {
        vault.setFee(bps, carol);
        vm.warp(vm.getBlockTimestamp() + FEE_DELAY);
    }

    // Every deposit stays idle, so raw moves only by donations and exits
    function _noTrove() internal {
        vault.setParams(2e18, 2.5e18, 3e18, 10_000, 100, 200, type(uint256).max);
    }

    function _donate(uint256 amount) internal {
        vm.prank(whale);
        btc.transfer(address(vault), amount);
    }

    // The fee the next checkpoint takes, on the gain left once the deficit is won back
    function _expectedFee(uint256 bps) internal view returns (uint256) {
        uint256 raw = vault.rawAssets();
        uint256 gain = raw > vault.recorded() ? raw - vault.recorded() : 0;
        uint256 deficit = vault.deficit();
        return (gain > deficit ? gain - deficit : 0) * bps / 1e4;
    }

    function _syncFee() internal returns (uint256 shares, uint256 assets) {
        vm.recordLogs();
        vault.sync();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == FEE_TAKEN) {
                (shares, assets) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
    }

    function _value(address user) internal view returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(user));
    }

    // A trove whose MUSD runs over what it owes, so the BTC price moves raw both ways
    function _surplusVault() internal {
        _activeFee(1000);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        _yield(5000e18);
        vault.sync();
        assertEq(vault.deficit(), 0);
        assertGt(vault.savingsValue(), vault.trove().debt - GAS_COMP, "MUSD over what is owed");
    }

    function test_setFeeChecks() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setFee(100, alice);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setFee(2001, carol);
        vm.expectRevert(Vault.BadParams.selector);
        vault.setFee(1, address(0));
        vault.setFee(0, address(0));

        vm.expectEmit(address(vault));
        emit Vault.FeeSet(2000, carol);
        vault.setFee(2000, carol);
        assertEq(vault.feeRecipient(), carol, "recipient at once");
        assertEq(vault.feeBps(), 0, "the rise waits");
        assertEq(vault.nextFeeBps(), 2000);
        assertEq(vault.nextFeeAt(), vm.getBlockTimestamp() + FEE_DELAY);
    }

    function test_riseWaitsThirtyDays() public {
        _noTrove();
        _depositBTC(alice, 1 ether);
        vault.setFee(1000, carol);
        uint256 at = vault.nextFeeAt();
        _donate(0.01 ether);
        (uint256 shares,) = _syncFee();
        assertEq(shares, 0, "no fee right after the rise");

        vm.warp(at - 1);
        _donate(0.01 ether);
        (shares,) = _syncFee();
        assertEq(shares, 0, "no fee a second before the delay ends");
        assertEq(vault.feeBps(), 0, "not applied yet");
        assertEq(vault.balanceOf(carol), 0);

        vm.warp(at);
        assertEq(vault.feeBps(), 0, "applied by the next checkpoint");
        _donate(0.01 ether);
        uint256 expected = _expectedFee(1000);
        assertEq(expected, 0.001 ether, "a tenth of the gain");
        uint256 assets;
        (shares, assets) = _syncFee();
        assertEq(assets, expected, "charged once the delay is over");
        assertEq(vault.balanceOf(carol), shares);
        assertEq(vault.feeBps(), 1000, "the checkpoint wrote the new rate");
        assertEq(vault.nextFeeAt(), 0);
    }

    function test_cutIsImmediate() public {
        _noTrove();
        _depositBTC(alice, 1 ether);
        _activeFee(2000);
        vault.setFee(500, carol);
        assertEq(vault.feeBps(), 500);
        assertEq(vault.nextFeeAt(), 0, "the cut clears the old rise");
        _donate(0.01 ether);
        (, uint256 assets) = _syncFee();
        assertEq(assets, 0.0005 ether, "5% of the gain");
    }

    // A cut while a rise waits calls the rise off
    function test_cutCancelsPendingRise() public {
        _noTrove();
        _depositBTC(alice, 1 ether);
        vault.setFee(2000, carol);
        vault.setFee(0, carol);
        assertEq(vault.nextFeeAt(), 0);
        vm.warp(vm.getBlockTimestamp() + FEE_DELAY);
        _donate(0.01 ether);
        (uint256 shares,) = _syncFee();
        assertEq(shares, 0, "nothing charged after the old delay");
    }

    // A second rise inside the delay restarts it
    function test_riseRestartsDelay() public {
        vault.setFee(1000, carol);
        vm.warp(vm.getBlockTimestamp() + 10 days);
        vault.setFee(2000, bob);
        assertEq(vault.feeRecipient(), bob);
        assertEq(vault.nextFeeBps(), 2000);
        assertEq(vault.nextFeeAt(), vm.getBlockTimestamp() + FEE_DELAY);
        // setFee applies a rise that is due before it compares, so the same rate is no rise
        vm.warp(vm.getBlockTimestamp() + FEE_DELAY);
        vault.setFee(2000, bob);
        assertEq(vault.feeBps(), 2000);
        assertEq(vault.nextFeeAt(), 0);
    }

    function test_feeSharesPricedOnRaw() public {
        _noTrove();
        _activeFee(1000);
        _depositBTC(alice, 1 ether);
        _depositBTC(bob, 1 ether);
        vault.sync();
        uint256 aliceBefore = _value(alice);
        uint256 supply = vault.totalSupply();
        _donate(0.1 ether);
        uint256 raw = vault.rawAssets();
        uint256 fee = 0.01 ether;
        uint256 expectedShares = fee * (supply + 1e6) / (raw - fee + 1);

        vm.expectEmit(address(vault));
        emit Vault.FeeTaken(expectedShares, fee);
        vm.expectEmit(false, false, false, false, address(vault));
        emit Vault.ProfitLocked(0, 0, 0);
        vault.sync();
        assertEq(vault.balanceOf(carol), expectedShares);
        assertEq(vault.lockedProfit(), 0.09 ether, "the rest of the gain unlocks");
        assertGe(_value(alice), aliceBefore, "holders' price does not fall");
        assertEq(vault.deficit(), 0, "the fee mint leaves no deficit");

        // The fee shares are fee over raw of the vault, so none of the rest reaches them
        vm.warp(vm.getBlockTimestamp() + 7 days);
        assertApproxEqAbs(_value(carol), fee, 1e3, "the fee and nothing more");
        assertApproxEqAbs(_value(alice), 1.045 ether, 1e3, "half the gain less half the fee");
        assertApproxEqAbs(_value(bob), 1.045 ether, 1e3);
    }

    // A loss carries forward, a partial recovery and then a pure one pay no fee at all
    function test_recoveryOfALossIsFree() public {
        _surplusVault();
        uint256 high = vault.rawAssets();

        // A higher BTC price makes the MUSD surplus worth less BTC
        _setPrice(120_000e18);
        uint256 loss = high - vault.rawAssets();
        (uint256 shares,) = _syncFee();
        assertEq(shares, 0, "no fee on a loss");
        assertEq(vault.deficit(), loss, "the loss is carried");

        _setPrice(110_000e18);
        uint256 back = vault.rawAssets() - (high - loss);
        assertLt(back, loss, "a partial recovery");
        (shares,) = _syncFee();
        assertEq(shares, 0, "no fee on part of the loss");
        assertEq(vault.deficit(), loss - back);

        _setPrice(PRICE);
        assertEq(vault.rawAssets(), high, "back at the old high");
        uint256 assets;
        (shares, assets) = _syncFee();
        assertEq(assets, 0, "not a wei on a pure recovery");
        assertEq(shares, 0);
        assertEq(vault.deficit(), 0);
    }

    function test_recoveryPastTheLossPaysOnTheExcess() public {
        _surplusVault();
        uint256 high = vault.rawAssets();
        _setPrice(120_000e18);
        vault.sync();
        uint256 loss = vault.deficit();
        assertGt(loss, 0);

        _setPrice(PRICE);
        _yield(2000e18);
        uint256 raw = vault.rawAssets();
        uint256 expected = (raw - high) * 1000 / 1e4;
        assertEq(_expectedFee(1000), expected, "a tenth of what is above the old high");
        assertLt(expected, (raw - (high - loss)) / 10, "less than a tenth of the gain");
        (, uint256 assets) = _syncFee();
        assertEq(assets, expected);
        assertEq(vault.deficit(), 0, "the fee mint leaves no deficit");
    }

    // Mints and burns carry the deficit per share, transfers leave it alone
    function test_deficitScalesWithSupply() public {
        _surplusVault();
        _setPrice(120_000e18);
        vault.sync();
        uint256 deficit = vault.deficit();
        uint256 supply = vault.totalSupply();
        assertGt(deficit, 0);

        _depositBTC(bob, 1 ether);
        uint256 grown = vault.totalSupply();
        assertEq(vault.deficit(), deficit * grown / supply, "a mint scales it up");
        assertApproxEqRel(vault.deficit() * 1e18 / grown, deficit * 1e18 / supply, 1e9);

        uint256 half = vault.balanceOf(bob) / 2;
        uint256 before = vault.deficit();
        vm.prank(bob);
        vault.transfer(carol, half);
        assertEq(vault.deficit(), before, "a transfer leaves it");

        vm.prank(bob);
        vault.redeem(half / 2, bob, bob);
        uint256 shrunk = vault.totalSupply();
        assertEq(vault.deficit(), before * shrunk / grown, "a leaving holder takes their part");
        assertApproxEqRel(vault.deficit() * 1e18 / shrunk, deficit * 1e18 / supply, 1e9);
    }

    function test_noFeeOnDeposits() public {
        _noTrove();
        _activeFee(2000);
        _depositBTC(alice, 1 ether);
        vault.sync();
        vm.deal(bob, 3 ether);
        vm.startPrank(bob);
        vault.depositBTC{value: 1 ether}(bob);
        btc.approve(address(vault), 2 ether);
        vault.deposit(1 ether, bob);
        vault.mint(vault.previewDeposit(0.5 ether), bob);
        vm.stopPrank();
        vault.sync();
        assertEq(vault.balanceOf(carol), 0, "deposits are no gain");

        // A deposit that follows a gain pays nothing toward the gain's fee
        _donate(0.01 ether);
        uint256 expected = _expectedFee(2000);
        vm.recordLogs();
        _depositBTC(bob, 10 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 assets;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == FEE_TAKEN) {
                (, assets) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
        assertEq(assets, expected, "the fee of the gain alone");
    }

    function test_noMintOnLoss() public {
        _surplusVault();
        uint256 before = vault.balanceOf(carol);
        _setPrice(120_000e18);
        (uint256 shares,) = _syncFee();
        assertEq(shares, 0);
        assertEq(vault.balanceOf(carol), before, "nothing minted on a loss");
    }

    function test_zeroFeeMintsNothing() public {
        _noTrove();
        _depositBTC(alice, 1 ether);
        vault.sync();
        _donate(0.1 ether);
        (uint256 shares,) = _syncFee();
        assertEq(shares, 0);
        assertEq(vault.lockedProfit(), 0.1 ether, "the whole gain unlocks to holders");
    }

    // Fee shares minted inside harvest, at the sale's own checkpoint
    function test_harvestPaysTheFee() public {
        _activeFee(1000);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        vault.sync();
        _yield(5000e18);
        vm.prank(keeper);
        vault.harvest(type(uint256).max);
        assertGt(vault.balanceOf(carol), 0);
    }

    // An exit and a deposit while profit unlocks change no holder's value, so the next gain pays
    function test_roundTripDuringUnlockKeepsFee() public {
        _noTrove();
        _activeFee(1000);
        _depositBTC(alice, 0.1 ether);
        _depositBTC(bob, 4 ether);
        vault.sync();
        _donate(0.041 ether);
        vault.sync();

        // Bob leaves at the unlocked price and comes back at once with the same BTC
        uint256 shares = vault.balanceOf(bob);
        vm.prank(bob);
        uint256 out = vault.redeem(shares, bob, bob);
        _depositBTC(bob, out);
        assertApproxEqRel(vault.balanceOf(bob), shares, 1e9, "the same shares back");
        assertEq(vault.deficit(), 0, "no loss to win back");

        vm.warp(vm.getBlockTimestamp() + 7 days);
        _donate(0.041 ether);
        (, uint256 assets) = _syncFee();
        assertEq(assets, 0.0041 ether, "a tenth of the new gain");
    }
}
