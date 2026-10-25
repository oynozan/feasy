// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {QueueMath} from "../src/QueueMath.sol";

// Keeps the cumulative fills like RedeemQueue, index 0 is the (0, 0) sentinel
contract QueueMathHarness {
    QueueMath.Fill[] private _fills;

    constructor() {
        _fills.push();
    }

    // The append of RedeemQueue.fill, taking this fill's own shares and BTC
    function push(uint256 shares, uint256 assets) external {
        QueueMath.Fill memory top = _fills[_fills.length - 1];
        _fills.push(
            QueueMath.Fill(
                SafeCast.toUint128(top.shares + shares), SafeCast.toUint128(top.assets + assets)
            )
        );
    }

    function paid(uint256 from, uint256 to) external view returns (uint256) {
        return QueueMath.paid(_fills, from, to);
    }

    function filledAssets(uint256 x) external view returns (uint256) {
        return QueueMath.filledAssets(_fills, x);
    }

    function last() external view returns (uint256 shares, uint256 assets) {
        QueueMath.Fill memory top = _fills[_fills.length - 1];
        return (top.shares, top.assets);
    }
}

// Realistic sizes and an exact reference, shared by the fuzz tests and the handler
abstract contract QueueMathBase is Test {
    // 21,000,000 BTC in wei
    uint256 internal constant MAX_ASSETS = 2.1e25;
    // The same BTC in share units, the vault's decimals offset gives 1e6 units per wei at par
    uint256 internal constant MAX_SHARES = 2.1e31;

    QueueMathHarness internal q;
    // The harness fills again, cumulative with the sentinel, for the reference math
    uint256[] internal cumShares;
    uint256[] internal cumAssets;

    function _deploy() internal {
        q = new QueueMathHarness();
        cumShares.push(0);
        cumAssets.push(0);
    }

    function _push(uint256 shares, uint256 assets) internal {
        q.push(shares, assets);
        cumShares.push(cumShares[cumShares.length - 1] + shares);
        cumAssets.push(cumAssets[cumAssets.length - 1] + assets);
    }

    function _filled() internal view returns (uint256 shares, uint256 assets) {
        return (cumShares[cumShares.length - 1], cumAssets[cumAssets.length - 1]);
    }

    // Spreads a seed over every order of magnitude, so dust and whole-supply sizes both come up
    function _pick(uint256 seed, uint256 min, uint256 max) internal pure returns (uint256) {
        return bound(seed >> 8, min, Math.max(min, Math.min(max, 10 ** (seed % 33))));
    }

    // Exact BTC owed to the first x shares as whole wei plus rem over width, by linear scan
    function _exact(uint256 x) internal view returns (uint256 whole, uint256 rem, uint256 width) {
        if (x == 0) return (0, 0, 1);
        for (uint256 k = 1; k < cumShares.length; k++) {
            if (x <= cumShares[k]) {
                width = cumShares[k] - cumShares[k - 1];
                uint256 num = (x - cumShares[k - 1]) * (cumAssets[k] - cumAssets[k - 1]);
                return (cumAssets[k - 1] + num / width, num % width, width);
            }
        }
        revert("past the last fill");
    }

    function _reference(uint256 x) internal view returns (uint256 whole) {
        (whole,,) = _exact(x);
    }

    // Floor and ceiling of the exact BTC the fills paid for the share range (from, to]
    function _exactBounds(uint256 from, uint256 to) internal view returns (uint256 lo, uint256 hi) {
        (uint256 wholeTo, uint256 remTo, uint256 widthTo) = _exact(to);
        (uint256 wholeFrom, uint256 remFrom, uint256 widthFrom) = _exact(from);
        uint256 fracTo = remTo * widthFrom;
        uint256 fracFrom = remFrom * widthTo;
        lo = wholeTo - wholeFrom - (fracTo < fracFrom ? 1 : 0);
        hi = wholeTo - wholeFrom + (fracTo > fracFrom ? 1 : 0);
    }
}

