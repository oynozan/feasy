// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SleeveBase} from "./SleeveBase.sol";

interface ICheckpoint {
    function checkpoint() external;
}

// Known v7 behaviour, a rebate claim that is veBTC's first write after the flip needs more than CLAIM_GAS
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

    // Flips once a later version checkpoints veBTC inside collect
    function test_known_staleCheckpointSkipsLiveRebates() public {
        (uint256 id4, uint256 id3) = _setUpLadder();
        _roll(keeper);
        assertGt(distributor.claimable(id4), 0, "E4 rebate skipped, still claimable");
        assertGt(distributor.claimable(id3), 0, "E3 rebate skipped, still claimable");
    }

    // Testnet's two week rungs, at the Nov 12 roll the live Nov 19 rung keeps its rebate unclaimed
    function test_known_twoWeekLadderNov12() public {
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
        assertGt(distributor.claimable(live), 0, "Nov 19 rung has a rebate");
        _roll(keeper);
        assertGt(distributor.claimable(live), 0, "skipped, still claimable");
    }

    // The claim alone pays veBTC's global catch-up over the week boundary
    function test_known_staleClaimExceedsClaimGas() public {
        (uint256 id4,) = _setUpLadder();
        uint256 g = gasleft();
        distributor.claim(id4);
        assertGt(g - gasleft(), CLAIM_GAS);
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
}
