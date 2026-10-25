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
import {
    useAccount,
    useBalance,
    useConnections,
    usePublicClient,
    useReadContracts,
    useSwitchChain,
    useWriteContract,
} from "wagmi";
import {
    LEGACY_VAULTS,
    MAINNET_RPC,
    mainnetRates,
    mainnetSavings,
    multicall,
    priceFeed,
    rateManager,
    redeemQueue,
    veSleeve,
    troveManager,
    vault,
    VAULT_FROM_BLOCK,
} from "./chain";
import { lastPayout, nettedLock, sampleBlocks, savingsApr, sharesToAssets, vaultYield, type Trove } from "./math";

const WEEK = 7 * 24 * 60 * 60;
// Mezo testnet averages about 4.6 seconds a block, only used to pick a block a week back
const BLOCK_SECONDS = 4.6;
const LOG_RANGE = 10_000n;
// Enough gas for a deposit and a later withdrawal, a Bitcoin wallet's smart account pays both refunds from here
export const GAS_RESERVE = 3_000_000n;
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
            { ...vault, functionName: "lockedProfit" },
            { ...vault, functionName: "profit" },
            { ...vault, functionName: "queue" },
            { ...vault, functionName: "rawAssets" },
            { ...vault, functionName: "recorded" },
            { ...vault, functionName: "sleeve" },
        ],
        query: { refetchInterval: 12_000 },
    });

    if (!data) return { isPending, data: undefined };
    const [price, lastPrice, totalAssets, totalSupply, trove, savingsValue, targetCR, minCR, troveRate, rate, ...rest] =
        data;
    const [shares, maxWithdraw, maxRedeem, maxDeposit, borrowing, lockedProfit, profit, queue, raw, recorded, sleeve] =
        rest;
    const locked = lockedProfit.result as bigint | undefined;
    const exact = raw.result !== undefined && recorded.result !== undefined;
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
            supply,
            position: sharesToAssets(userShares, assets, supply),
            maxWithdraw: maxWithdraw.result ?? 0n,
            maxRedeem: maxRedeem.result ?? 0n,
            maxDeposit: maxDeposit.result ?? 0n,
            borrowing: (borrowing.result as boolean | undefined) ?? true,
            // v6 only, undefined on v5
            unlocking:
                locked !== undefined && exact
                    ? nettedLock(locked, raw.result as bigint, recorded.result as bigint)
                    : locked,
            // Only v7 can net a loss, v6 shows the stored lock which may run high
            unlockingExact: exact,
            sleeve: sleeve.result && sleeve.result !== zeroAddress ? (sleeve.result as Address) : undefined,
            unlockAt: (profit.result as readonly [bigint, bigint, bigint] | undefined)?.[2],
            queue: queue.result as Address | undefined,
        },
    };
}

// Every connected wallet's Mezo address, the active one first
export function useAddresses() {
    const { address } = useAccount();
    const connections = useConnections();
    const all = [address, ...connections.map((c) => c.accounts[0])].filter((a): a is Address => !!a);
    return [...new Map(all.map((a) => [a.toLowerCase(), a])).values()];
}

// The BTC on Mezo and the pool slice of every connected wallet, added up
export function useHoldings() {
    const addresses = useAddresses();
    const { data } = useVault();
    const reads = useReadContracts({
        allowFailure: false,
        contracts: addresses.flatMap((a) => [
            { ...multicall, functionName: "getEthBalance", args: [a] },
            { ...vault, functionName: "balanceOf", args: [a] },
        ]) as never,
        query: { enabled: addresses.length > 0, refetchInterval: 12_000 },
    }).data as bigint[] | undefined;
    if (!reads || !data) return undefined;
    let wallet = 0n;
    let shares = 0n;
    for (let i = 0; i < reads.length; i += 2) {
        wallet += reads[i];
        shares += reads[i + 1];
    }
    return { wallet, pool: sharesToAssets(shares, data.totalAssets, data.supply) };
}

