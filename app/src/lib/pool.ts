"use client";

import { queryOptions, useQuery, useQueryClient } from "@tanstack/react-query";
import { createPublicClient, http, parseAbi, zeroAddress, type Address, type Hash } from "viem";
import { mezoTestnet } from "viem/chains";
import { usePublicClient, useReadContracts } from "wagmi";
import { booster, boostVoter, erc20, savingsSleeve, vault, veMezo, veSleeve, VAULT_FROM_BLOCK } from "./chain";
import { useSleeve } from "./hooks";
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

const events = [...vault.abi, ...poolAbi, ...savingsSleeve].filter((item) => item.type === "event");

type Client = NonNullable<ReturnType<typeof usePublicClient>>;

// Mezo's RPC answers a batch one call at a time, so these reads go out as parallel requests
const history = createPublicClient({ chain: mezoTestnet, transport: http(), batch: { multicall: true } });

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

export type PoolParts = { total: bigint; loan: bigint; aside: bigint; locked: bigint; rest: bigint };

// Whole satoshis, the rest taken from the cut parts so the rows add up to the figure exactly
function split(total: bigint, coll: bigint, aside: bigint, locked: bigint): PoolParts {
    const sats = (wei: bigint) => (wei / SAT) * SAT;
    const rest = sats(total) - sats(coll) - sats(aside) - sats(locked);
    return { total: sats(total), loan: sats(coll), aside: sats(aside), locked: sats(locked), rest };
}

/* Live pool state */

// The pool's split, the ceiling ratio and one share's BTC value, all from one block
export function usePoolState() {
    const client = usePublicClient();
    const links = useQuery({ ...linksQuery(client), enabled: !!client }).data;
    const sleeve = useSleeve();
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
                ? split(total, trove.coll, idle + surplus, sleeve?.principal ?? 0n)
                : undefined,
        maxCR: data?.[4].result,
        perShare: data?.[5].result,
        gasComp: links?.gasComp,
    };
}

/* Mezo loop */

export type Borrowing = "on" | "waiting" | "paused" | "off" | "closing";

// v8's spread guard, its sMUSD in Mezo's gauge, the MEZO it earns and the veMEZO boost, undefined before v8
export function useLoop() {
    const { data: links } = useReadContracts({
        contracts: [
            { ...vault, functionName: "savingsSleeve" },
            { ...vault, functionName: "borrowingEnabled" },
            { ...vault, functionName: "closing" },
            { ...vault, functionName: "feeBps" },
            { ...vault, functionName: "nextFeeBps" },
            { ...vault, functionName: "nextFeeAt" },
        ],
        query: { refetchInterval: 30_000 },
    });
    const at = links?.[0].result;
    const { data: reads } = useReadContracts({
        contracts: [
            { address: at!, abi: savingsSleeve, functionName: "savings" },
            { address: at!, abi: savingsSleeve, functionName: "savingsRate" },
            { address: at!, abi: savingsSleeve, functionName: "loanRate" },
            { address: at!, abi: savingsSleeve, functionName: "spreadOk" },
            { address: at!, abi: savingsSleeve, functionName: "staked" },
            { address: at!, abi: savingsSleeve, functionName: "mezoEarned" },
            { address: at!, abi: savingsSleeve, functionName: "booster" },
        ],
        query: { enabled: !!at, refetchInterval: 30_000 },
    });
    const smusd = reads?.[0].result;
    const boostAt = reads?.[6].result;
    const { data: parts } = useReadContracts({
        contracts: [
            { address: smusd!, abi: erc20, functionName: "balanceOf", args: [at!] },
            { address: smusd!, abi: erc20, functionName: "totalSupply" },
            { address: boostAt!, abi: booster, functionName: "veMezoId" },
            { address: boostAt!, abi: booster, functionName: "veMezo" },
            { address: boostAt!, abi: booster, functionName: "boostVoter" },
        ],
        query: { enabled: !!smusd && !!boostAt, refetchInterval: 30_000 },
    });
    const sleeve = useSleeve();
    const id = parts?.[2].result;
    const voter = parts?.[4].result;
    const { data: power } = useReadContracts({
        contracts: [
            { address: parts?.[3].result, abi: veMezo, functionName: "votingPowerOfNFT", args: [id] },
            ...(sleeve?.rungs ?? []).map((rung) => ({
                address: voter,
                abi: boostVoter,
                functionName: "getBoost",
                args: [rung.id],
            })),
        ] as never,
        query: { enabled: id !== undefined && !!voter && !!sleeve, refetchInterval: 60_000 },
    });
    if (!at || !links || !reads || !parts || !power) return undefined;

    const [, enabled, closing, feeBps, nextFeeBps, nextFeeAt] = links.map((r) => r.result);
    const [, savingsRate, loanRate, spreadOk, staked, mezoEarned] = reads.map((r) => r.result);
    const held = ((parts[0].result as bigint | undefined) ?? 0n) + ((staked as bigint | undefined) ?? 0n);
    const supply = parts[1].result as bigint | undefined;
    const results = power as { result?: bigint }[];
    const borrowing: Borrowing = closing
        ? "closing"
        : !enabled
          ? "off"
          : savingsRate === 0n
            ? "waiting"
            : spreadOk
              ? "on"
              : "paused";
    return {
        borrowing,
        savingsRate: Number(savingsRate ?? 0n),
        loanRate: Number(loanRate ?? 0n),
        smusdShare: supply ? Number((held * 1_000_000n) / supply) / 1e6 : 0,
        stakedShare: held > 0n ? Number(((staked as bigint) * 10_000n) / held) / 1e4 : undefined,
        staked: (staked as bigint | undefined) ?? 0n,
        mezoPending: (mezoEarned as bigint | undefined) ?? 0n,
        veMezo: id ? (results[0].result ?? 0n) : 0n,
        boosts: results.slice(1).map((r) => Number(r.result ?? 0n) / 1e18),
        fee: Number(feeBps ?? 0),
        nextFee: Number(nextFeeBps ?? 0),
        nextFeeAt: Number(nextFeeAt ?? 0n),
    };
}

