import assert from "node:assert/strict";
import test from "node:test";
import {
    btcParts,
    LIQUIDATION_CR,
    loanState,
    priceAtRatio,
    formatBtc,
    ratioOf,
    sampleBlocks,
    savingsApr,
    sharesToAssets,
    vaultYield,
    WAD,
    YEAR,
} from "./math.ts";

test("shares convert like the vault", () => {
    // Testnet state from the run log, Alice's 0.06 BTC position
    assert.equal(sharesToAssets(0n, 10n ** 17n, 10n ** 23n), 0n);
    const shares = 60_000_000_000_000_000_000_000n;
    const assets = sharesToAssets(shares, 89_964_605_271_197_040n, 90_000_000_000_000_000_000_000n);
    assert.ok(assets > 59_976_000_000_000_000n && assets < 59_977_000_000_000_000n);
});

test("loan ratio and liquidation headroom", () => {
    const trove = { active: true, coll: 87_300_000_000_000_000n, debt: 2_815_598_320_181_999_999_999n };
    const ratio = ratioOf(trove, 80_629_963_350_000_000_000_000n);
    assert.ok(ratio !== null && Math.abs(ratio - 2.5) < 0.001);
    // At 250% a 56% fall reaches liquidation and a 20% fall reaches the 200% repay line
    assert.ok(Math.abs(priceAtRatio(100_000, 2.5, LIQUIDATION_CR) - 44_000) < 1e-6);
    assert.ok(Math.abs(priceAtRatio(100_000, 2.5, 2) - 80_000) < 1e-6);
    assert.equal(ratioOf({ active: false, coll: 0n, debt: 0n }, WAD), null);
});

const idleInput = () => ({
    savingsApr: 0.05,
    trove: { active: false, coll: 0n, debt: 0n },
    troveRateBps: 0,
    currentRateBps: 100,
    savings: 0n,
    totalAssets: 0n,
    price: 0n,
    targetCR: 25n * 10n ** 17n,
    borrowing: true,
});

test("yield", () => {
    assert.ok(Math.abs(savingsApr(WAD + WAD / 20n, WAD, YEAR) - 0.05) < 1e-9);
    // No loan, 5% savings and 1% borrow at 250% earns (5 - 1) / 2.5 = 1.6%
    const idle = vaultYield({
        savingsApr: 0.05,
        trove: { active: false, coll: 0n, debt: 0n },
        troveRateBps: 0,
        currentRateBps: 100,
        savings: 0n,
        totalAssets: 0n,
        price: 0n,
        targetCR: 25n * 10n ** 17n,
        borrowing: true,
    });
    assert.ok(Math.abs(idle - 0.016) < 1e-9);
    // With borrowing off and no loan the BTC sits idle and earns nothing
    assert.equal(vaultYield({ ...idleInput(), borrowing: false }), 0);
    // The PDF example, 1 BTC at $100k with $40k borrowed and parked earns 1.6%
    const open = vaultYield({
        savingsApr: 0.05,
        trove: { active: true, coll: WAD, debt: 40_000n * WAD },
        troveRateBps: 100,
        currentRateBps: 100,
        savings: 40_000n * WAD,
        totalAssets: WAD,
        price: 100_000n * WAD,
        targetCR: 25n * 10n ** 17n,
        borrowing: true,
    });
    assert.ok(Math.abs(open - 0.016) < 1e-9);
});

test("sample blocks", () => {
    assert.deepEqual(sampleBlocks(10n, 10n, 32), [10n]);
    assert.deepEqual(sampleBlocks(10n, 12n, 32), [10n, 11n, 12n]);
    const many = sampleBlocks(0n, 1000n, 5);
    assert.deepEqual(many, [0n, 250n, 500n, 750n, 1000n]);
});

test("btc formatting", () => {
    assert.deepEqual(btcParts(59_976_403_567_738_295n), { head: "0.0599", tail: "7640" });
    assert.deepEqual(btcParts(0n), { head: "0.0000", tail: "0000" });
    assert.equal(formatBtc(60_000_000_000_000_000n), "0.06000000");
    assert.equal(formatBtc(-12_000_000_000_000n), "-0.00001200");
    assert.equal(formatBtc(0n), "0.00000000");
});

test("loan state", () => {
    const open = { active: true, coll: 1n, debt: 1n };
    const none = { active: false, coll: 0n, debt: 0n };
    assert.equal(loanState(open, true), "open");
    assert.equal(loanState(open, false), "paused");
    assert.equal(loanState(none, true), "waiting");
    assert.equal(loanState(none, false), "off");
});
