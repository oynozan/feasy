// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vault} from "vault/Vault.sol";
import {VeSleeve} from "vault/VeSleeve.sol";
import {IHintHelpers, ISavings, IVoter} from "vault/interfaces/IMezo.sol";
import {SleeveBase} from "./SleeveBase.sol";

contract SleeveEdgesTest is SleeveBase {
    function _bootstrap(uint8 lockWeeks, uint256 amount) internal {
        sleeve.setSleeve(2500, type(uint256).max, lockWeeks);
        _depositBTC(alice, amount);
        vault.rebalance();
        _roll(keeper);
    }

    function _nextWeek(uint256 k, bool rebates) internal {
        vm.warp(_epoch(k) + 1 minutes);
        _mezoWeek(rebates);
        vm.warp(_epoch(k) + 1 hours + 1);
    }

    function _ladder() internal {
        sleeve.setSleeve(2500, type(uint256).max, 4);
        for (uint256 k; k < 5; k++) {
            if (k > 0) _nextWeek(k, true);
            if (k < 4) {
                _depositBTC(alice, 1 ether);
                vault.rebalance();
            }
            _roll(keeper);
        }
    }

    // A pool without a gauge is a sleeve that could never vote
    function test_constructorRejectsBadEarn() public {
        vm.expectRevert(VeSleeve.BadSleeve.selector);
        new Vault(
            btc,
            bo,
            IHintHelpers(hints),
            ISavings(address(musd)),
            router,
            factory,
            keeper,
            guardian,
            7 days,
            IVoter(address(voter)),
            "Feasy BTC",
            "fBTC"
        );
    }

    function test_callerChecks() public {
        vm.startPrank(stranger);
        vm.expectRevert(VeSleeve.NotVault.selector);
        sleeve.collect();
        vm.deal(stranger, 1 ether);
        vm.expectRevert(VeSleeve.NotVault.selector);
        sleeve.lock{value: 1 ether}(_epoch(0));
        vm.expectRevert(VeSleeve.NotVault.selector);
        sleeve.tend(0);
        vm.expectRevert(VeSleeve.NotVault.selector);
        sleeve.release(1);
        vm.expectRevert(VeSleeve.NotAllowed.selector);
        sleeve.setSleeve(100, 1 ether, 2);
        vm.stopPrank();

        vm.expectRevert(VeSleeve.BadSleeve.selector);
        sleeve.setSleeve(2501, 1 ether, 2);
        vm.expectRevert(VeSleeve.BadSleeve.selector);
        sleeve.setSleeve(100, 1 ether, 0);
        vm.expectRevert(VeSleeve.BadSleeve.selector);
        sleeve.setSleeve(100, 1 ether, 5);
    }

    // A short gas limit reverts the roll instead of skipping a rung's weekly work
    function test_collectNeedsTheTendBudget() public {
        _bootstrap(2, 1 ether);
        _nextWeek(1, true);
        vm.prank(keeper);
        vm.expectRevert(VeSleeve.LowGas.selector);
        vault.roll{gas: 2_000_000}();
    }

    function test_lockNeedsTheLockBudget() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        vm.prank(keeper);
        vm.expectRevert(Vault.RollGas.selector);
        vault.roll{gas: 2_800_000}();
    }

    function test_noLockInRecoveryMode() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        // A large borrower near the line, so a 10% drop puts the system in Recovery Mode
        uint256 coll = 10_000 ether;
        uint256 debt = coll * _price() / 1.55e18;
        vm.deal(carol, coll);
        vm.prank(carol);
        bo.openTrove{value: coll}(
            (debt - GAS_COMP) * 1e18 / (1e18 + bo.borrowingRate()), address(0), address(0)
        );
        sys.exec(sys.aggregator(), abi.encodeCall(IAggregatorLike.setPrice, (90_000e18)));
        assertTrue(tm.checkRecoveryMode(_price()));
        _roll(keeper);
        assertEq(sleeve.principal(), 0, "no veBTC lock in Recovery Mode");
    }

    // Two rungs of a tiny lock would each fall under the minimum, so it opens one
    function test_tinyLockOpensOneRung() public {
        sleeve.setSleeve(2500, 1.5e14, 4);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        // The open's buy-back spent the BTC held back, a fresh deposit refills it
        _depositBTC(bob, 0.01 ether);
        _roll(keeper);
        (uint256[] memory ids, uint256[] memory amounts,) = _rungs();
        assertEq(ids.length, 1);
        assertEq(amounts[0], 1.5e14);
    }

    // A matured rung waiting for Mezo's period update holds the slot a top-up would use
    function test_waitingRungBlocksTopUp() public {
        _ladder();
        (uint256 waiting,) = _rungAt(_epoch(5));
        assertGt(waiting, 0);
        _nextWeek(5, false);
        _depositBTC(alice, 2 ether);
        vault.rebalance();
        uint256 principal = sleeve.principal();
        assertGt(sleeve.hold(vault.rawAssets()), MIN_RUNG_, "a lock is due");
        _roll(keeper);
        assertEq(sleeve.principal(), principal, "the lock waits");
        (uint256 kept,) = _rungAt(_epoch(5));
        assertEq(kept, waiting, "the matured rung still waits for its rebate");
    }

    uint256 constant MIN_RUNG_ = 1e14;
}

interface IAggregatorLike {
    function setPrice(uint256 price) external returns (bool);
}
