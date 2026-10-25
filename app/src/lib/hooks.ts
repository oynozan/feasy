"use client";

import { createContext, createElement, useContext, useState, type ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useSendTransaction } from "@mezo-org/orangekit";
import {
    BaseError,
    ChainMismatchError,
    ContractFunctionRevertedError,
    createPublicClient,
    encodeFunctionData,
    http,
    InsufficientFundsError,
    SwitchChainError,
    UserRejectedRequestError,
    zeroAddress,
    type Address,
    type Block,
    type Hash,
} from "viem";
import { mezoTestnet } from "viem/chains";
import { useAccount, useBalance, usePublicClient, useReadContracts, useSwitchChain, useWriteContract } from "wagmi";
import {
    MAINNET_RPC,
    mainnetRates,
    mainnetSavings,
    priceFeed,
    rateManager,
    troveManager,
    vault,
    VAULT_FROM_BLOCK,
} from "./chain";
import { lastPayout, sampleBlocks, savingsApr, sharesToAssets, vaultYield, type Trove } from "./math";

const WEEK = 7 * 24 * 60 * 60;
// Mezo testnet averages about 4.6 seconds a block, only used to pick a block a week back
const BLOCK_SECONDS = 4.6;
const LOG_RANGE = 10_000n;
const BARS = 32;

/* Session */

// Whether wagmi has a connection stored to reconnect, read once per page load
const resuming = (() => {
    try {
        return JSON.parse(localStorage.getItem("wagmi.store") ?? "{}").state?.connections?.value?.length > 0;
    } catch {
        return false;
    }
})();

// Signed out once wagmi has had its chance to reconnect, so a returning wallet never flashes the pitch
export function useSignedOut() {
    const { status } = useAccount();
    const [waiting, setWaiting] = useState(resuming);
    if (waiting && status !== "disconnected") setWaiting(false);
    return (status === "disconnected" || status === "connecting") && !waiting;
}

/* Live vault state */

export function useVault() {
    const { address } = useAccount();
    const user = address ?? zeroAddress;
    // Mezo allows 20 precompile calls per call, the five oracle reads here cost ten
    const { data, isPending } = useReadContracts({
        allowFailure: true,
        contracts: [
            { ...priceFeed, functionName: "fetchPrice" },
            { ...vault, functionName: "lastPrice" },
            { ...vault, functionName: "totalAssets" },
            { ...vault, functionName: "totalSupply" },
            { ...vault, functionName: "trove" },
            { ...vault, functionName: "savingsValue" },
            { ...vault, functionName: "targetCR" },
            { ...vault, functionName: "minCR" },
            { ...troveManager, functionName: "getTroveInterestRate", args: [vault.address] },
            { ...rateManager, functionName: "interestRate" },
            { ...vault, functionName: "balanceOf", args: [user] },
            { ...vault, functionName: "maxWithdraw", args: [user] },
            { ...vault, functionName: "maxRedeem", args: [user] },
            { ...vault, functionName: "maxDeposit", args: [user] },
            { ...vault, functionName: "borrowingEnabled" },
        ],
        query: { refetchInterval: 12_000 },
    });

    if (!data) return { isPending, data: undefined };
    const [price, lastPrice, totalAssets, totalSupply, trove, savingsValue, targetCR, minCR, troveRate, rate, ...rest] =
        data;
    const [shares, maxWithdraw, maxRedeem, maxDeposit, borrowing] = rest;
    const t = trove.result as Trove | undefined;
    const assets = totalAssets.result ?? 0n;
    const supply = totalSupply.result ?? 0n;
    const userShares = address ? (shares.result ?? 0n) : 0n;

    return {
        isPending,
        data: {
            // A stale oracle makes fetchPrice revert, the vault then prices with the last one it saw
            price: price.result ?? lastPrice.result ?? 0n,
            stale: price.status === "failure",
            totalAssets: assets,
            trove: t ?? { active: false, coll: 0n, debt: 0n },
            savings: savingsValue.result ?? 0n,
            targetCR: targetCR.result ?? 25n * 10n ** 17n,
            minCR: minCR.result ?? 2n * 10n ** 18n,
            troveRateBps: troveRate.result ?? 0,
            currentRateBps: rate.result ?? 0,
            shares: userShares,
            position: sharesToAssets(userShares, assets, supply),
            maxWithdraw: maxWithdraw.result ?? 0n,
            maxRedeem: maxRedeem.result ?? 0n,
            maxDeposit: maxDeposit.result ?? 0n,
            borrowing: (borrowing.result as boolean | undefined) ?? true,
        },
    };
}