// The connected wallets' exit requests in this vault's queue and any older vault's, a request stays where it was made
export function useQueue() {
    const addresses = useAddresses();
    const vaults = [vault.address, ...LEGACY_VAULTS.map((v) => v.address)];
    const found = useReadContracts({
        contracts: vaults.map((address) => ({ address, abi: vault.abi, functionName: "queue" })) as never,
        query: { staleTime: Infinity },
    }).data as { result?: Address }[] | undefined;
    const pairs = vaults
        .map((at, i) => ({ vault: at, queue: found?.[i]?.result }))
        .filter((pair): pair is { vault: Address; queue: Address } => !!pair.queue);
    const lists = useReadContracts({
        allowFailure: false,
        contracts: pairs.flatMap((pair) =>
            addresses.map((owner) => ({
                address: pair.queue,
                abi: redeemQueue,
                functionName: "requestsOf",
                args: [owner],
            })),
        ) as never,
        query: { enabled: pairs.length > 0 && addresses.length > 0, refetchInterval: 12_000 },
    }).data as (readonly bigint[])[] | undefined;
    const ids = pairs.map((_, i) => lists?.slice(i * addresses.length, (i + 1) * addresses.length).flat() ?? []);
    // Every read here is storage only, so any number of requests stays clear of the precompile cap
    const reads = useReadContracts({
        allowFailure: false,
        contracts: pairs.flatMap((pair, i) => [
            { address: pair.queue, abi: redeemQueue, functionName: "queueState" },
            ...ids[i].flatMap((id) =>
                (["pendingRedeem", "claimableRedeem", "sharesAhead"] as const).map((functionName) => ({
                    address: pair.queue,
                    abi: redeemQueue,
                    functionName,
                    args: [id],
                })),
            ),
        ]) as never,
        query: { enabled: !!lists, refetchInterval: 12_000 },
    }).data as unknown[] | undefined;

    let offset = 0;
    const each = pairs.map((pair, i) => {
        if (!reads) return undefined;
        const state = reads[offset] as readonly bigint[];
        const values = reads.slice(offset + 1, offset + 1 + ids[i].length * 3) as bigint[];
        offset += 1 + ids[i].length * 3;
        let pending = 0n;
        let claimable = 0n;
        let ahead: bigint | undefined;
        const ready: bigint[] = [];
        ids[i].forEach((id, k) => {
            const [wait, claim, before] = values.slice(k * 3, k * 3 + 3);
            pending += wait;
            claimable += claim;
            if (claim > 0n) ready.push(id);
            if (wait > 0n && (ahead === undefined || before < ahead)) ahead = before;
        });
        return { ...pair, pending, claimable, ready, ahead, backlog: state[0] - state[1] };
    });
    // Waiting shares are worth what their own vault pays for them, one price read per vault
    const worth = useReadContracts({
        allowFailure: false,
        contracts: each.map((q) => ({
            address: q?.vault,
            abi: vault.abi,
            functionName: "convertToAssets",
            args: [q?.pending ?? 0n],
        })) as never,
        query: { enabled: !!reads && each.length > 0, refetchInterval: 12_000 },
    }).data as bigint[] | undefined;
    if (!reads || !worth || pairs.length === 0) return undefined;
    const queues = each.filter((q): q is NonNullable<typeof q> => !!q);
    const current = queues.find((q) => q.vault === vault.address);
    return {
        waiting: worth.reduce((sum, value) => sum + value, 0n),
        claimable: queues.reduce((sum, q) => sum + q.claimable, 0n),
        // One claim call per queue, the first one with BTC ready goes first
        claims: queues.filter((q) => q.ready.length > 0).map((q) => ({ queue: q.queue, ids: q.ready })),
        ahead: current?.ahead,
        backlog: current?.backlog ?? 0n,
    };
}

// What the active wallet can still move out of each older vault, the free shares only
export function useLegacy() {
    const { address } = useAccount();
    const { data } = useReadContracts({
        contracts: LEGACY_VAULTS.flatMap((v) => [
            { address: v.address, abi: vault.abi, functionName: "maxRedeem", args: [address!] },
            { address: v.address, abi: vault.abi, functionName: "maxWithdraw", args: [address!] },
        ]) as never,
        query: { enabled: !!address, refetchInterval: 30_000 },
    });
    const reads = data as { result?: bigint }[] | undefined;
    if (!address || !reads) return [];
    return LEGACY_VAULTS.map((v, i) => ({
        ...v,
        shares: reads[i * 2]?.result,
        assets: reads[i * 2 + 1]?.result,
    })).filter((v): v is typeof v & { shares: bigint; assets: bigint } => !!v.shares && !!v.assets);
}

