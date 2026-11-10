// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Base} from "./Base.sol";
import {SavingsSleeve} from "vault/SavingsSleeve.sol";

interface ISavingsIndex {
    function yieldIndex() external view returns (uint256);
}

interface IInterestHooks {
    function updateSystemInterest() external;
}

interface IPCVLike {
    function distributeMUSD() external;
}

contract SpreadGuardTest is Base {
    uint256 constant YEAR = 365 days;

    uint256 t0;

    // A vault deployed now, so its sleeve has no sMUSD history yet
    function setUp() public override {
        super.setUp();
        vault = _newVault(7 days);
        queue = vault.queue();
        savingsSleeve = vault.savingsSleeve();
        vault.setBorrowingEnabled(true);
        (, t0) = savingsSleeve.snapshots(0);
    }

    function _index() internal view returns (uint256) {
        return ISavingsIndex(savings).yieldIndex();
    }

    function _oldest() internal view returns (uint256 index, uint256 time) {
        uint8 next = (savingsSleeve.latest() + 1) % 4;
        (index, time) = savingsSleeve.snapshots(next);
        if (time == 0) (index, time) = savingsSleeve.snapshots(0);
    }

    // The realized rate from the oldest snapshot, as the sleeve is meant to compute it
    function _rate() internal view returns (uint256) {
        (uint256 index, uint256 time) = _oldest();
        uint256 elapsed = vm.getBlockTimestamp() - time;
        if (elapsed < 1 days) return 0;
        return (_index() - index) * YEAR * 1e4 / (elapsed * 1e18);
    }

    // MUSD that sMUSD holders must still be paid for the realized rate to reach bps
    function _yieldFor(uint256 bps) internal view returns (uint256) {
        (uint256 index, uint256 time) = _oldest();
        uint256 target = bps * (vm.getBlockTimestamp() - time) * 1e18 / (YEAR * 1e4) + 1;
        uint256 have = _index() - index;
        if (have >= target) return 0;
        uint256 supply = IERC20(savings).totalSupply();
        return (target - have) * supply / 1e18 + supply / 1e18 + 1;
    }

    function _open() internal {
        _depositBTC(alice, 2 ether);
        vm.warp(t0 + 1 days);
        _yield(_yieldFor(savingsSleeve.loanRate() + 500));
        vault.rebalance();
        assertTrue(vault.trove().active, "trove open");
    }

    function test_noBorrowBeforeADayOfHistory() public {
        _depositBTC(alice, 2 ether);
        _yield(1000e18);
        assertEq(savingsSleeve.savingsRate(), 0, "no rate inside the first day");
        assertFalse(savingsSleeve.spreadOk());
        vault.rebalance();
        assertFalse(vault.trove().active, "no debt without a rate");

        vm.warp(t0 + 1 days - 1);
        assertEq(savingsSleeve.savingsRate(), 0, "a second short of a day");
        vault.rebalance();
        assertFalse(vault.trove().active);

        vm.warp(t0 + 1 days);
        assertEq(savingsSleeve.savingsRate(), _rate());
        assertGt(savingsSleeve.savingsRate(), savingsSleeve.loanRate());
        vault.rebalance();
        assertTrue(vault.trove().active, "borrows once a day of history beats the loan");
    }

    // MUSD's own interest reaches sMUSD through the PCV, and that realized rate opens the loan
    function test_interestDistributionOpensBorrowing() public {
        _depositBTC(alice, 2 ether);
        vm.warp(t0 + 1 days);
        assertEq(savingsSleeve.savingsRate(), 0, "a day without yield is no rate");
        vault.rebalance();
        assertFalse(vault.trove().active);

        uint256 before = _index();
        IInterestHooks(address(tm)).updateSystemInterest();
        IPCVLike(sys.pcv()).distributeMUSD();
        assertGt(_index(), before, "the whale's interest paid sMUSD holders");
        assertEq(savingsSleeve.savingsRate(), _rate());
        assertGt(savingsSleeve.savingsRate(), savingsSleeve.loanRate(), "beats 1% plus the fee");
        vault.rebalance();
        assertTrue(vault.trove().active);
    }

    function test_rateMustBeatLoanRate() public {
        _depositBTC(alice, 2 ether);
        vm.warp(t0 + 2 days);
        uint256 need = _yieldFor(savingsSleeve.loanRate());
        _yield(need * 9 / 10);
        assertLt(savingsSleeve.savingsRate(), savingsSleeve.loanRate());
        assertFalse(savingsSleeve.spreadOk());
        vault.rebalance();
        assertFalse(vault.trove().active, "a rate under the loan's cost opens nothing");

        _yield(_yieldFor(savingsSleeve.loanRate()));
        assertGe(savingsSleeve.savingsRate(), savingsSleeve.loanRate());
        assertTrue(savingsSleeve.spreadOk());
        vault.rebalance();
        assertTrue(vault.trove().active);
    }

    function test_minSpreadBlocksNewDebt() public {
        _open();
        uint256 headroom = savingsSleeve.savingsRate() - savingsSleeve.loanRate();
        savingsSleeve.setMinSpread(uint16(headroom + 1));
        assertFalse(savingsSleeve.spreadOk());

        _setPrice(130_000e18);
        uint256 debt = vault.trove().debt;
        vault.rebalance();
        assertEq(vault.trove().debt, debt, "no new debt above the band");
        uint256 coll = vault.trove().coll;
        _depositBTC(bob, 0.5 ether);
        vault.rebalance();
        assertEq(vault.trove().debt, debt, "still none");
        assertGt(vault.trove().coll, coll, "spare goes in as collateral");

        savingsSleeve.setMinSpread(0);
        vault.rebalance();
        assertGt(vault.trove().debt, debt, "borrows again once the spread is enough");
        assertApproxEqRel(_ratio(), 2.5e18, 1e16);
    }

    function test_guardianOnlyRaisesMinSpread() public {
        vm.expectEmit(address(savingsSleeve));
        emit SavingsSleeve.MinSpreadSet(50);
        vm.prank(guardian);
        savingsSleeve.setMinSpread(50);
        vm.prank(guardian);
        savingsSleeve.setMinSpread(50);
        vm.prank(guardian);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setMinSpread(49);
        vm.prank(keeper);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setMinSpread(100);
        vm.prank(alice);
        vm.expectRevert(SavingsSleeve.NotAllowed.selector);
        savingsSleeve.setMinSpread(100);
        vm.prank(guardian);
        savingsSleeve.setMinSpread(400);
        assertEq(savingsSleeve.minSpreadBps(), 400);
        savingsSleeve.setMinSpread(0);
        assertEq(savingsSleeve.minSpreadBps(), 0, "the owner may lower it");
    }

    function test_snapshotRing() public {
        (uint192 first,) = savingsSleeve.snapshots(0);
        assertEq(first, _index(), "first snapshot at deployment");
        assertEq(savingsSleeve.latest(), 0);
        savingsSleeve.snapshot();
        assertEq(savingsSleeve.latest(), 0, "nothing new inside the week");

        uint256[6] memory index;
        index[0] = _index();
        for (uint256 k = 1; k < 6; k++) {
            vm.warp(t0 + k * 1 weeks);
            _yield(100e18 * k);
            index[k] = _index();
            vm.expectEmit(address(savingsSleeve));
            emit SavingsSleeve.Snapshotted(index[k], vm.getBlockTimestamp());
            savingsSleeve.snapshot();
            assertEq(savingsSleeve.latest(), k % 4, "the ring moves on");
            (uint192 i, uint64 time) = savingsSleeve.snapshots(k % 4);
            assertEq(i, index[k]);
            assertEq(time, vm.getBlockTimestamp());
            // Three snapshots back once the ring is full, the deployment one before that
            uint256 back = k < 4 ? 0 : k - 3;
            (uint256 oldest, uint256 at) = _oldest();
            assertEq(oldest, index[back], "oldest snapshot");
            assertEq(at, t0 + back * 1 weeks);
            assertEq(savingsSleeve.savingsRate(), _rate());
            savingsSleeve.snapshot();
            assertEq(savingsSleeve.latest(), k % 4, "once a week at most");
        }

        // park takes the weekly snapshot as well
        vm.warp(t0 + 6 weeks);
        vault.rebalance();
        assertEq(savingsSleeve.latest(), 2);
    }

    function test_loanRateMath() public {
        uint256 fee = bo.borrowingRate() / 1e14;
        assertEq(fee, 10, "the 0.1% borrowing fee counts as 10 bps a year");
        assertEq(savingsSleeve.loanRate(), 100 + fee, "MUSD's 1% before the vault borrows");
        _setRate(150);
        assertEq(savingsSleeve.loanRate(), 150 + fee);
        _open();
        assertEq(tm.getTroveInterestRate(address(vault)), 150);
        // A cheaper system rate leaves the trove at its own rate
        _setRate(50);
        assertEq(savingsSleeve.loanRate(), 150 + fee, "the trove's rate");
        _setRate(300);
        assertEq(savingsSleeve.loanRate(), 300 + fee, "a new loan would pay today's rate");
    }
}
