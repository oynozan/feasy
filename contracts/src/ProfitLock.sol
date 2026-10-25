// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Linear release of vault profit, pure so it can be fuzzed without Mezo
library ProfitLock {
    using Math for uint256;

    struct Profit {
        uint128 locked;
        uint64 lockedAt;
        uint64 unlockAt;
    }

    // Profit still locked at time, it falls linearly to zero at unlockAt
    function remaining(Profit memory p, uint256 time) internal pure returns (uint256) {
        if (p.locked == 0 || time >= p.unlockAt) return 0;
        return uint256(p.locked).mulDiv(p.unlockAt - time, p.unlockAt - p.lockedAt);
    }

    // Gains since the last checkpoint stay hidden and losses show at once
    function unlocked(Profit memory p, uint256 recorded, uint256 raw, uint256 time)
        internal
        pure
        returns (uint256)
    {
        return Math.min(raw, recorded.saturatingSub(remaining(p, time)));
    }

    // Gains lock for the period, a loss uses up locked profit and keeps its end
    function checkpoint(
        Profit memory p,
        uint256 recorded,
        uint256 raw,
        uint256 time,
        uint256 period
    ) internal pure returns (Profit memory next, uint256 gain) {
        uint256 left = remaining(p, time);
        uint256 end = p.unlockAt;
        uint256 locked = left.saturatingSub(recorded.saturatingSub(raw));
        if (raw > recorded) {
            gain = raw - recorded;
            locked = left + gain;
            // Weighted by size, older profit keeps its end and new profit gets the full period
            end = time + (left * end.saturatingSub(time) + gain * period) / locked;
        }
        next = Profit(SafeCast.toUint128(locked), uint64(time), uint64(end));
    }
}