// v7's veBTC locks, up to a quarter of the pool, each ending on a Thursday at 00:00 UTC
export function useSleeve() {
    const { data } = useVault();
    const sleeve = data?.sleeve;
    const reads = useReadContracts({
        allowFailure: false,
        contracts: [
            { address: sleeve!, abi: veSleeve, functionName: "principal" },
            { address: sleeve!, abi: veSleeve, functionName: "paused" },
            { address: sleeve!, abi: veSleeve, functionName: "live" },
            { address: sleeve!, abi: veSleeve, functionName: "lockWeeks" },
            ...[0n, 1n, 2n, 3n].map((i) => ({ address: sleeve!, abi: veSleeve, functionName: "rungs", args: [i] })),
        ] as never,
        query: { enabled: !!sleeve, refetchInterval: 60_000 },
    }).data as unknown[] | undefined;
    if (!sleeve || !reads) return undefined;
    const [principal, paused, live, lockWeeks, ...rungs] = reads as [
        bigint,
        boolean,
        boolean,
        number,
        ...(readonly [bigint, bigint, bigint])[],
    ];
    return {
        principal,
        // Paused or Mezo Earn down means no new locks, the running ones still end on schedule
        open: !paused && live,
        lockWeeks,
        rungs: rungs
            .filter(([id]) => id !== 0n)
            .map(([, amount, end]) => ({ amount, end: Number(end) }))
            .sort((a, b) => a.end - b.end),
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

// Every vault event since deployment, then the connected wallets' balances sampled along the way
export function useHistory() {
    const client = usePublicClient();
    const addresses = useAddresses();
    const mine = new Set(addresses.map((a) => a.toLowerCase()));
    return useQuery({
        queryKey: ["history", ...[...mine].sort()],
        enabled: !!client && addresses.length > 0,
        staleTime: 60_000,
        queryFn: async () => {
            const [latest, queue] = await Promise.all([
                client!.getBlock(),
                client!.readContract({ ...vault, functionName: "queue" }).catch(() => undefined),
            ]);
            const escrow = queue?.toLowerCase();
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
                            address: queue ? [vault.address, queue] : vault.address,
                            events: [...eventsOf(), ...redeemQueue.filter((item) => item.type === "event")],
                            fromBlock,
                            toBlock,
                            strict: true,
                        }),
                    ),
                )
            ).flat();
            logs.sort((a, b) => Number(a.blockNumber - b.blockNumber) || a.logIndex - b.logIndex);

            // A share moving into the queue's escrow still belongs to its holder, so only the claim counts
            const ours = logs.filter((log) =>
                log.eventName === "Transfer"
                    ? (mine.has(log.args.from.toLowerCase()) || mine.has(log.args.to.toLowerCase())) &&
                      log.args.from.toLowerCase() !== escrow &&
                      log.args.to.toLowerCase() !== escrow
                    : mine.has(log.args.owner.toLowerCase()),
            );
            // Mezo's logs carry blockTimestamp as 0x0, so the times come from the blocks
            const times = new Map<bigint, number>();
            await Promise.all(
                [...new Set(ours.map((log) => log.blockNumber))].map(async (blockNumber) => {
                    times.set(blockNumber, Number((await client!.getBlock({ blockNumber })).timestamp));
                }),
            );

            const activity: Activity[] = [];
            const moves: { block: bigint; delta: bigint }[] = [];
            let deposited = 0n;
            for (const log of ours) {
                const time = times.get(log.blockNumber)!;
                if (log.eventName === "Transfer") {
                    const { from, to, value } = log.args;
                    // A move between two of the wallets adds and takes away the same shares
                    if (mine.has(to.toLowerCase())) moves.push({ block: log.blockNumber, delta: value });
                    if (mine.has(from.toLowerCase())) moves.push({ block: log.blockNumber, delta: -value });
                } else if (log.eventName === "Claimed") {
                    // A filled request paid out, its shares are gone and its BTC landed in the wallet
                    moves.push({ block: log.blockNumber, delta: -log.args.shares });
                    deposited -= log.args.assets;
                    activity.push({ kind: "withdraw", assets: log.args.assets, time, hash: log.transactionHash });
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
                        Promise.all(addresses.map((a) => client!.getBalance({ address: a, blockNumber: block }))).then(
                            (each) => each.reduce((sum, value) => sum + value, 0n),
                        ),
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
    | { functionName: "withdraw" | "redeem"; args: readonly [bigint, Address, Address] }
    // An exit from v5, which the Move row sends before depositing into v6
    | { functionName: "redeem"; args: readonly [bigint, Address, Address]; at: Address }
    // v6 sends exit requests and claims to its queue contract instead
    | { functionName: "requestRedeem"; args: readonly [bigint, Address, Address]; queue: Address }
    | { functionName: "claim"; args: readonly [readonly bigint[]]; queue: Address };

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
            const { queue, at, ...rest } = { queue: undefined, at: undefined, ...call } as VaultCall & {
                queue?: Address;
                at?: Address;
            };
            const target = queue
                ? { address: queue, abi: redeemQueue }
                : { address: at ?? vault.address, abi: vault.abi };
            // VaultCall already pins each call's shape, viem just cannot narrow the union
            const request = { ...target, ...rest, account: address } as Parameters<typeof client.simulateContract>[0];
            // Mezo's gas estimate drops revert data while eth_call keeps it, so a doomed call fails here with its reason
            await client.simulateContract(request);
            if (isBitcoinWallet(connector)) {
                // OrangeKit signs with the Bitcoin wallet and relays through its smart account, writeContract skips that
                const data = encodeFunctionData(request as Parameters<typeof encodeFunctionData>[0]);
                const sent = await sendFromBitcoin(target.address, "value" in call ? call.value : 0n, data);
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
            // A smart account can land while the call inside it reverts, so only a vault or queue event counts
            const ran = receipt.logs.some((log) =>
                [target.address, vault.address].some((to) => log.address.toLowerCase() === to.toLowerCase()),
            );
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

export function isBitcoinWallet(connector: unknown) {
    return typeof (connector as { getBitcoinProvider?: unknown } | undefined)?.getBitcoinProvider === "function";
}

const REVERTS: Record<string, string> = {
    ERC4626ExceededMaxDeposit: "The pool can't take that much right now.",
    ERC4626ExceededMaxWithdraw: "That's more than you can withdraw right now.",
    ERC4626ExceededMaxRedeem: "That's more than you can withdraw right now.",
    Illiquid: "The pool can't free that much BTC right now.",
    ZeroShares: "That amount is too small.",
    BadReceiver: "That address can't receive BTC from the pool.",
    BadParams: "That request can't be claimed.",
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