export function useWalletBtc() {
    const { address } = useAccount();
    return useBalance({ address, query: { enabled: !!address, refetchInterval: 12_000 } }).data?.value;
}

/* Rates */

const mainnet = createPublicClient({ transport: http(MAINNET_RPC) });
const WEEKS = 12;

// Mezo mainnet's savings rate over the last twelve whole payout weeks, and its loan rate
export function useMainnetRates() {
    return useQuery({
        queryKey: ["mainnet-rates"],
        staleTime: 60 * 60_000,
        queryFn: async () => {
            const head = await mainnet.getBlock();
            const end = lastPayout(Number(head.timestamp));
            const [to, from] = await Promise.all([blockAt(head, end), blockAt(head, end - WEEKS * WEEK)]);
            const index = (block: Block) =>
                mainnet.readContract({ ...mainnetSavings, functionName: "yieldIndex", blockNumber: block.number! });
            const [now, then, rate] = await Promise.all([
                index(to),
                index(from),
                mainnet.readContract({ ...mainnetRates, functionName: "interestRate" }),
            ]);
            return { savingsApr: savingsApr(now, then, Number(to.timestamp - from.timestamp)), loanRateBps: rate };
        },
    });
}

// A block within minutes of a time, guessed from the block rate between the head and a first try
async function blockAt(head: Block, seconds: number) {
    const behind = (rate: number) => head.number! - BigInt(Math.round((Number(head.timestamp) - seconds) / rate));
    const guess = await mainnet.getBlock({ blockNumber: behind(3.8) });
    const rate = Number(head.timestamp - guess.timestamp) / Number(head.number! - guess.number);
    return mainnet.getBlock({ blockNumber: behind(rate) });
}

// The vault's yearly BTC yield at mainnet rates, savings income minus loan interest
export function useYield() {
    const { data } = useVault();
    const rates = useMainnetRates().data;
    if (!data || !rates) return undefined;
    const { savingsApr, loanRateBps } = rates;
    return vaultYield({ ...data, savingsApr, troveRateBps: loanRateBps, currentRateBps: loanRateBps });
}

/* BTC price */

// The last week of BTC's dollar price, hourly, oldest first as [unix ms, USD]
export function useBtcHistory() {
    return useQuery({
        queryKey: ["btc-history"],
        staleTime: 10 * 60_000,
        refetchInterval: 10 * 60_000,
        queryFn: async () => {
            const end = Math.floor(Date.now() / 1000);
            const response = await fetch(
                `https://coins.llama.fi/chart/coingecko:bitcoin?end=${end}&span=168&period=1h`,
            );
            if (!response.ok) throw new Error(`DefiLlama answered ${response.status}`);
            const body = (await response.json()) as {
                coins: Record<string, { prices: { timestamp: number; price: number }[] }>;
            };
            const prices = body.coins["coingecko:bitcoin"]?.prices ?? [];
            return prices
                .filter((p) => Number.isFinite(p.price) && p.price > 0)
                .map((p): [number, number] => [p.timestamp * 1000, p.price])
                .sort((a, b) => a[0] - b[0]);
        },
    });
}

/* History */

export type Activity = { kind: "deposit" | "withdraw"; assets: bigint; time: number; hash: Hash };
export type Bar = { time: number; pool: bigint; wallet: bigint };

