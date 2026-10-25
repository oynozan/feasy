// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ProfitLock} from "../src/ProfitLock.sol";

uint256 constant MAX_BTC = 21_000_000e18;
uint256 constant MIN_PERIOD = 1;
uint256 constant MAX_PERIOD = 30 days;
// First of January 2026 and of 2200, in Unix seconds
uint256 constant START = 1_767_225_600;
uint256 constant YEAR_2200 = 7_258_118_400;

// Fuzzed inputs of the history that leads up to the step under test
struct Seed {
    uint256 period;
    uint256 start;
    uint256 base;
    uint256 first;
    uint256 wait;
    uint256 second;
    bool up;
    uint256 flow;
    bool out;
}

// A vault right after an entry point, so raw equals recorded and time is that checkpoint's
struct Book {
    ProfitLock.Profit p;
    uint256 recorded;
    uint256 time;
    uint256 period;
}

contract ProfitLockTest is Test {
    /* Worked examples at the live 7 day period */

    function test_gainUnlocksLinearlyOverThePeriod() public pure {
        // 100 BTC deposited at START, then a 7 BTC payout checkpointed a day later
        ProfitLock.Profit memory p = ProfitLock.Profit(0, uint64(START), 0);
        uint256 t = START + 1 days;
        assertEq(
            ProfitLock.unlocked(p, 100e18, 107e18, t), 100e18, "payout seen before its checkpoint"
        );
        (ProfitLock.Profit memory next, uint256 gain) =
            ProfitLock.checkpoint(p, 100e18, 107e18, t, 7 days);
        assertEq(gain, 7e18, "gain");
        assertEq(uint256(next.locked), 7e18, "locked");
        assertEq(uint256(next.unlockAt), t + 7 days, "unlockAt");
        assertEq(ProfitLock.unlocked(next, 107e18, 107e18, t), 100e18, "at the checkpoint");
        assertEq(ProfitLock.unlocked(next, 107e18, 107e18, t + 1 days), 101e18, "a day in");
        assertEq(ProfitLock.unlocked(next, 107e18, 107e18, t + 84 hours), 103.5e18, "half way");
        assertEq(ProfitLock.unlocked(next, 107e18, 107e18, t + 7 days), 107e18, "at the end");
        assertEq(ProfitLock.unlocked(next, 107e18, 107e18, t + 30 days), 107e18, "after the end");
    }

    function test_lossUsesUpTheLockFirst() public pure {
        ProfitLock.Profit memory p = _weekLock();
        uint256 mid = START + 84 hours;
        // 3.5 BTC is still locked half way, so a 2 BTC loss leaves the price where it was
        assertEq(ProfitLock.unlocked(p, 107e18, 105e18, mid), 103.5e18, "loss reached the price");
        (ProfitLock.Profit memory next, uint256 gain) =
            ProfitLock.checkpoint(p, 107e18, 105e18, mid, 7 days);
        assertEq(gain, 0, "gain");
        assertEq(uint256(next.locked), 1.5e18, "locked");
        assertEq(uint256(next.unlockAt), START + 7 days, "unlockAt");
        assertEq(ProfitLock.unlocked(next, 105e18, 105e18, mid), 103.5e18, "at the checkpoint");
        assertEq(ProfitLock.unlocked(next, 105e18, 105e18, mid + 42 hours), 104.25e18, "half way");
        assertEq(ProfitLock.unlocked(next, 105e18, 105e18, START + 7 days), 105e18, "at the end");
    }

    function test_lossBeyondTheLockLowersThePrice() public pure {
        ProfitLock.Profit memory p = _weekLock();
        uint256 mid = START + 84 hours;
        // A 5 BTC loss is 1.5 BTC more than the lock, and only that excess comes off the price
        assertEq(ProfitLock.unlocked(p, 107e18, 107e18, mid), 103.5e18, "before the loss");
        assertEq(ProfitLock.unlocked(p, 107e18, 102e18, mid), 102e18, "after the loss");
        (ProfitLock.Profit memory next, uint256 gain) =
            ProfitLock.checkpoint(p, 107e18, 102e18, mid, 7 days);
        assertEq(gain, 0, "gain");
        assertEq(uint256(next.locked), 0, "locked");
        assertEq(ProfitLock.unlocked(next, 102e18, 102e18, mid), 102e18, "at the checkpoint");
        assertEq(ProfitLock.unlocked(next, 102e18, 102e18, START + 7 days), 102e18, "at the end");
    }

    function test_newGainMergesAtTheWeightedEnd() public pure {
        ProfitLock.Profit memory p = _weekLock();
        uint256 mid = START + 84 hours;
        // 3.5 BTC with 84 hours left and a 3.5 BTC gain with 168 hours average out at 126 hours
        (ProfitLock.Profit memory next, uint256 gain) =
            ProfitLock.checkpoint(p, 107e18, 110.5e18, mid, 7 days);
        assertEq(gain, 3.5e18, "gain");
        assertEq(uint256(next.locked), 7e18, "locked");
        assertEq(uint256(next.unlockAt), mid + 126 hours, "unlockAt");
        assertEq(ProfitLock.unlocked(next, 110.5e18, 110.5e18, mid), 103.5e18, "at the checkpoint");
        assertEq(ProfitLock.unlocked(next, 110.5e18, 110.5e18, mid + 63 hours), 107e18, "half way");
        assertEq(
            ProfitLock.unlocked(next, 110.5e18, 110.5e18, mid + 126 hours), 110.5e18, "at the end"
        );
    }

    function test_extremeInputsDoNotRevert() public pure {
        uint256 t = YEAR_2200 - MAX_PERIOD;
        ProfitLock.Profit memory empty = ProfitLock.Profit(0, uint64(t), 0);
        // The whole supply donated to an empty vault and locked for the longest period
        (ProfitLock.Profit memory p, uint256 gain) =
            ProfitLock.checkpoint(empty, 0, MAX_BTC, t, MAX_PERIOD);
        assertEq(gain, MAX_BTC, "gain");
        assertEq(uint256(p.unlockAt), YEAR_2200, "unlockAt");
        assertEq(ProfitLock.unlocked(p, MAX_BTC, MAX_BTC, t), 0, "at the checkpoint");
        assertEq(ProfitLock.unlocked(p, MAX_BTC, MAX_BTC, YEAR_2200), MAX_BTC, "at the end");
        // Half the supply locked, then the other half gained a second later
        (ProfitLock.Profit memory half,) =
            ProfitLock.checkpoint(empty, 0, MAX_BTC / 2, t, MAX_PERIOD);
        (ProfitLock.Profit memory merged,) =
            ProfitLock.checkpoint(half, MAX_BTC / 2, MAX_BTC, t + 1, MAX_PERIOD);
        assertLe(uint256(merged.locked), MAX_BTC, "merged lock");
        assertLe(uint256(merged.unlockAt), t + 1 + MAX_PERIOD, "merged end");
        // Everything lost while the whole supply is locked
        (ProfitLock.Profit memory gone,) = ProfitLock.checkpoint(p, MAX_BTC, 0, t + 1, MAX_PERIOD);
        assertEq(uint256(gone.locked), 0, "lock after a total loss");
        assertEq(ProfitLock.unlocked(gone, 0, 0, t + 1), 0, "unlocked after a total loss");
        // The shortest period with the whole supply, one second before 2200
        (ProfitLock.Profit memory quick,) = ProfitLock.checkpoint(
            ProfitLock.Profit(0, uint64(YEAR_2200 - 1), 0), 0, MAX_BTC, YEAR_2200 - 1, MIN_PERIOD
        );
        assertEq(ProfitLock.remaining(quick, YEAR_2200 - 1), MAX_BTC, "start of a 1 s lock");
        assertEq(ProfitLock.remaining(quick, YEAR_2200), 0, "end of a 1 s lock");
    }

    /* P1, a checkpoint leaves the unlocked total where it was */

    function testFuzz_continuityOnGain(Seed memory s, uint256 later, uint256 gain) public pure {
        Book memory b = _reach(s);
        vm.assume(b.recorded < MAX_BTC);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        uint256 raw = b.recorded + bound(gain, 1, MAX_BTC - b.recorded);
        uint256 left = ProfitLock.remaining(b.p, time);
        uint256 flat = ProfitLock.unlocked(b.p, b.recorded, b.recorded, time);
        assertEq(ProfitLock.unlocked(b.p, b.recorded, raw, time), flat, "gain shown early");
        (ProfitLock.Profit memory next, uint256 gained) =
            _continuousCheckpoint(b.p, b.recorded, raw, time, b.period);
        assertEq(gained, raw - b.recorded, "gain");
        assertEq(uint256(next.locked), left + gained, "lock did not grow by the gain");
    }

    function testFuzz_continuityOnLossWithinLock(Seed memory s, uint256 later, uint256 loss)
        public
        pure
    {
        Book memory b = _reach(s);
        vm.assume(b.p.unlockAt > b.time);
        uint256 time = b.time + bound(later, 0, b.p.unlockAt - b.time - 1);
        uint256 left = ProfitLock.remaining(b.p, time);
        vm.assume(left > 0);
        loss = bound(loss, 1, left);
        uint256 raw = b.recorded - loss;
        uint256 flat = ProfitLock.unlocked(b.p, b.recorded, b.recorded, time);
        assertEq(
            ProfitLock.unlocked(b.p, b.recorded, raw, time), flat, "covered loss hit the price"
        );
        (ProfitLock.Profit memory next, uint256 gained) =
            _continuousCheckpoint(b.p, b.recorded, raw, time, b.period);
        assertEq(gained, 0, "loss read as a gain");
        assertEq(uint256(next.locked), left - loss, "lock did not absorb the loss");
        assertEq(uint256(next.unlockAt), uint256(b.p.unlockAt), "loss moved the end");
    }

    function testFuzz_continuityOnLossBeyondLock(Seed memory s, uint256 later, uint256 loss)
        public
        pure
    {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        uint256 left = ProfitLock.remaining(b.p, time);
        vm.assume(b.recorded > left);
        loss = bound(loss, left + 1, b.recorded);
        uint256 raw = b.recorded - loss;
        uint256 flat = ProfitLock.unlocked(b.p, b.recorded, b.recorded, time);
        assertEq(
            flat - ProfitLock.unlocked(b.p, b.recorded, raw, time),
            loss - left,
            "price did not fall by exactly the excess"
        );
        (ProfitLock.Profit memory next, uint256 gained) =
            _continuousCheckpoint(b.p, b.recorded, raw, time, b.period);
        assertEq(gained, 0, "loss read as a gain");
        assertEq(uint256(next.locked), 0, "lock outlived a larger loss");
    }

    function testFuzz_continuityWithNothingLocked(
        Seed memory s,
        bool fresh,
        uint256 later,
        uint256 raw
    ) public pure {
        Book memory b = _reach(s);
        // A vault whose checkpoints never saw a gain
        if (fresh) b.p = ProfitLock.Profit(0, uint64(b.time), 0);
        uint256 time = Math.max(b.time, b.p.unlockAt) + bound(later, 0, 2 * b.period);
        assertEq(ProfitLock.remaining(b.p, time), 0, "lock not empty");
        raw = bound(raw, 0, MAX_BTC);
        (ProfitLock.Profit memory next, uint256 gained) =
            _continuousCheckpoint(b.p, b.recorded, raw, time, b.period);
        assertEq(
            raw - next.locked, Math.min(raw, b.recorded), "total is not raw capped at recorded"
        );
        assertEq(gained, raw > b.recorded ? raw - b.recorded : 0, "gain");
        assertEq(uint256(next.locked), gained, "lock is not the new gain");
        if (gained > 0) {
            assertEq(uint256(next.unlockAt), time + b.period, "lone gain not locked one period");
        }
    }

    /* P2, between checkpoints the release only moves forward */

    function testFuzz_unlockedNeverFallsWithTime(
        Seed memory s,
        uint256 raw,
        uint256 later,
        uint256 gap
    ) public pure {
        Book memory b = _reach(s);
        uint256 t1 = b.time + bound(later, 0, 2 * b.period);
        uint256 t2 = t1 + bound(gap, 0, 2 * b.period);
        assertGe(
            b.recorded - ProfitLock.remaining(b.p, t2),
            b.recorded - ProfitLock.remaining(b.p, t1),
            "release went backwards"
        );
        raw = bound(raw, 0, MAX_BTC);
        assertGe(
            ProfitLock.unlocked(b.p, b.recorded, raw, t2),
            ProfitLock.unlocked(b.p, b.recorded, raw, t1),
            "unlocked total fell with time"
        );
    }

    /* P3 */

    function testFuzz_unlockedNeverAboveRaw(Seed memory s, uint256 later, uint256 raw) public pure {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        raw = bound(raw, 0, MAX_BTC);
        uint256 unlocked = ProfitLock.unlocked(b.p, b.recorded, raw, time);
        assertLe(unlocked, raw, "unlocked above raw");
        assertLe(unlocked, b.recorded - ProfitLock.remaining(b.p, time), "pending gain unlocked");
    }

    /* P4 */

    function testFuzz_lockedNeverAboveRecorded(
        Seed memory s,
        uint256 later,
        uint256 raw,
        uint256 amount,
        bool out,
        uint256 after_
    ) public pure {
        Book memory b = _reach(s);
        assertLe(b.p.locked, b.recorded, "after the seeded history");
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        raw = bound(raw, 0, MAX_BTC);
        (ProfitLock.Profit memory p,) = ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        assertLe(p.locked, raw, "after a checkpoint");
        // An exit is capped by the unlocked total as the view reports it
        uint256 recorded = out
            ? raw - bound(amount, 0, ProfitLock.unlocked(p, raw, raw, time))
            : raw + bound(amount, 0, MAX_BTC - raw);
        assertLe(p.locked, recorded, "after a deposit or exit");
        uint256 t2 = time + bound(after_, 0, 2 * b.period);
        assertLe(ProfitLock.remaining(p, t2), recorded, "later in the same lock");
    }

    /* P5, a deposit or exit moves the unlocked total by its amount and leaves the lock alone */

    function testFuzz_depositMovesUnlockedByItsAmount(
        Seed memory s,
        uint256 later,
        uint256 raw,
        uint256 amount,
        uint256 after_,
        uint256 move,
        bool up
    ) public pure {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        raw = bound(raw, 0, MAX_BTC);
        // The deposit's own checkpoint comes first, as in depositBTC, deposit and mint
        (ProfitLock.Profit memory p,) = ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        amount = bound(amount, 0, MAX_BTC - raw);
        _assertNoPhantom(p, raw + amount, time, b.period);
        _assertApartBy(p, raw, raw, amount, time, b.period);
        // The same later gain or loss in a vault with and without the deposit
        uint256 t2 = time + bound(after_, 0, 2 * b.period);
        uint256 moved =
            up ? raw + bound(move, 0, MAX_BTC - raw - amount) : raw - bound(move, 0, raw);
        _assertApartBy(p, raw, moved, amount, t2, b.period);
    }

    function testFuzz_exitMovesUnlockedByItsAmount(
        Seed memory s,
        uint256 later,
        uint256 raw,
        uint256 amount,
        uint256 after_,
        uint256 move,
        bool up
    ) public pure {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        raw = bound(raw, 0, MAX_BTC);
        // The exit's own checkpoint comes first, as in withdraw, redeem and every queue fill
        (ProfitLock.Profit memory p,) = ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        amount = bound(amount, 0, ProfitLock.unlocked(p, raw, raw, time));
        uint256 rest = raw - amount;
        _assertNoPhantom(p, rest, time, b.period);
        _assertApartBy(p, rest, rest, amount, time, b.period);
        // The same later gain or loss in a vault with and without the exit
        uint256 t2 = time + bound(after_, 0, 2 * b.period);
        uint256 moved = up ? rest + bound(move, 0, MAX_BTC - raw) : rest - bound(move, 0, rest);
        _assertApartBy(p, rest, moved, amount, t2, b.period);
    }

    /* P6, the lock's ends, a gain's period, a loss's end and no reverts */

    function testFuzz_lockFullAtStartEmptyAtEnd(Seed memory s, uint256 later) public pure {
        Book memory b = _reach(s);
        ProfitLock.Profit memory p = b.p;
        assertEq(ProfitLock.remaining(p, p.lockedAt), p.locked, "not full at lockedAt");
        assertEq(ProfitLock.remaining(p, p.unlockAt), 0, "not empty at unlockAt");
        uint256 end = Math.max(p.lockedAt, p.unlockAt);
        uint256 t = end + bound(later, 0, YEAR_2200 - end);
        assertEq(ProfitLock.remaining(p, t), 0, "not empty after unlockAt");
        // A live lock has a length, so remaining never divides by zero
        if (p.locked > 0) {
            assertGt(uint256(p.unlockAt), uint256(p.lockedAt), "live lock with no length");
            assertLe(uint256(p.unlockAt), p.lockedAt + b.period, "lock longer than the period");
        }
    }

    function testFuzz_gainReleasedWithinItsPeriod(Seed memory s, uint256 later, uint256 gain)
        public
        pure
    {
        Book memory b = _reach(s);
        vm.assume(b.recorded < MAX_BTC);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        uint256 raw = b.recorded + bound(gain, 1, MAX_BTC - b.recorded);
        (ProfitLock.Profit memory next,) =
            ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        assertGt(uint256(next.unlockAt), time, "gain locked for no time");
        assertLe(uint256(next.unlockAt), time + b.period, "gain outlasts its period");
        assertEq(ProfitLock.remaining(next, time + b.period), 0, "lock left a period later");
        assertEq(ProfitLock.unlocked(next, raw, raw, time + b.period), raw, "raw not all unlocked");
    }

    function testFuzz_lossKeepsTheEnd(Seed memory s, uint256 later, uint256 loss) public pure {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        loss = bound(loss, 0, b.recorded);
        uint256 left = ProfitLock.remaining(b.p, time);
        (ProfitLock.Profit memory next, uint256 gained) =
            ProfitLock.checkpoint(b.p, b.recorded, b.recorded - loss, time, b.period);
        assertEq(gained, 0, "loss read as a gain");
        assertEq(uint256(next.unlockAt), uint256(b.p.unlockAt), "loss moved unlockAt");
        assertEq(uint256(next.lockedAt), time, "lock did not restart now");
        assertEq(
            uint256(next.locked), left > loss ? left - loss : 0, "loss not taken from the lock"
        );
    }

    /* Beyond P1 to P6, the weighted end and no early release from a gain or an idle sync */

    function testFuzz_gainMovesEndToWeightedAverage(Seed memory s, uint256 later, uint256 gain)
        public
        pure
    {
        Book memory b = _reach(s);
        vm.assume(b.recorded < MAX_BTC);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        uint256 raw = b.recorded + bound(gain, 1, MAX_BTC - b.recorded);
        uint256 left = ProfitLock.remaining(b.p, time);
        (ProfitLock.Profit memory next, uint256 gained) =
            ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        // BTC seconds still to release, the old lock to its own end plus the gain over a period
        uint256 owed = left * (Math.max(b.p.unlockAt, time) - time) + gained * b.period;
        uint256 length = next.unlockAt - time;
        assertLe(next.locked * length, owed, "merged lock ends after the weighted average");
        assertGt(next.locked * (length + 1), owed, "merged lock ends a second early");
    }

    function testFuzz_gainNeverSpeedsUpTheOldLock(
        Seed memory s,
        uint256 later,
        uint256 gain,
        uint256 after_
    ) public pure {
        Book memory b = _reach(s);
        vm.assume(b.recorded < MAX_BTC);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        uint256 raw = b.recorded + bound(gain, 1, MAX_BTC - b.recorded);
        (ProfitLock.Profit memory next,) =
            ProfitLock.checkpoint(b.p, b.recorded, raw, time, b.period);
        if (ProfitLock.remaining(b.p, time) > 0) {
            assertGe(uint256(next.unlockAt), uint256(b.p.unlockAt), "old end pulled in");
        }
        uint256 t2 = time + bound(after_, 0, 2 * b.period);
        assertGe(
            ProfitLock.remaining(next, t2),
            ProfitLock.remaining(b.p, t2),
            "old profit released sooner"
        );
    }

    function testFuzz_idleCheckpointKeepsTheSchedule(Seed memory s, uint256 later, uint256 after_)
        public
        pure
    {
        Book memory b = _reach(s);
        uint256 time = b.time + bound(later, 0, 2 * b.period);
        (ProfitLock.Profit memory next, uint256 gained) =
            ProfitLock.checkpoint(b.p, b.recorded, b.recorded, time, b.period);
        assertEq(gained, 0, "no change read as a gain");
        uint256 t2 = time + bound(after_, 0, 2 * b.period);
        uint256 kept = ProfitLock.remaining(b.p, t2);
        uint256 moved = ProfitLock.remaining(next, t2);
        assertLe(moved, kept, "idle sync delayed the release");
        assertLe(kept - moved, 1, "idle sync released over 1 wei early");
    }

    /* Helpers */

    // Two checkpoints and an entry point from an empty vault, so only reachable states come out
    function _reach(Seed memory s) internal pure returns (Book memory b) {
        b.period = bound(s.period, MIN_PERIOD, MAX_PERIOD);
        b.time = bound(s.start, START, YEAR_2200 - 8 * MAX_PERIOD);
        b.p.lockedAt = uint64(b.time);
        b.recorded = bound(s.base, 0, MAX_BTC);
        uint256 raw = b.recorded + bound(s.first, 0, MAX_BTC - b.recorded);
        (b.p,) = ProfitLock.checkpoint(b.p, b.recorded, raw, b.time, b.period);
        b.recorded = raw;
        b.time += bound(s.wait, 0, 2 * b.period);
        raw = s.up ? raw + bound(s.second, 0, MAX_BTC - raw) : raw - bound(s.second, 0, raw);
        (b.p,) = ProfitLock.checkpoint(b.p, b.recorded, raw, b.time, b.period);
        // The entry point that took this checkpoint then deposits or pays out at its total
        b.recorded = s.out
            ? raw - bound(s.flow, 0, raw - b.p.locked)
            : raw + bound(s.flow, 0, MAX_BTC - raw);
    }

    // 7 BTC locked at START over 7 days on top of 100 BTC, so recorded is 107 BTC
    function _weekLock() internal pure returns (ProfitLock.Profit memory p) {
        (p,) = ProfitLock.checkpoint(
            ProfitLock.Profit(0, uint64(START), 0), 100e18, 107e18, START, 7 days
        );
    }

    // Runs a checkpoint and checks P1 on it, before and after as the vault and the views see it
    function _continuousCheckpoint(
        ProfitLock.Profit memory p,
        uint256 recorded,
        uint256 raw,
        uint256 time,
        uint256 period
    ) internal pure returns (ProfitLock.Profit memory next, uint256 gain) {
        uint256 before = ProfitLock.unlocked(p, recorded, raw, time);
        (next, gain) = ProfitLock.checkpoint(p, recorded, raw, time, period);
        assertLe(next.locked, raw, "lock above raw");
        assertEq(raw - next.locked, before, "checkpoint moved the unlocked total");
        assertEq(ProfitLock.unlocked(next, raw, raw, time), before, "view moved at the checkpoint");
    }

    // A checkpoint right after a deposit or exit finds no gain or loss and returns the same lock
    function _assertNoPhantom(ProfitLock.Profit memory p, uint256 raw, uint256 time, uint256 period)
        internal
        pure
    {
        (ProfitLock.Profit memory again, uint256 gained) =
            ProfitLock.checkpoint(p, raw, raw, time, period);
        assertEq(gained, 0, "flow read as a gain");
        assertEq(uint256(again.locked), uint256(p.locked), "flow moved the lock");
        assertEq(uint256(again.lockedAt), uint256(p.lockedAt), "flow moved lockedAt");
        assertEq(uint256(again.unlockAt), uint256(p.unlockAt), "flow moved unlockAt");
    }

    // Two vaults apart by gap in recorded and raw stay apart by gap unlocked and lock the same
    function _assertApartBy(
        ProfitLock.Profit memory p,
        uint256 recorded,
        uint256 raw,
        uint256 gap,
        uint256 time,
        uint256 period
    ) internal pure {
        assertEq(
            ProfitLock.unlocked(p, recorded + gap, raw + gap, time),
            ProfitLock.unlocked(p, recorded, raw, time) + gap,
            "unlocked totals not apart by the flow"
        );
        (ProfitLock.Profit memory a, uint256 gainA) =
            ProfitLock.checkpoint(p, recorded, raw, time, period);
        (ProfitLock.Profit memory b, uint256 gainB) =
            ProfitLock.checkpoint(p, recorded + gap, raw + gap, time, period);
        assertEq(gainB, gainA, "flow changed the gain");
        assertEq(uint256(b.locked), uint256(a.locked), "flow changed the lock");
        assertEq(uint256(b.unlockAt), uint256(a.unlockAt), "flow changed unlockAt");
    }
}

