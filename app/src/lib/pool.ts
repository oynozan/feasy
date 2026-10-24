"use client";

import { queryOptions, useQuery, useQueryClient } from "@tanstack/react-query";
import { parseAbi, zeroAddress, type Address, type Hash } from "viem";
import { mezoTestnet } from "viem/chains";
import { usePublicClient, useReadContracts } from "wagmi";
import { vault, VAULT_FROM_BLOCK } from "./chain";
import { sampleBlocks, WAD, type Trove } from "./math";

const LOG_RANGE = 10_000n;
const SAMPLES = 32;
const SAT = 10n ** 10n;

// One whole share, 24 decimals, worth exactly 1 BTC before the first deposit
const ONE_SHARE = 10n ** 24n;

// Kept apart from the vault ABI in chain.ts, whose event list useHistory decodes as its own
const poolAbi = parseAbi([
    "function maxCR() view returns (uint256)",
    "function collSurplusPool() view returns (address)",
    "function borrowerOperations() view returns (address)",
    "event Rebalanced(uint256 coll, uint256 debt, uint256 savings)",
    "event Harvested(uint256 musdIn, uint256 btcOut)",
    "event ShortfallBought(uint256 btcIn, uint256 musdOut)",
    "event TroveClosed()",
]);

const surplusAbi = parseAbi(["function getCollateral(address account) view returns (uint256)"]);
const operationsAbi = parseAbi(["function MUSD_GAS_COMPENSATION() view returns (uint256)"]);

// Read through Multicall3 so the vault's BTC lands in the same call and block as its other reads
const multicall = {
    address: mezoTestnet.contracts.multicall3.address,
    abi: parseAbi(["function getEthBalance(address addr) view returns (uint256 balance)"]),
} as const;

const events = [...vault.abi, ...poolAbi].filter((item) => item.type === "event");

type Client = NonNullable<ReturnType<typeof usePublicClient>>;

// Mezo contracts the vault fixed at deployment, and the gas deposit a trove gets back on close
const linksQuery = (client: Client | undefined) =>
    queryOptions({
        queryKey: ["pool-links"],
        staleTime: Infinity,
        queryFn: async () => {
            const [surplusPool, operations] = await Promise.all([
                client!.readContract({ address: vault.address, abi: poolAbi, functionName: "collSurplusPool" }),
                client!.readContract({ address: vault.address, abi: poolAbi, functionName: "borrowerOperations" }),
            ]);
            const gasComp = await client!.readContract({
                address: operations,
                abi: operationsAbi,
                functionName: "MUSD_GAS_COMPENSATION",
            });
            return { surplusPool, gasComp };
        },
    });

/* Where the BTC sits */

export type PoolParts = { total: bigint; loan: bigint; aside: bigint; rest: bigint };

// Whole satoshis, the rest taken from the cut parts so the rows add up to the figure exactly
function split(total: bigint, coll: bigint, aside: bigint): PoolParts {
    const sats = (wei: bigint) => (wei / SAT) * SAT;
    return { total: sats(total), loan: sats(coll), aside: sats(aside), rest: sats(total) - sats(coll) - sats(aside) };
}

/* Live pool state */

// The pool's split, the ceiling ratio and one share's BTC value, all from one block
export function usePoolState() {
    const client = usePublicClient();
    const links = useQuery({ ...linksQuery(client), enabled: !!client }).data;
    const { data } = useReadContracts({
        allowFailure: true,
        contracts: [
            { ...vault, functionName: "totalAssets" },
            { ...vault, functionName: "trove" },
            { ...multicall, functionName: "getEthBalance", args: [vault.address] },
            {
                address: links?.surplusPool ?? zeroAddress,
                abi: surplusAbi,
                functionName: "getCollateral",
                args: [vault.address],
            },
            { address: vault.address, abi: poolAbi, functionName: "maxCR" },
            { ...vault, functionName: "convertToAssets", args: [ONE_SHARE] },
        ],
        query: { enabled: !!links, refetchInterval: 12_000 },
    });

    const total = data?.[0].result;
    const trove = data?.[1].result;
    const idle = data?.[2].result;
    const surplus = data?.[3].result;
    return {
        parts:
            total !== undefined && trove && idle !== undefined && surplus !== undefined
                ? split(total, trove.coll, idle + surplus)
                : undefined,
        maxCR: data?.[4].result,
        perShare: data?.[5].result,
        gasComp: links?.gasComp,
    };
}

/* History */

type Stamp = { id: string; time: number; hash: Hash };

export type PoolEvent = Stamp &
    (
        | { kind: "deposit" | "withdraw"; owner: Address; assets: bigint }
        | { kind: "harvest" | "shortfall" | "collateral"; btc: bigint }
        | { kind: "open" | "borrow" | "repay" | "close"; musd: bigint }
    );

export type PoolSample = { time: number; perShare: bigint; parts: PoolParts };

