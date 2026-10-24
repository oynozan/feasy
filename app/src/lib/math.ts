// Pure vault math, kept free of imports so `npm test` runs it with plain Node

export const WAD = 10n ** 18n;
export const YEAR = 365 * 24 * 60 * 60;

// The vault's ERC-4626 decimals offset, shares carry 24 decimals
const VIRTUAL_SHARES = 10n ** 6n;

// Mezo liquidates a trove under 110%
export const LIQUIDATION_CR = 1.1;

export type Trove = { active: boolean; coll: bigint; debt: bigint };

// Same rounding as the vault's convertToAssets
export function sharesToAssets(shares: bigint, totalAssets: bigint, totalSupply: bigint) {
    return (shares * (totalAssets + 1n)) / (totalSupply + VIRTUAL_SHARES);
}

export function ratioOf(trove: Trove, price: bigint) {
    if (!trove.active || trove.debt === 0n) return null;
    return Number((trove.coll * price) / trove.debt) / 1e18;
}

// The BTC price at which a loan now at ratio would sit at target, debt and collateral held still
export function priceAtRatio(price: number, ratio: number, target: number) {
    return (price * target) / ratio;
}

// Yearly MUSD yield of sMUSD per MUSD, from its yield index at two blocks
export function savingsApr(indexNow: bigint, indexThen: bigint, seconds: number) {
    if (seconds <= 0) return 0;
    return (Number(indexNow - indexThen) / 1e18) * (YEAR / seconds);
}

type YieldInput = {
    savingsApr: number;
    trove: Trove;
    troveRateBps: number;
    currentRateBps: number;
    savings: bigint;
    totalAssets: bigint;
    price: bigint;
    targetCR: bigint;
};

// Savings income minus loan interest, as a yearly share of the vault's BTC
export function vaultYield(v: YieldInput) {
    if (!v.trove.active || v.totalAssets === 0n || v.price === 0n) {
        // ponytail: with no loan open, quote the rate the loan would earn at the target ratio
        return (v.savingsApr - v.currentRateBps / 1e4) / (Number(v.targetCR) / 1e18);
    }
    const income = v.savingsApr * (Number(v.savings) / 1e18) - (v.troveRateBps / 1e4) * (Number(v.trove.debt) / 1e18);
    return income / (Number(v.price) / 1e18) / (Number(v.totalAssets) / 1e18);
}

// Evenly spaced sample blocks from start to end, at most count of them
export function sampleBlocks(start: bigint, end: bigint, count: number) {
    const span = end - start;
    const n = span + 1n < BigInt(count) ? Number(span + 1n) : count;
    if (n <= 1) return [end];
    return Array.from({ length: n }, (_, i) => start + (span * BigInt(i)) / BigInt(n - 1));
}

// Splits a BTC amount into whole-satoshi digits, the first four decimals kept apart from the last four
export function btcParts(wei: bigint) {
    const sats = wei / 10n ** 10n;
    const whole = sats / 100_000_000n;
    const fraction = (sats % 100_000_000n).toString().padStart(8, "0");
    return { head: `${whole}.${fraction.slice(0, 4)}`, tail: fraction.slice(4) };
}

export function formatBtc(wei: bigint, decimals = 8) {
    const negative = wei < 0n;
    const abs = negative ? -wei : wei;
    const sats = abs / 10n ** BigInt(18 - decimals);
    const scale = 10n ** BigInt(decimals);
    const fraction = (sats % scale).toString().padStart(decimals, "0");
    return `${negative ? "-" : ""}${sats / scale}.${fraction}`;
}