// Moves raw, recorded, the lock and time the way Vault.sol does, and checks every step
contract ProfitLockHandler is Test {
    uint256 public immutable period;
    uint256 public raw;
    uint256 public recorded;
    uint256 public time = START;
    ProfitLock.Profit internal _profit;

    constructor(uint256 period_) {
        period = period_;
    }

    function profit() external view returns (ProfitLock.Profit memory) {
        return _profit;
    }

    function unlocked() public view returns (uint256) {
        return ProfitLock.unlocked(_profit, recorded, raw, time);
    }

    /* Steps */

    // Time passes with no entry point, so P2 applies
    function wait(uint256 dt) external {
        uint256 shown = recorded - ProfitLock.remaining(_profit, time);
        uint256 before = unlocked();
        time += bound(dt, 0, 2 * period);
        assertGe(recorded - ProfitLock.remaining(_profit, time), shown, "P2 release reversed");
        assertGe(unlocked(), before, "P2 unlocked total fell with time");
        _checkState();
    }

    // A payout, sale premium, buy-back spread, price rise or donation
    function gain(uint256 amount) external {
        uint256 before = unlocked();
        amount = bound(amount, 0, MAX_BTC - raw);
        raw += amount;
        assertGe(unlocked(), before, "gain lowered the unlocked total");
        assertLe(unlocked() - before, amount, "gain raised the unlocked total by more than itself");
        _checkState();
    }

    // A liquidation, redemption haircut, interest, swap cost or price fall
    function loss(uint256 amount) external {
        uint256 before = unlocked();
        amount = bound(amount, 0, raw);
        raw -= amount;
        assertLe(unlocked(), before, "loss raised the unlocked total");
        assertLe(before - unlocked(), amount, "loss cut the total by more than itself");
        _checkState();
    }

    // sync, and the checkpoints of rebalance and harvest that no fill follows
    function sync() external {
        _checkpoint();
        _checkState();
    }

    // depositBTC, deposit and mint, priced at the total their checkpoint returns
    function deposit(uint256 amount) external {
        uint256 total = _checkpoint();
        amount = bound(amount, 0, MAX_BTC - raw);
        raw += amount;
        recorded += amount;
        assertEq(unlocked(), total + amount, "P5 deposit moved the total by other than its amount");
        _assertNoPhantom();
        _checkState();
    }

    // withdraw, redeem and queue fills, none pays more than the checkpointed total
    function exit(uint256 amount) external {
        uint256 total = _checkpoint();
        amount = bound(amount, 0, total);
        raw -= amount;
        recorded -= amount;
        assertEq(unlocked(), total - amount, "P5 exit moved the total by other than its amount");
        _assertNoPhantom();
        _checkState();
    }

    /* Checks */

    // Vault._checkpoint with P1 and the rules for the new end checked on the way
    function _checkpoint() internal returns (uint256 total) {
        ProfitLock.Profit memory p = _profit;
        uint256 before = unlocked();
        uint256 left = ProfitLock.remaining(p, time);
        (ProfitLock.Profit memory next, uint256 gained) =
            ProfitLock.checkpoint(p, recorded, raw, time, period);
        assertLe(next.locked, raw, "P4 lock above raw after a checkpoint");
        assertEq(raw - next.locked, before, "P1 checkpoint moved the unlocked total");
        assertEq(
            ProfitLock.unlocked(next, raw, raw, time), before, "P1 view moved at the checkpoint"
        );
        assertEq(gained, raw > recorded ? raw - recorded : 0, "gain is not raw above recorded");
        assertEq(uint256(next.lockedAt), time, "lock did not restart at the checkpoint");
        if (gained > 0) {
            assertGt(uint256(next.unlockAt), time, "gain locked for no time");
            assertLe(uint256(next.unlockAt), time + period, "P6 gain outlasts its period");
            if (left > 0) {
                assertGe(uint256(next.unlockAt), uint256(p.unlockAt), "gain pulled the old end in");
            }
        } else {
            assertEq(uint256(next.unlockAt), uint256(p.unlockAt), "P6 loss moved the end");
        }
        _profit = next;
        recorded = raw;
        total = raw - next.locked;
    }

    // A deposit or exit is neither gain nor loss, so a checkpoint right after it changes nothing
    function _assertNoPhantom() internal view {
        (ProfitLock.Profit memory again, uint256 gained) =
            ProfitLock.checkpoint(_profit, recorded, raw, time, period);
        assertEq(gained, 0, "P5 flow read as a gain");
        assertEq(uint256(again.locked), uint256(_profit.locked), "P5 flow moved the lock");
        assertEq(uint256(again.unlockAt), uint256(_profit.unlockAt), "P5 flow moved the end");
    }

    // P3, P4 and the shape of the lock, after every step
    function _checkState() internal view {
        ProfitLock.Profit memory p = _profit;
        assertLe(unlocked(), raw, "P3 unlocked above raw");
        assertLe(p.locked, recorded, "P4 locked above recorded");
        assertLe(ProfitLock.remaining(p, time), p.locked, "remaining above locked");
        assertEq(ProfitLock.remaining(p, p.lockedAt), p.locked, "P6 lock not full at its start");
        assertEq(ProfitLock.remaining(p, p.unlockAt), 0, "P6 lock not empty at its end");
        assertLe(uint256(p.lockedAt), time, "lock starts in the future");
        if (p.locked > 0) {
            assertGt(uint256(p.unlockAt), uint256(p.lockedAt), "live lock with no length");
            assertLe(uint256(p.unlockAt), p.lockedAt + period, "lock longer than the period");
        }
    }
}