/* History */

type Stamp = { id: string; time: number; hash: Hash };

export type PoolEvent = Stamp &
    (
        | { kind: "deposit" | "withdraw"; owner: Address; assets: bigint }
        | { kind: "harvest" | "mezo" | "shortfall" | "collateral"; btc: bigint }
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
            const [latest, { surplusPool }, savingsAt, feeTo, queue, sleeve] = await Promise.all([
                history.getBlock(),
                queryClient.ensureQueryData(linksQuery(client)),
                history.readContract({ ...vault, functionName: "savingsSleeve" }).catch(() => undefined),
                history.readContract({ ...vault, functionName: "feeRecipient" }).catch(() => undefined),
                history.readContract({ ...vault, functionName: "queue" }).catch(() => undefined),
                history.readContract({ ...vault, functionName: "sleeve" }).catch(() => zeroAddress),
            ]);
            // v8 sells the MEZO its sMUSD earns from the savings sleeve, so those sales list with the vault's events
            const sources = savingsAt ? [vault.address, savingsAt] : [vault.address];
            const ranges: [bigint, bigint][] = [];
            for (let from = VAULT_FROM_BLOCK; from <= latest.number; from += LOG_RANGE) {
                const to = from + LOG_RANGE - 1n;
                ranges.push([from, to < latest.number ? to : latest.number]);
            }
            const logs = (
                await Promise.all(
                    ranges.map(([fromBlock, toBlock]) =>
                        history.getLogs({ address: sources, events, fromBlock, toBlock, strict: true }),
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
            // v6 escrows queued shares at its queue, which holds them for others rather than depositing
            if (queue) holders.delete(queue.toLowerCase());
            // v8 mints its fee as shares to the booster, which is the protocol and not a depositor
            if (feeTo) holders.delete(feeTo.toLowerCase());
            const depositors = [...holders.values()].filter((shares) => shares > 0n).length;

            // Before the first deposit the pool holds nothing, a zero there would flatten the chart
            const opened = logs.find((log) => log.eventName === "Deposit")?.blockNumber ?? VAULT_FROM_BLOCK;
            const blocks = sampleBlocks(opened, latest.number, SAMPLES);

            // Mezo's logs carry blockTimestamp as 0x0, so the times come from the blocks
            const times = new Map<bigint, number>([[latest.number, Number(latest.timestamp)]]);
            const wanted = new Set([VAULT_FROM_BLOCK, ...blocks, ...logs.map((log) => log.blockNumber)]);
            const loanLogs = logs.filter((log) => log.eventName === "Rebalanced" || log.eventName === "TroveClosed");
            const before = new Map<bigint, Trove>();
            const timed = Promise.all([
                ...[...wanted]
                    .filter((blockNumber) => !times.has(blockNumber))
                    .map(async (blockNumber) => {
                        times.set(blockNumber, Number((await history.getBlock({ blockNumber })).timestamp));
                    }),
                // The loan as it stood a block earlier, so a loan event shows what it changed
                ...[...new Set(loanLogs.map((log) => log.blockNumber - 1n))].map(async (blockNumber) => {
                    before.set(
                        blockNumber,
                        await history.readContract({ ...vault, functionName: "trove", blockNumber }),
                    );
                }),
            ]);

            // Reads at one block share a multicall, its four oracle calls stay under Mezo's cap of twenty
            const read = Promise.all(
                blocks.map(async (blockNumber) => {
                    const [assets, perShare, trove, idle, surplus, locked] = await Promise.all([
                        history.readContract({ ...vault, functionName: "totalAssets", blockNumber }),
                        history.readContract({
                            ...vault,
                            functionName: "convertToAssets",
                            args: [ONE_SHARE],
                            blockNumber,
                        }),
                        history.readContract({ ...vault, functionName: "trove", blockNumber }),
                        history.readContract({
                            ...multicall,
                            functionName: "getEthBalance",
                            args: [vault.address],
                            blockNumber,
                        }),
                        history.readContract({
                            address: surplusPool,
                            abi: surplusAbi,
                            functionName: "getCollateral",
                            args: [vault.address],
                            blockNumber,
                        }),
                        sleeve === zeroAddress
                            ? 0n
                            : history
                                  .readContract({
                                      address: sleeve,
                                      abi: veSleeve,
                                      functionName: "principal",
                                      blockNumber,
                                  })
                                  .catch(() => 0n),
                    ]);
                    return { blockNumber, perShare, parts: split(assets, trove.coll, idle + surplus, locked) };
                }),
            );
            // The samples read alongside the block times, and take their time once both are in
            const [, reads] = await Promise.all([timed, read]);
            const samples: PoolSample[] = reads.map(({ blockNumber, ...sample }) => ({
                time: times.get(blockNumber)!,
                ...sample,
            }));

            const closed = new Set(
                logs.filter((log) => log.eventName === "TroveClosed").map((log) => log.transactionHash),
            );
            const activity: PoolEvent[] = [];
            let mezoHarvested = 0n;
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
                } else if (log.eventName === "MezoHarvested") {
                    mezoHarvested += log.args.mezoIn;
                    if (log.args.btcOut > 0n) activity.push({ ...stamp, kind: "mezo", btc: log.args.btcOut });
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

            return { activity, samples, depositors, mezoHarvested, launch: times.get(VAULT_FROM_BLOCK)! };
        },
    });
}
