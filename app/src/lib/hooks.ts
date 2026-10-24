"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError, zeroAddress, type Hash } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContracts, useWriteContract } from "wagmi";
import { priceFeed, rateManager, savings, troveManager, vault, VAULT_FROM_BLOCK } from "./chain";
import { sampleBlocks, savingsApr, sharesToAssets, type Trove } from "./math";

const WEEK = 7 * 24 * 60 * 60;
// Mezo testnet averages about 4.6 seconds a block, only used to pick a block a week back
const BLOCK_SECONDS = 4.6;
const LOG_RANGE = 10_000n;
const BARS = 32;

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
            { ...troveManager, functionName: "getTroveInterestRate", args: [vault.address] },
            { ...rateManager, functionName: "interestRate" },
            { ...vault, functionName: "balanceOf", args: [user] },
            { ...vault, functionName: "maxWithdraw", args: [user] },
            { ...vault, functionName: "maxRedeem", args: [user] },
            { ...vault, functionName: "maxDeposit", args: [user] },
        ],
        query: { refetchInterval: 12_000 },
    });

    if (!data) return { isPending, data: undefined };
    const [price, lastPrice, totalAssets, totalSupply, trove, savingsValue, targetCR, troveRate, rate, ...rest] = data;
    const [shares, maxWithdraw, maxRedeem, maxDeposit] = rest;
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
            troveRateBps: troveRate.result ?? 0,
            currentRateBps: rate.result ?? 0,
            shares: userShares,
            position: sharesToAssets(userShares, assets, supply),
            maxWithdraw: maxWithdraw.result ?? 0n,
            maxRedeem: maxRedeem.result ?? 0n,
            maxDeposit: maxDeposit.result ?? 0n,
        },
    };
}

export function useWalletBtc() {
    const { address } = useAccount();
    return useBalance({ address, query: { enabled: !!address, refetchInterval: 12_000 } }).data?.value;
}

/* Savings rate */

// sMUSD's yield index over the last week, annualized
export function useSavingsApr() {
    const client = usePublicClient();
    return useQuery({
        queryKey: ["savings-apr"],
        enabled: !!client,
        staleTime: 10 * 60_000,
        queryFn: async () => {
            const latest = await client!.getBlock();
            const back = BigInt(Math.round(WEEK / BLOCK_SECONDS));
            const past = await client!.getBlock({ blockNumber: latest.number - back });
            const read = (blockNumber: bigint) =>
                client!.readContract({ ...savings, functionName: "yieldIndex", blockNumber });
            const [now, then] = await Promise.all([read(latest.number), read(past.number)]);
            return savingsApr(now, then, Number(latest.timestamp - past.timestamp));
        },
    });
}

/* History */

export type Activity = { kind: "deposit" | "withdraw"; assets: bigint; time: number; hash: Hash };
export type Bar = { time: number; btc: bigint };

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
            const moves: { block: bigint; time: number; delta: bigint }[] = [];
            let deposited = 0n;
            for (const log of mine) {
                const time = times.get(log.blockNumber)!;
                if (log.eventName === "Transfer") {
                    const { from, to, value } = log.args;
                    if (to.toLowerCase() === me) moves.push({ block: log.blockNumber, time, delta: value });
                    if (from.toLowerCase() === me) moves.push({ block: log.blockNumber, time, delta: -value });
                } else {
                    const kind = log.eventName === "Deposit" ? "deposit" : "withdraw";
                    deposited += kind === "deposit" ? log.args.assets : -log.args.assets;
                    activity.push({ kind, assets: log.args.assets, time, hash: log.transactionHash });
                }
            }
            activity.reverse();
            if (moves.length === 0) return { activity, deposited, bars: [] as Bar[] };

            const start = moves[0];
            const blocks = sampleBlocks(start.block, latest.number, BARS);
            const span = Number(latest.timestamp) - start.time;
            const last = blocks[blocks.length - 1];
            const bars = await Promise.all(
                blocks.map(async (block): Promise<Bar> => {
                    let shares = 0n;
                    for (const move of moves) if (move.block <= block) shares += move.delta;
                    // ponytail: bar times are spread linearly between the first move and now, blocks run near constant
                    const offset = last === start.block ? 1 : Number(block - start.block) / Number(last - start.block);
                    const time = start.time + span * offset;
                    if (shares === 0n) return { time, btc: 0n };
                    const btc = await client!.readContract({
                        ...vault,
                        functionName: "convertToAssets",
                        args: [shares],
                        blockNumber: block,
                    });
                    return { time, btc };
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
    | { status: "error"; message: string };

type VaultCall =
    | { functionName: "depositBTC"; args: readonly [`0x${string}`]; value: bigint }
    | { functionName: "withdraw" | "redeem"; args: readonly [bigint, `0x${string}`, `0x${string}`] };

export function useVaultTx() {
    const client = usePublicClient();
    const queryClient = useQueryClient();
    const { address } = useAccount();
    const { writeContractAsync } = useWriteContract();
    const [state, setState] = useState<TxState>({ status: "idle" });

    async function send(call: VaultCall) {
        if (!client || !address) return;
        setState({ status: "wallet" });
        try {
            // VaultCall already pins each call's shape, viem just cannot narrow the union
            const request = { ...vault, ...call, account: address } as Parameters<typeof client.estimateContractGas>[0];
            // Mezo underestimates calls through its BTC precompile and bills max(used, limit / 2), so padding is free
            const gas = ((await client.estimateContractGas(request)) * 3n) / 2n;
            const hash = await writeContractAsync({ ...request, gas } as Parameters<typeof writeContractAsync>[0]);
            setState({ status: "pending", hash });
            const receipt = await client.waitForTransactionReceipt({ hash });
            if (receipt.status !== "success") throw new Error("reverted");
            setState({ status: "done", hash });
        } catch (error) {
            setState(errorState(error));
        } finally {
            await queryClient.invalidateQueries();
        }
    }

    return { state, send, reset: () => setState({ status: "idle" }) };
}

function errorState(error: unknown): TxState {
    if (error instanceof BaseError) {
        if (error.walk((e) => e instanceof UserRejectedRequestError)) return { status: "idle" };
        const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
        const name = revert instanceof ContractFunctionRevertedError ? revert.data?.errorName : undefined;
        if (name?.startsWith("ERC4626ExceededMax"))
            return { status: "error", message: "That's more than the vault allows right now." };
        return { status: "error", message: error.shortMessage };
    }
    return { status: "error", message: "The transaction failed." };
}