// Every vault event since deployment, then the holder's balance sampled along the way
export function useHistory() {
    const client = usePublicClient();
    const { address } = useAccount();
    return useQuery({
        queryKey: ["history", address],
        enabled: !!client && !!address,
        staleTime: 60_000,
        queryFn: async () => {
            const latest = await client!.getBlock();
            const ranges: [bigint, bigint][] = [];
            for (let from = VAULT_FROM_BLOCK; from <= latest.number; from += LOG_RANGE) {
                const to = from + LOG_RANGE - 1n;
                ranges.push([from, to < latest.number ? to : latest.number]);
            }
            // ponytail: one log query per 10k blocks since deployment, an indexer once the vault is months old
            const logs = (
                await Promise.all(
                    ranges.map(([fromBlock, toBlock]) =>
                        client!.getLogs({
                            address: vault.address,
                            events: eventsOf(),
                            fromBlock,
                            toBlock,
                            strict: true,
                        }),
                    ),
                )
            ).flat();
            logs.sort((a, b) => Number(a.blockNumber - b.blockNumber) || a.logIndex - b.logIndex);

            const me = address!.toLowerCase();
            const mine = logs.filter((log) =>
                log.eventName === "Transfer"
                    ? log.args.from.toLowerCase() === me || log.args.to.toLowerCase() === me
                    : log.args.owner.toLowerCase() === me,
            );
            // Mezo's logs carry blockTimestamp as 0x0, so the times come from the blocks
            const times = new Map<bigint, number>();
            await Promise.all(
                [...new Set(mine.map((log) => log.blockNumber))].map(async (blockNumber) => {
                    times.set(blockNumber, Number((await client!.getBlock({ blockNumber })).timestamp));
                }),
            );

            const activity: Activity[] = [];
            const moves: { block: bigint; delta: bigint }[] = [];
            let deposited = 0n;
            for (const log of mine) {
                const time = times.get(log.blockNumber)!;
                if (log.eventName === "Transfer") {
                    const { from, to, value } = log.args;
                    if (to.toLowerCase() === me) moves.push({ block: log.blockNumber, delta: value });
                    if (from.toLowerCase() === me) moves.push({ block: log.blockNumber, delta: -value });
                } else {
                    const kind = log.eventName === "Deposit" ? "deposit" : "withdraw";
                    deposited += kind === "deposit" ? log.args.assets : -log.args.assets;
                    activity.push({ kind, assets: log.args.assets, time, hash: log.transactionHash });
                }
            }
            activity.reverse();
            if (moves.length === 0) return { activity, deposited, bars: [] as Bar[] };

            // At least a week back like the price chart, so a fresh deposit still draws a full row of bars
            const weekBack = latest.number - BigInt(Math.round(WEEK / BLOCK_SECONDS));
            const from = moves[0].block < weekBack ? moves[0].block : weekBack;
            const blocks = sampleBlocks(from, latest.number, BARS);
            const first = Number((await client!.getBlock({ blockNumber: from })).timestamp);
            const span = Number(latest.timestamp) - first;
            const bars = await Promise.all(
                blocks.map(async (block): Promise<Bar> => {
                    let shares = 0n;
                    for (const move of moves) if (move.block <= block) shares += move.delta;
                    // ponytail: bar times are spread linearly from the first bar to now, blocks run near constant
                    const time = first + (span * Number(block - from)) / Number(latest.number - from);
                    const [wallet, pool] = await Promise.all([
                        client!.getBalance({ address: address!, blockNumber: block }),
                        shares === 0n
                            ? 0n
                            : client!.readContract({
                                  ...vault,
                                  functionName: "convertToAssets",
                                  args: [shares],
                                  blockNumber: block,
                              }),
                    ]);
                    return { time, pool, wallet };
                }),
            );
            return { activity, deposited, bars };
        },
    });
}

function eventsOf() {
    return vault.abi.filter((item) => item.type === "event");
}

/* Transactions */

export type TxState =
    | { status: "idle" }
    | { status: "wallet" }
    | { status: "pending"; hash: Hash }
    | { status: "done"; hash: Hash }
    | { status: "error"; message: string; hash?: Hash };

type VaultCall =
    | { functionName: "depositBTC"; args: readonly [Address]; value: bigint }
    | { functionName: "withdraw" | "redeem"; args: readonly [bigint, Address, Address] };

class Failed extends Error {}

type Tx = ReturnType<typeof useTxState>;

const TxContext = createContext<Tx | null>(null);

// One transaction at a time, shared by the deposit and withdraw blocks so it survives switching between them
export function TxProvider({ children }: { children: ReactNode }) {
    return createElement(TxContext.Provider, { value: useTxState() }, children);
}