// Every vault event since deployment, and the pool's BTC sampled from its first deposit to now
export function usePoolHistory() {
    const client = usePublicClient();
    const queryClient = useQueryClient();
    return useQuery({
        queryKey: ["pool-history"],
        enabled: !!client,
        staleTime: 60_000,
        // Each run re-reads every log and sample, a transaction invalidates it sooner anyway
        refetchInterval: 10 * 60_000,
        queryFn: async () => {
            const [latest, { surplusPool }] = await Promise.all([
                client!.getBlock(),
                queryClient.ensureQueryData(linksQuery(client)),
            ]);
            const ranges: [bigint, bigint][] = [];
            for (let from = VAULT_FROM_BLOCK; from <= latest.number; from += LOG_RANGE) {
                const to = from + LOG_RANGE - 1n;
                ranges.push([from, to < latest.number ? to : latest.number]);
            }
            const logs = (
                await Promise.all(
                    ranges.map(([fromBlock, toBlock]) =>
                        client!.getLogs({ address: vault.address, events, fromBlock, toBlock, strict: true }),
                    ),
                )
            ).flat();
            logs.sort((a, b) => Number(a.blockNumber - b.blockNumber) || a.logIndex - b.logIndex);

            const holders = new Map<string, bigint>();
            for (const log of logs) {
                if (log.eventName !== "Transfer") continue;
                const { from, to, value } = log.args;
                holders.set(from.toLowerCase(), (holders.get(from.toLowerCase()) ?? 0n) - value);
                holders.set(to.toLowerCase(), (holders.get(to.toLowerCase()) ?? 0n) + value);
            }
            holders.delete(zeroAddress);
            const depositors = [...holders.values()].filter((shares) => shares > 0n).length;

            // Before the first deposit the pool holds nothing, a zero there would flatten the chart
            const opened = logs.find((log) => log.eventName === "Deposit")?.blockNumber ?? VAULT_FROM_BLOCK;
            const blocks = sampleBlocks(opened, latest.number, SAMPLES);

            // Mezo's logs carry blockTimestamp as 0x0, so the times come from the blocks
            const times = new Map<bigint, number>([[latest.number, Number(latest.timestamp)]]);
            const wanted = new Set([VAULT_FROM_BLOCK, ...blocks, ...logs.map((log) => log.blockNumber)]);
            const loanLogs = logs.filter((log) => log.eventName === "Rebalanced" || log.eventName === "TroveClosed");
            const before = new Map<bigint, Trove>();
            await Promise.all([
                ...[...wanted]
                    .filter((blockNumber) => !times.has(blockNumber))
                    .map(async (blockNumber) => {
                        times.set(blockNumber, Number((await client!.getBlock({ blockNumber })).timestamp));
                    }),
                // The loan as it stood a block earlier, so a loan event shows what it changed
                ...[...new Set(loanLogs.map((log) => log.blockNumber - 1n))].map(async (blockNumber) => {
                    before.set(
                        blockNumber,
                        await client!.readContract({ ...vault, functionName: "trove", blockNumber }),
                    );
                }),
            ]);

            // Reads at one block share a multicall, its four oracle calls stay under Mezo's cap of twenty
            const samples = await Promise.all(
                blocks.map(async (blockNumber): Promise<PoolSample> => {
                    const [assets, perShare, trove, idle, surplus] = await Promise.all([
                        client!.readContract({ ...vault, functionName: "totalAssets", blockNumber }),
                        client!.readContract({
                            ...vault,
                            functionName: "convertToAssets",
                            args: [ONE_SHARE],
                            blockNumber,
                        }),
                        client!.readContract({ ...vault, functionName: "trove", blockNumber }),
                        client!.readContract({
                            ...multicall,
                            functionName: "getEthBalance",
                            args: [vault.address],
                            blockNumber,
                        }),
                        client!.readContract({
                            address: surplusPool,
                            abi: surplusAbi,
                            functionName: "getCollateral",
                            args: [vault.address],
                            blockNumber,
                        }),
                    ]);
                    return {
                        time: times.get(blockNumber)!,
                        perShare,
                        parts: split(assets, trove.coll, idle + surplus),
                    };
                }),
            );

            const closed = new Set(
                logs.filter((log) => log.eventName === "TroveClosed").map((log) => log.transactionHash),
            );
            const activity: PoolEvent[] = [];
            for (const log of logs) {
                const stamp = {
                    id: `${log.transactionHash}-${log.logIndex}`,
                    time: times.get(log.blockNumber)!,
                    hash: log.transactionHash,
                };
                if (log.eventName === "Deposit" || log.eventName === "Withdraw") {
                    const kind = log.eventName === "Deposit" ? "deposit" : "withdraw";
                    activity.push({ ...stamp, kind, owner: log.args.owner, assets: log.args.assets });
                } else if (log.eventName === "Harvested") {
                    activity.push({ ...stamp, kind: "harvest", btc: log.args.btcOut });
                } else if (log.eventName === "ShortfallBought") {
                    activity.push({ ...stamp, kind: "shortfall", btc: log.args.btcIn });
                } else if (log.eventName === "TroveClosed") {
                    const debt = before.get(log.blockNumber - 1n)!.debt;
                    activity.push({ ...stamp, kind: "close", musd: -debt });
                } else if (log.eventName === "Rebalanced" && !closed.has(log.transactionHash)) {
                    const was = before.get(log.blockNumber - 1n)!;
                    const debt = log.args.debt - (was.active ? was.debt : 0n);
                    const coll = log.args.coll - (was.active ? was.coll : 0n);
                    // Interest moves the debt every block, so only a whole MUSD counts as a change
                    if (!was.active && log.args.debt > 0n) activity.push({ ...stamp, kind: "open", musd: debt });
                    else if (debt >= WAD) activity.push({ ...stamp, kind: "borrow", musd: debt });
                    else if (debt <= -WAD) activity.push({ ...stamp, kind: "repay", musd: debt });
                    else if (coll !== 0n) activity.push({ ...stamp, kind: "collateral", btc: coll });
                }
            }
            activity.reverse();

            return { activity, samples, depositors, launch: times.get(VAULT_FROM_BLOCK)! };
        },
    });
}
