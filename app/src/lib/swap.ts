import { encodePacked, parseAbi, type Address, type Hex, type PublicClient } from "viem";

// WBTC and cbBTC on Ethereum mainnet swap into tBTC before the bridge, Sepolia has no real pools for them

export type Source = "tBTC" | "WBTC" | "cbBTC";
export type Wrapped = Exclude<Source, "tBTC">;

const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
const CBBTC = "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf";
const TBTC = "0x18084fbA666a33d37592fA2633fD49a74DD93a88";

// Both count in satoshis, tBTC and Mezo's BTC in 18 decimals
export const WRAPPED: Record<Wrapped, { address: Address; decimals: number }> = {
    WBTC: { address: WBTC, decimals: 8 },
    cbBTC: { address: CBBTC, decimals: 8 },
};

const QUOTER = "0x61fFE014bA17989E743c5F6cB21bF9697530B21e";
const ROUTER = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
// The deepest tBTC venue, WBTC is coin 0 and tBTC coin 1
const CURVE = "0xb7ecb2aa52aa64a717180e030241bc75cd946726";

// The quoter is not a view on chain, it reverts internally to report, so it reads fine through eth_call
const quoter = parseAbi([
    "function quoteExactInput(bytes path, uint256 amountIn) view returns (uint256 amountOut, uint160[] sqrtPriceX96AfterList, uint32[] initializedTicksCrossedList, uint256 gasEstimate)",
]);
const router = parseAbi([
    "function exactInput((bytes path, address recipient, uint256 amountIn, uint256 amountOutMinimum) params) payable returns (uint256 amountOut)",
]);
const curve = parseAbi([
    "function get_dy(int128 i, int128 j, uint256 dx) view returns (uint256)",
    "function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) returns (uint256)",
]);

export type Route =
    { venue: "uniswap"; path: Hex; out: bigint; spender: Address } | { venue: "curve"; out: bigint; spender: Address };

// cbBTC has no deep tBTC pool, so it goes through WBTC on Uniswap's 0.01% pool first
const PATHS: Record<Wrapped, (Address | number)[][]> = {
    WBTC: [
        [WBTC, 100, TBTC],
        [WBTC, 500, TBTC],
    ],
    cbBTC: [
        [CBBTC, 100, WBTC, 100, TBTC],
        [CBBTC, 100, WBTC, 500, TBTC],
    ],
};

function encodePath(hops: (Address | number)[]) {
    const types = hops.map((_, i) => (i % 2 === 0 ? "address" : "uint24"));
    return encodePacked(types, hops);
}

// Every Uniswap path and, for WBTC, the Curve pool, the route paying the most tBTC wins
export async function bestRoute(client: PublicClient, source: Wrapped, amountIn: bigint): Promise<Route | undefined> {
    const uniswap = PATHS[source].map(encodePath).map((path) =>
        client
            .readContract({ address: QUOTER, abi: quoter, functionName: "quoteExactInput", args: [path, amountIn] })
            .then(([out]): Route => ({ venue: "uniswap", path, out, spender: ROUTER }))
            .catch(() => undefined),
    );
    const viaCurve =
        source === "WBTC"
            ? [
                  client
                      .readContract({ address: CURVE, abi: curve, functionName: "get_dy", args: [0n, 1n, amountIn] })
                      .then((out): Route => ({ venue: "curve", out, spender: CURVE }))
                      .catch(() => undefined),
              ]
            : [];
    const routes = (await Promise.all([...uniswap, ...viaCurve])).filter((r): r is Route => !!r && r.out > 0n);
    return routes.sort((a, b) => (b.out > a.out ? 1 : b.out < a.out ? -1 : 0))[0];
}

// The swap transaction for a route, paying the tBTC to the signer
export function swapCall(route: Route, amountIn: bigint, minOut: bigint, recipient: Address) {
    return route.venue === "uniswap"
        ? ({
              address: ROUTER,
              abi: router,
              functionName: "exactInput",
              args: [{ path: route.path, recipient, amountIn, amountOutMinimum: minOut }],
          } as const)
        : ({ address: CURVE, abi: curve, functionName: "exchange", args: [0n, 1n, amountIn, minOut] } as const);
}

// Satoshi amounts sit in 18 decimals everywhere in the form, so they scale back before reaching a contract
export function toToken(amount: bigint, source: Source) {
    return source === "tBTC" ? amount : amount / 10n ** BigInt(18 - WRAPPED[source].decimals);
}

export function fromToken(amount: bigint, source: Source) {
    return source === "tBTC" ? amount : amount * 10n ** BigInt(18 - WRAPPED[source].decimals);
}