export function useVaultTx() {
    const tx = useContext(TxContext);
    if (!tx) throw new Error("useVaultTx needs a TxProvider");
    return tx;
}

function useTxState() {
    const client = usePublicClient();
    const queryClient = useQueryClient();
    const { address, chainId, connector } = useAccount();
    const { writeContractAsync } = useWriteContract();
    const { switchChainAsync } = useSwitchChain();
    const { sendTransaction: sendFromBitcoin } = useSendTransaction();
    const [state, setState] = useState<TxState>({ status: "idle" });

    // Resolves true once the vault call lands, so the form only clears on success
    async function send(call: VaultCall) {
        if (!client || !address) return false;
        setState({ status: "wallet" });
        let hash: Hash | undefined;
        try {
            // VaultCall already pins each call's shape, viem just cannot narrow the union
            const request = { ...vault, ...call, account: address } as Parameters<typeof client.simulateContract>[0];
            // Mezo's gas estimate drops revert data while eth_call keeps it, so a doomed call fails here with its reason
            await client.simulateContract(request);
            if (isBitcoinWallet(connector)) {
                // OrangeKit signs with the Bitcoin wallet and relays through its smart account, writeContract skips that
                const data = encodeFunctionData(request as Parameters<typeof encodeFunctionData>[0]);
                const sent = await sendFromBitcoin(vault.address, "value" in call ? call.value : 0n, data);
                if (!sent) throw new Failed("Reconnect your Bitcoin wallet and try again.");
                hash = sent.hash;
            } else {
                if (chainId !== mezoTestnet.id) await switchChainAsync({ chainId: mezoTestnet.id });
                // The wallet would estimate unpadded on its own RPC, ours is padded in relayer.ts
                const gas = await client.estimateContractGas(request as never);
                const write = { ...request, gas, chainId: mezoTestnet.id } as Parameters<typeof writeContractAsync>[0];
                hash = await writeContractAsync(write);
            }
            setState({ status: "pending", hash });
            const receipt = await client.waitForTransactionReceipt({ hash });
            // A smart account can land while the vault call inside it reverts, so only a vault event counts
            const ran = receipt.logs.some((log) => log.address.toLowerCase() === vault.address.toLowerCase());
            if (receipt.status !== "success" || !ran) throw new Failed("The vault call didn't go through.");
            setState({ status: "done", hash });
            return true;
        } catch (error) {
            // A hash means it failed on chain, so the steps show the confirm step red and keep the link
            const failed = errorState(error);
            setState(failed.status === "error" && hash ? { ...failed, hash } : failed);
            return false;
        } finally {
            void queryClient.invalidateQueries();
        }
    }

    return { state, send, reset: () => setState({ status: "idle" }) };
}

function isBitcoinWallet(connector: unknown) {
    return typeof (connector as { getBitcoinProvider?: unknown } | undefined)?.getBitcoinProvider === "function";
}

const REVERTS: Record<string, string> = {
    ERC4626ExceededMaxDeposit: "The pool can't take that much right now.",
    ERC4626ExceededMaxWithdraw: "That's more than you can withdraw right now.",
    ERC4626ExceededMaxRedeem: "That's more than you can withdraw right now.",
    Illiquid: "The pool can't free that much BTC right now.",
    ZeroShares: "That amount is too small.",
};

function errorState(error: unknown): TxState {
    if (error instanceof Failed) return { status: "error", message: error.message };
    if (error instanceof BaseError) {
        if (error.walk((e) => e instanceof UserRejectedRequestError)) return { status: "idle" };
        if (error.walk((e) => e instanceof ChainMismatchError || e instanceof SwitchChainError)) {
            return { status: "error", message: "Switch your wallet to Mezo and try again." };
        }
        if (error.walk((e) => e instanceof InsufficientFundsError)) {
            return { status: "error", message: "Not enough BTC left for gas." };
        }
        const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
        const name = revert instanceof ContractFunctionRevertedError ? revert.data?.errorName : undefined;
        if (name && REVERTS[name]) return { status: "error", message: REVERTS[name] };
    }
    return { status: "error", message: "The transaction didn't go through." };
}