// Every run starts from an empty vault and walks random entry points at one unlock period
abstract contract ProfitLockInvariant is Test {
    ProfitLockHandler internal handler;

    function _period() internal pure virtual returns (uint256);

    function setUp() public {
        handler = new ProfitLockHandler(_period());
        bytes4[] memory steps = new bytes4[](6);
        steps[0] = ProfitLockHandler.wait.selector;
        steps[1] = ProfitLockHandler.gain.selector;
        steps[2] = ProfitLockHandler.loss.selector;
        steps[3] = ProfitLockHandler.sync.selector;
        steps[4] = ProfitLockHandler.deposit.selector;
        steps[5] = ProfitLockHandler.exit.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: steps}));
    }

    function invariant_unlockedNeverAboveRaw() public view {
        assertLe(handler.unlocked(), handler.raw(), "P3 unlocked above raw");
    }

    function invariant_lockedNeverAboveRecorded() public view {
        ProfitLock.Profit memory p = handler.profit();
        uint256 recorded = handler.recorded();
        assertLe(p.locked, recorded, "P4 locked above recorded");
        assertLe(ProfitLock.remaining(p, handler.time()), recorded, "P4 remaining above recorded");
    }

    function invariant_lockRunsAtMostOnePeriod() public view {
        ProfitLock.Profit memory p = handler.profit();
        assertEq(ProfitLock.remaining(p, p.lockedAt), p.locked, "P6 lock not full at its start");
        assertEq(ProfitLock.remaining(p, p.unlockAt), 0, "P6 lock not empty at its end");
        if (p.locked > 0) {
            assertLe(uint256(p.unlockAt), p.lockedAt + _period(), "P6 lock outlasts the period");
        }
    }
}

/* One suite per unlock period, pinned to fail on a handler revert since the checks live there */

/// forge-config: default.invariant.fail-on-revert = true
contract ProfitLockSecondInvariantTest is ProfitLockInvariant {
    function _period() internal pure override returns (uint256) {
        return MIN_PERIOD;
    }
}

/// forge-config: default.invariant.fail-on-revert = true
contract ProfitLockHourInvariantTest is ProfitLockInvariant {
    function _period() internal pure override returns (uint256) {
        return 1 hours;
    }
}

/// forge-config: default.invariant.fail-on-revert = true
contract ProfitLockWeekInvariantTest is ProfitLockInvariant {
    function _period() internal pure override returns (uint256) {
        return 7 days;
    }
}

/// forge-config: default.invariant.fail-on-revert = true
contract ProfitLockMonthInvariantTest is ProfitLockInvariant {
    function _period() internal pure override returns (uint256) {
        return MAX_PERIOD;
    }
}