contract QueueMathTest is QueueMathBase {
    uint256 internal constant FILLS = 12;

    function setUp() public {
        _deploy();
    }

    /* Unit */

    function test_roundingNeverStrandsDust() public {
        // Three share units split two wei, each claim takes the floor of its running total
        _push(3, 2);
        assertEq(q.paid(0, 1), 0);
        assertEq(q.paid(1, 2), 1);
        assertEq(q.paid(2, 3), 1);
        assertEq(q.paid(0, 3), 2);
    }

    function test_dustRequestZeroFillKeepsLaterClaimsExact() public {
        // A 1 BTC request filled at par, then a one-unit dust request the vault fills for 0 BTC
        _push(1e24, 1e18);
        _push(1, 0);
        uint256 dustEnd = 1e24 + 1;
        assertEq(q.paid(0, 1e24), 1e18);
        assertEq(q.paid(1e24, dustEnd), 0);
        // A third request filled in two parts and claimed after each
        _push(1e23, 1e17 + 1);
        assertEq(q.paid(dustEnd, dustEnd + 1e23), 1e17 + 1);
        _push(2e23, 2e17);
        assertEq(q.paid(dustEnd + 1e23, dustEnd + 2e23), 1e17);
        assertEq(q.paid(dustEnd + 2e23, dustEnd + 3e23), 1e17);
        assertEq(q.paid(0, dustEnd + 3e23), 13e17 + 1);
        assertEq(q.filledAssets(1e24), 1e18);
        assertEq(q.filledAssets(dustEnd), 1e18);
    }

    /* Fuzz */

    function testFuzz_partitionClaimsSumToLastFill(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 count,
        uint256[8] memory cutSeeds
    ) public {
        _pushRandom(shareSeeds, assetSeeds, 0, bound(count, 1, FILLS));
        (uint256 filledShares, uint256 filledAssets) = _filled();
        uint256[] memory cuts = new uint256[](cutSeeds.length + 2);
        for (uint256 i; i < cutSeeds.length; i++) {
            cuts[i + 1] = _point(cutSeeds[i], filledShares);
        }
        cuts[cuts.length - 1] = filledShares;
        _sort(cuts);
        // Every piece is a claim paid out of reserved, so reserved must land on exactly zero
        uint256 reserved = filledAssets;
        for (uint256 i = 1; i < cuts.length; i++) {
            reserved -= q.paid(cuts[i - 1], cuts[i]);
        }
        assertEq(reserved, 0, "claims do not sum to the last fill");
    }

    function testFuzz_filledAssetsMonotoneAndExactAtBoundaries(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 count,
        uint256[8] memory pointSeeds
    ) public {
        _pushRandom(shareSeeds, assetSeeds, 0, bound(count, 1, FILLS));
        (uint256 filledShares,) = _filled();
        for (uint256 k; k < cumShares.length; k++) {
            assertEq(q.filledAssets(cumShares[k]), cumAssets[k], "inexact at a fill boundary");
        }
        uint256[] memory xs = new uint256[](pointSeeds.length);
        for (uint256 i; i < xs.length; i++) {
            xs[i] = _point(pointSeeds[i], filledShares);
        }
        _sort(xs);
        uint256 prev;
        for (uint256 i; i < xs.length; i++) {
            uint256 value = q.filledAssets(xs[i]);
            assertGe(value, prev, "not monotone");
            prev = value;
        }
    }

    function testFuzz_filledAssetsMatchesLinearScan(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 count,
        uint256[8] memory pointSeeds
    ) public {
        _pushRandom(shareSeeds, assetSeeds, 0, bound(count, 1, FILLS));
        (uint256 filledShares,) = _filled();
        for (uint256 i; i < pointSeeds.length; i++) {
            uint256 x = _point(pointSeeds[i], filledShares);
            assertEq(q.filledAssets(x), _reference(x), "binary search picked the wrong fill");
        }
    }

    function testFuzz_zeroBtcFillKeepsLaterClaimsExact(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 at,
        uint256 dustSeed,
        uint256[8] memory pointSeeds
    ) public {
        at = bound(at, 0, FILLS - 2);
        uint256 dust = _pick(dustSeed, 1, MAX_SHARES / FILLS);
        // The same fills without the 0 BTC one
        QueueMathHarness plain = new QueueMathHarness();
        for (uint256 i; i < FILLS - 1; i++) {
            if (i == at) _push(dust, 0);
            uint256 shares = _pick(shareSeeds[i], 1, MAX_SHARES / FILLS);
            uint256 assets = _pick(assetSeeds[i], 0, MAX_ASSETS / FILLS);
            _push(shares, assets);
            plain.push(shares, assets);
        }
        uint256 zeroStart = cumShares[at];
        uint256 zeroEnd = cumShares[at + 1];
        (uint256 filledShares, uint256 filledAssets) = _filled();
        assertEq(q.paid(zeroStart, zeroEnd), 0, "the dust range was paid");
        for (uint256 i; i < pointSeeds.length; i++) {
            uint256 x = _point(pointSeeds[i], filledShares);
            uint256 expected = x <= zeroStart
                ? plain.filledAssets(x)
                : x <= zeroEnd ? cumAssets[at] : plain.filledAssets(x - dust);
            assertEq(q.filledAssets(x), expected, "the 0 BTC fill moved what a share is owed");
        }
        for (uint256 k = at + 2; k < cumShares.length; k++) {
            assertEq(
                q.paid(cumShares[k - 1], cumShares[k]),
                cumAssets[k] - cumAssets[k - 1],
                "a later fill did not pay its own BTC"
            );
        }
        assertEq(q.paid(0, filledShares), filledAssets);
    }

    function testFuzz_paidIsDifferenceOfFilledAssets(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 count,
        uint256 fromSeed,
        uint256 toSeed
    ) public {
        _pushRandom(shareSeeds, assetSeeds, 0, bound(count, 1, FILLS));
        (uint256 from, uint256 to) = _range(fromSeed, toSeed);
        uint256 got = q.paid(from, to);
        assertEq(got, q.filledAssets(to) - q.filledAssets(from));
        assertEq(got, _reference(to) - _reference(from));
        assertEq(q.paid(from, from), 0);
        assertEq(q.paid(to, to), 0);
    }

    function testFuzz_paidWithinOneWeiOfExactShare(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 count,
        uint256 fromSeed,
        uint256 toSeed
    ) public {
        _pushRandom(shareSeeds, assetSeeds, 0, bound(count, 1, FILLS));
        (uint256 from, uint256 to) = _range(fromSeed, toSeed);
        (uint256 lo, uint256 hi) = _exactBounds(from, to);
        uint256 got = q.paid(from, to);
        assertGe(got, lo, "pays under the floor of its exact share");
        assertLe(got, hi, "pays over its exact share rounded up");
    }

    function testFuzz_laterFillsKeepEarlierValues(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 split,
        uint256[8] memory pointSeeds
    ) public {
        split = bound(split, 1, FILLS - 1);
        _pushRandom(shareSeeds, assetSeeds, 0, split);
        (uint256 filledShares,) = _filled();
        uint256[] memory xs = new uint256[](pointSeeds.length);
        uint256[] memory earlier = new uint256[](pointSeeds.length);
        for (uint256 i; i < xs.length; i++) {
            xs[i] = _point(pointSeeds[i], filledShares);
            earlier[i] = q.filledAssets(xs[i]);
        }
        _pushRandom(shareSeeds, assetSeeds, split, FILLS);
        for (uint256 i; i < xs.length; i++) {
            assertEq(q.filledAssets(xs[i]), earlier[i], "a later fill re-priced an earlier claim");
        }
    }

    /* Helpers */

    function _pushRandom(
        uint256[FILLS] memory shareSeeds,
        uint256[FILLS] memory assetSeeds,
        uint256 from,
        uint256 to
    ) internal {
        for (uint256 i = from; i < to; i++) {
            _push(
                _pick(shareSeeds[i], 1, MAX_SHARES / FILLS),
                _pick(assetSeeds[i], 0, MAX_ASSETS / FILLS)
            );
        }
    }

    // A share position up to filled, half the time on or next to a fill boundary
    function _point(uint256 seed, uint256 filled) internal view returns (uint256) {
        uint256 edge = cumShares[bound(seed >> 3, 0, cumShares.length - 1)];
        uint256 mode = seed % 6;
        if (mode == 0) return edge;
        if (mode == 1) return Math.min(edge + 1, filled);
        if (mode == 2) return edge == 0 ? 0 : edge - 1;
        return bound(seed >> 3, 0, filled);
    }

    function _range(uint256 fromSeed, uint256 toSeed)
        internal
        view
        returns (uint256 from, uint256 to)
    {
        (uint256 filledShares,) = _filled();
        uint256 a = _point(fromSeed, filledShares);
        uint256 b = _point(toSeed, filledShares);
        (from, to) = a <= b ? (a, b) : (b, a);
    }

    function _sort(uint256[] memory a) internal pure {
        for (uint256 i = 1; i < a.length; i++) {
            uint256 value = a[i];
            uint256 j = i;
            for (; j > 0 && a[j - 1] > value; j--) {
                a[j] = a[j - 1];
            }
            a[j] = value;
        }
    }
}

