// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SleeveBase} from "./SleeveBase.sol";
import {VeSleeve} from "vault/VeSleeve.sol";

interface ICheckpoint {
    function checkpoint() external;
}

// The first veBTC write after the flip pays its catch-up, so collect checkpoints before the claims
contract RebateCheckpointTest is SleeveBase {
    uint256 constant CLAIM_GAS = 600_000;

    function _setUpLadder() internal returns (uint256 id4, uint256 id3) {
        // Four week rungs end E3 in slot 3 and E4 in slot 0, so E4 is tended first
        sleeve.setSleeve(2500, type(uint256).max, 4);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        _roll(keeper);
        (id4,) = _rungAt(_epoch(4));
        (id3,) = _rungAt(_epoch(3));
        // Mezo's weekly routine at the flip writes nothing to veBTC
        vm.warp(_epoch(1) + 1 minutes);
        _mezoWeek(true);
        vm.warp(_epoch(1) + 1 hours + 1);
        assertGt(distributor.claimable(id4), 0, "E4 rung has a rebate");
        assertGt(distributor.claimable(id3), 0, "E3 rung has a rebate");
    }

    // The roll's own checkpoint lets every live rung claim its rebate
    function test_rollClaimsLiveRebatesAfterFlip() public {
        (uint256 id4, uint256 id3) = _setUpLadder();
        _roll(keeper);
        assertEq(distributor.claimable(id4), 0, "E4 rebate claimed in the roll");
        assertEq(distributor.claimable(id3), 0, "E3 rebate claimed in the roll");
    }

    // Testnet's two week rungs, the Nov 12 roll claims the live Nov 19 rung's rebate
    function test_twoWeekLadderNov12ClaimsLiveRebate() public {
        sleeve.setSleeve(2500, type(uint256).max, 2);
        _depositBTC(alice, 1 ether);
        vault.rebalance();
        _roll(keeper);
        for (uint256 k = 1; k < 4; k++) {
            vm.warp(_epoch(k) + 1 minutes);
            _mezoWeek(true);
            vm.warp(_epoch(k) + 1 hours + 1);
            if (k == 3) break;
            _roll(keeper);
        }
        (uint256 live,) = _rungAt(_epoch(4));
        uint256 rebate = distributor.claimable(live);
        assertGt(rebate, 0, "Nov 19 rung has a rebate");
        uint256 locked = uint256(int256(ve.locked(live).amount));
        _roll(keeper);
        assertEq(distributor.claimable(live), 0, "claimed in the roll");
        assertEq(uint256(int256(ve.locked(live).amount)), locked + rebate, "compounded");
    }

    // On its own the stale claim still costs more than CLAIM_GAS, inside the roll it fits
    function test_staleClaimFitsAfterCollectCheckpoint() public {
        (uint256 id4,) = _setUpLadder();
        uint256 snap = vm.snapshotState();
        uint256 g = gasleft();
        distributor.claim(id4);
        assertGt(g - gasleft(), CLAIM_GAS, "the catch-up alone is over the budget");
        vm.revertToState(snap);
        _roll(keeper);
        assertEq(distributor.claimable(id4), 0, "claimed without a keeper checkpoint");
    }

    // The keeper's checkpoint before each roll lets the roll claim every rebate
    function test_keeperCheckpointFirstClaimsAll() public {
        (uint256 id4, uint256 id3) = _setUpLadder();
        ICheckpoint(address(ve)).checkpoint();
        uint256 snap = vm.snapshotState();
        uint256 g = gasleft();
        distributor.claim(id4);
        assertLt(g - gasleft(), CLAIM_GAS, "fits once checkpointed");
        vm.revertToState(snap);
        _roll(keeper);
        assertEq(distributor.claimable(id4), 0, "E4 rung rebate claimed");
        assertEq(distributor.claimable(id3), 0, "E3 rung rebate claimed");
    }

    function test_collectCheckpointsVeBTC() public {
        _setUpLadder();
        vm.expectCall(address(ve), abi.encodeCall(ICheckpoint.checkpoint, ()), 1);
        _roll(keeper);
    }

    // Without principal there is no rung to claim for, so collect skips the checkpoint
    function test_noCheckpointWithoutPrincipal() public {
        _depositBTC(alice, 1 ether);
        vm.expectCall(address(ve), abi.encodeCall(ICheckpoint.checkpoint, ()), 0);
        vm.prank(stranger);
        vault.roll{gas: 1_000_000}();
    }

    // A gas limit that cannot fund the checkpoint reverts the roll instead of skipping it
    function test_checkpointNeedsItsBudget() public {
        _setUpLadder();
        vm.expectCall(address(ve), abi.encodeCall(ICheckpoint.checkpoint, ()), 0);
        vm.prank(keeper);
        vm.expectRevert(VeSleeve.LowGas.selector);
        vault.roll{gas: 1_000_000}();
    }
}
