// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Cumulative fill bookkeeping of the queue, no token so it can be fuzzed on its own
library QueueMath {
    using Math for uint256;

    struct Fill {
        uint128 shares;
        uint128 assets;
    }

    // BTC owed to the queued share range (from, to], exact at every fill boundary
    function paid(Fill[] storage fills, uint256 from, uint256 to) internal view returns (uint256) {
        return filledAssets(fills, to) - filledAssets(fills, from);
    }

    // BTC paid for the first x queued shares, fills[0] is the (0, 0) sentinel
    function filledAssets(Fill[] storage fills, uint256 x) internal view returns (uint256) {
        if (x == 0) return 0;
        uint256 low = 1;
        uint256 high = fills.length - 1;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (fills[mid].shares < x) low = mid + 1;
            else high = mid;
        }
        Fill memory a = fills[low - 1];
        Fill memory b = fills[low];
        return a.assets + (x - a.shares).mulDiv(b.assets - a.assets, b.shares - a.shares);
    }
}