// RedeemQueue's bookkeeping, with fills priced like Vault._fillQueue
contract QueueHandler is QueueMathBase {
    using Math for uint256;

    uint256 internal constant MAX_CLAIMS = 16;
    uint256 internal constant VIRTUAL_SHARES = 1e6;

    struct Request {
        uint256 start;
        uint256 end;
        uint256 claimed;
        uint256 paidOut;
    }

    // Index 0 is a sentinel like in RedeemQueue, so ids start at 1
    Request[] internal _requests;
    uint256 public queuedShares;
    uint256 public filledShares;
    uint256 public reserved;
    uint256 public claimedAssets;
    // Claims beyond their own share range or outside the floor and ceiling of its exact BTC
    uint256 public badClaims;
    // Claims that paid out shares while an earlier request still waited
    uint256 public unfairClaims;

    constructor() {
        _deploy();
        _requests.push();
    }

    /* Actions */

    function request(uint256 sharesSeed) external {
        uint256 room = MAX_SHARES - queuedShares;
        if (room == 0) return;
        uint256 shares = _pick(sharesSeed, 1, room);
        uint256 start = queuedShares;
        queuedShares = start + shares;
        _requests.push(Request(start, start + shares, start, 0));
    }

    // A third empty the queue, a quarter pay 0 BTC, the rest pay the vault's floor price
    function fill(uint256 sharesSeed, uint256 navSeed, uint256 supplySeed, uint256 mode) external {
        uint256 pending = queuedShares - filledShares;
        if (pending == 0) return;
        uint256 shares = mode % 3 == 0 ? pending : _pick(sharesSeed, 1, pending);
        uint256 assets;
        if ((mode / 3) % 4 != 0) {
            // What the vault holds plus what it already paid out stays within all 21M BTC
            (, uint256 paidIn) = _filled();
            uint256 nav = _pick(navSeed, 0, MAX_ASSETS - paidIn);
            // Escrowed shares stay in the supply until the fill burns them
            uint256 supply = pending + _pick(supplySeed, 0, MAX_SHARES - pending);
            assets = shares.mulDiv(nav + 1, supply + VIRTUAL_SHARES);
        }
        filledShares += shares;
        reserved += assets;
        _push(shares, assets);
    }

    function claim(uint256 idSeed, uint256 countSeed) external {
        uint256 lastId = _requests.length - 1;
        if (lastId == 0) return;
        uint256 count = bound(countSeed, 1, MAX_CLAIMS);
        for (uint256 i; i < count; i++) {
            _claim(bound(uint256(keccak256(abi.encode(idSeed, i))), 1, lastId));
        }
    }

    // RedeemQueue._claim without the BTC transfer
    function _claim(uint256 id) internal {
        Request storage r = _requests[id];
        uint256 from = r.claimed;
        uint256 to = Math.min(r.end, filledShares);
        if (to <= from) return;
        uint256 assets = q.paid(from, to);
        for (uint256 j = 1; j < id; j++) {
            if (_requests[j].end > filledShares) unfairClaims++;
        }
        (uint256 lo, uint256 hi) = _exactBounds(from, to);
        if (from < r.start || to > r.end || assets < lo || assets > hi) badClaims++;
        r.claimed = to;
        reserved -= assets;
        claimedAssets += assets;
        r.paidOut += assets;
    }

    /* Views */

    function harness() external view returns (QueueMathHarness) {
        return q;
    }

    function filledAssets() external view returns (uint256 assets) {
        (, assets) = _filled();
    }

    function requestCount() external view returns (uint256) {
        return _requests.length - 1;
    }

    function getRequest(uint256 id) external view returns (Request memory) {
        return _requests[id];
    }

    // RedeemQueue.claimableRedeem
    function claimable(uint256 id) external view returns (uint256) {
        Request memory r = _requests[id];
        uint256 to = Math.min(r.end, filledShares);
        return to > r.claimed ? q.paid(r.claimed, to) : 0;
    }

    // RedeemQueue.pendingRedeem
    function pendingRedeem(uint256 id) external view returns (uint256) {
        Request memory r = _requests[id];
        return r.end - Math.max(r.claimed, Math.min(r.end, filledShares));
    }

    function exactBounds(uint256 from, uint256 to) external view returns (uint256, uint256) {
        return _exactBounds(from, to);
    }
}

contract QueueMathInvariantTest is Test {
    QueueHandler internal handler;
    QueueMathHarness internal q;

    function setUp() public {
        handler = new QueueHandler();
        q = handler.harness();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = QueueHandler.request.selector;
        selectors[1] = QueueHandler.fill.selector;
        selectors[2] = QueueHandler.claim.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_claimablePlusClaimedEqualsFilled() public view {
        (uint256 shares, uint256 assets) = q.last();
        assertEq(shares, handler.filledShares(), "last fill shares");
        assertEq(assets, handler.filledAssets(), "last fill assets");
        assertEq(_claimable() + handler.claimedAssets(), assets, "claimable plus claimed");
    }

    function invariant_reservedEqualsFilledMinusClaimed() public view {
        (, uint256 assets) = q.last();
        uint256 reserved = handler.reserved();
        assertEq(reserved, assets - handler.claimedAssets(), "reserved");
        assertEq(reserved, _claimable(), "reserved is not what is left to claim");
    }

    function invariant_noRequestPaidBeforeEarlierFilled() public view {
        assertEq(handler.unfairClaims(), 0, "a claim paid ahead of an earlier request");
        uint256 filled = handler.filledShares();
        uint256 waiting;
        bool earlierFilled = true;
        for (uint256 id = 1; id <= handler.requestCount(); id++) {
            QueueHandler.Request memory r = handler.getRequest(id);
            if (Math.min(r.end, filled) > r.start) {
                assertTrue(earlierFilled, "filled ahead of an earlier request");
            } else {
                assertEq(r.claimed, r.start, "claimed before it was reached");
                assertEq(r.paidOut, 0, "paid before it was reached");
                assertEq(handler.claimable(id), 0, "claimable before it was reached");
            }
            uint256 left = handler.pendingRedeem(id);
            waiting += left;
            earlierFilled = earlierFilled && left == 0;
        }
        assertEq(waiting, handler.queuedShares() - filled, "pending shares");
    }

    function invariant_claimsWithinShareRange() public view {
        assertEq(handler.badClaims(), 0, "a claim paid outside its share range");
        uint256 filled = handler.filledShares();
        for (uint256 id = 1; id <= handler.requestCount(); id++) {
            QueueHandler.Request memory r = handler.getRequest(id);
            uint256 to = Math.min(r.end, filled);
            assertGe(r.claimed, r.start, "claimed below its start");
            assertLe(r.claimed, Math.max(r.start, to), "claimed past its filled end");
            if (to > r.start) {
                (uint256 lo, uint256 hi) = handler.exactBounds(r.start, to);
                uint256 owed = r.paidOut + handler.claimable(id);
                assertGe(owed, lo, "owed under the floor of its exact share");
                assertLe(owed, hi, "owed over its exact share rounded up");
            }
        }
    }

    function _claimable() internal view returns (uint256 sum) {
        for (uint256 id = 1; id <= handler.requestCount(); id++) {
            sum += handler.claimable(id);
        }
    }
}
