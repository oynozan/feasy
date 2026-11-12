"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { createPublicClient, http, zeroAddress, type Address } from "viem";
import { mezoTestnet } from "viem/chains";
import { useAccount } from "wagmi";
import {
    BOOST_VOTER,
    boostGauges,
    BTC_TOKEN,
    locker,
    MEZO_LOCKER,
    MEZO_TOKEN,
    mezoLocker,
    MUSD_TOKEN,
    priceFeed,
    token,
    VE_BTC,
    VE_MEZO,
    veNft,
} from "./chain";

const WEEK = 7 * 24 * 60 * 60;
const YEAR = 365 * 24 * 60 * 60;
const WAD = 10n ** 18n;
// Lists of a wallet's locks stop here, a wallet with more brings them in from Mezo's own app
const MAX_LOCKS = 12;

// Its own unbatched client, Mezo's RPC answers a JSON-RPC batch one call at a time
const client = createPublicClient({ chain: mezoTestnet, transport: http(), batch: { multicall: true } });

export type Rung = { id: bigint; amount: bigint; end: number; boost: number; gauge: boolean };
export type Request = { id: bigint; amount: bigint; end: bigint; claimed: bigint; claimable: bigint; readyBy: number };
export type VeLock = {
    id: bigint;
    amount: bigint;
    end: number;
    permanent: boolean;
    voted: boolean;
    approved: boolean;
    // Why it can't come in, or nothing when it can
    blocked?: string;
};

type Streams = { btc: bigint; musd: bigint };

export type LockerState = Awaited<ReturnType<typeof readLocker>>;

async function readLocker(user: Address) {
    const L = { address: locker.address, abi: locker.abi } as const;
    const M = { address: MEZO_LOCKER, abi: mezoLocker } as const;
    const ve = (address: Address) => ({ address, abi: veNft }) as const;
    // Typed by hand below, viem cannot tell two ABIs apart that share one placeholder address
    const r = (await client.multicall({
        allowFailure: false,
        contracts: [
            { ...L, functionName: "totalSupply" },
            { ...L, functionName: "locked" },
            { ...L, functionName: "queued" },
            { ...L, functionName: "filled" },
            { ...L, functionName: "paused" },
            { ...L, functionName: "live" },
            { ...L, functionName: "boostBps" },
            { ...L, functionName: "feeBps" },
            { ...L, functionName: "rewardRate", args: [BTC_TOKEN] },
            { ...L, functionName: "rewardRate", args: [MUSD_TOKEN] },
            ...[0n, 1n, 2n, 3n].map((i) => ({ ...L, functionName: "rungs", args: [i] }) as const),
            { ...L, functionName: "balanceOf", args: [user] },
            { ...L, functionName: "earned", args: [BTC_TOKEN, user] },
            { ...L, functionName: "earned", args: [MUSD_TOKEN, user] },
            { ...L, functionName: "requestsOf", args: [user] },
            { ...M, functionName: "totalSupply" },
            { ...M, functionName: "veMezoId" },
            { ...M, functionName: "balanceOf", args: [user] },
            { ...M, functionName: "earned", args: [BTC_TOKEN, user] },
            { ...M, functionName: "earned", args: [MUSD_TOKEN, user] },
            { ...M, functionName: "rewardRate", args: [BTC_TOKEN] },
            { ...M, functionName: "rewardRate", args: [MUSD_TOKEN] },
            { address: MEZO_TOKEN, abi: token, functionName: "balanceOf", args: [user] },
            { address: MEZO_TOKEN, abi: token, functionName: "allowance", args: [user, MEZO_LOCKER] },
            { ...ve(VE_BTC), functionName: "balanceOf", args: [user] },
            { ...ve(VE_MEZO), functionName: "balanceOf", args: [user] },
        ] as never,
    })) as unknown[];
    const [supply, lockedBtc, queued, filled] = r as bigint[];
    const [paused, live] = r.slice(4, 6) as boolean[];
    const [boostBps, feeBps] = r.slice(6, 8) as number[];
    const [btcRate, musdRate] = r.slice(8, 10) as bigint[];
    const slots = r.slice(10, 14) as (readonly [bigint, bigint, bigint])[];
    const [balance, earnedBtc, earnedMusd, requestIds] = r.slice(14, 18) as [bigint, bigint, bigint, readonly bigint[]];
    const [mSupply, veMezoId, mBalance, mEarnedBtc, mEarnedMusd, mBtcRate, mMusdRate, mezo, allowance] = r.slice(
        18,
        27,
    ) as bigint[];
    const [veBtcCount, veMezoCount] = r.slice(27, 29) as bigint[];

    const live_ = slots.filter(([id]) => id !== 0n);
    const ids = (owner: bigint) => Array.from({ length: Math.min(Number(owner), MAX_LOCKS) }, (_, i) => BigInt(i));
    const B = { address: BOOST_VOTER, abi: boostGauges } as const;
    const second = (await client.multicall({
        allowFailure: true,
        contracts: [
            { ...priceFeed, functionName: "fetchPrice" },
            ...live_.flatMap(([id]) => [
                { ...B, functionName: "getBoost", args: [id] } as const,
                { ...B, functionName: "boostableTokenIdToGauge", args: [id] } as const,
            ]),
            ...requestIds.flatMap((id) => [
                { ...L, functionName: "requests", args: [id] } as const,
                { ...L, functionName: "claimable", args: [id] } as const,
            ]),
            ...ids(veBtcCount).map(
                (i) => ({ ...ve(VE_BTC), functionName: "ownerToNFTokenIdList", args: [user, i] }) as const,
            ),
            ...ids(veMezoCount).map(
                (i) => ({ ...ve(VE_MEZO), functionName: "ownerToNFTokenIdList", args: [user, i] }) as const,
            ),
        ] as never,
    })) as { result?: unknown }[];
    const price = (second[0].result as bigint | undefined) ?? 0n;
    let at = 1;
    const rungs: Rung[] = live_
        .map(([id, amount, end]) => {
            const boost = (second[at++].result as bigint | undefined) ?? WAD;
            const gauge = (second[at++].result as Address | undefined) ?? zeroAddress;
            return { id, amount, end: Number(end), boost: Number(boost) / 1e18, gauge: gauge !== zeroAddress };
        })
        .sort((a, b) => a.end - b.end);
    const rawRequests = requestIds.map((id) => {
        const q = second[at++].result as readonly [Address, bigint, bigint, bigint];
        const claimable = (second[at++].result as bigint | undefined) ?? 0n;
        return { id, amount: q[1], end: q[2], claimed: q[3], claimable };
    });
    const veBtcIds = ids(veBtcCount).map(() => second[at++].result as bigint);
    const veMezoIds = ids(veMezoCount).map(() => second[at++].result as bigint);

    const lockReads = (address: Address, list: bigint[]) =>
        list.flatMap((id) => [
            { ...ve(address), functionName: "locked", args: [id] } as const,
            { ...ve(address), functionName: "voted", args: [id] } as const,
            { ...ve(address), functionName: "getApproved", args: [id] } as const,
        ]);
    const third = (await client.multicall({
        allowFailure: true,
        contracts: [...lockReads(VE_BTC, veBtcIds), ...lockReads(VE_MEZO, veMezoIds)] as never,
    })) as { result?: unknown }[];
    let k = 0;
    const now = Math.floor(Date.now() / 1000);
    const lastEnd = now - (now % WEEK) + 4 * WEEK;
    const readLocks = (list: bigint[], spender: Address, isBtc: boolean): VeLock[] =>
        list.map((id) => {
            const l = third[k++].result as { amount: bigint; end: bigint; isPermanent: boolean } | undefined;
            const voted = (third[k++].result as boolean | undefined) ?? false;
            const approvedTo = (third[k++].result as Address | undefined) ?? zeroAddress;
            const amount = l ? (l.amount < 0n ? 0n : l.amount) : 0n;
            const end = Number(l?.end ?? 0n);
            const permanent = !!l?.isPermanent;
            let blocked: string | undefined;
            if (voted) blocked = "Voting";
            else if (permanent) blocked = "Permanent";
            else if (end <= now) blocked = "Ended";
            else if (isBtc && !rungs.some((rung) => rung.end >= end && rung.end <= lastEnd)) blocked = "No match";
            return {
                id,
                amount,
                end,
                permanent,
                voted,
                approved: approvedTo.toLowerCase() === spender.toLowerCase(),
                blocked,
            };
        });

    // A request is paid by the rungs that end first, in line behind everything requested before it
    let served = filled;
    const readyAt = rungs.map((rung) => ({ end: rung.end, upTo: (served += rung.amount) }));
    const requests: Request[] = rawRequests
        .filter((q) => q.claimed < q.amount)
        .map((q) => ({ ...q, readyBy: q.end <= filled ? 0 : (readyAt.find((s) => s.upTo >= q.end)?.end ?? 0) }));

    return {
        fetchedAt: Date.now(),
        price,
        supply,
        locked: lockedBtc,
        queue: queued - filled,
        open: !paused && live,
        boostBps,
        feeBps,
        rates: { btc: btcRate, musd: musdRate } as Streams,
        rungs,
        balance,
        earned: { btc: earnedBtc, musd: earnedMusd } as Streams,
        requests,
        mezo: {
            supply: mSupply,
            lock: veMezoId,
            balance: mBalance,
            earned: { btc: mEarnedBtc, musd: mEarnedMusd } as Streams,
            rates: { btc: mBtcRate, musd: mMusdRate } as Streams,
            wallet: mezo,
            allowance,
        },
        veBtc: readLocks(veBtcIds, locker.address, true),
        veMezo: readLocks(veMezoIds, MEZO_LOCKER, false),
    };
}

export function useLocker() {
    const { address } = useAccount();
    return useQuery({
        queryKey: ["locker", address],
        queryFn: () => readLocker(address ?? zeroAddress),
        refetchInterval: 15_000,
    });
}

// A clock for figures that move every second between reads
export function useNow(every = 1000) {
    const [now, setNow] = useState(() => Date.now());
    useEffect(() => {
        const timer = setInterval(() => setNow(Date.now()), every);
        return () => clearInterval(timer);
    }, [every]);
    return now;
}

// What a holder has earned by now, the last read plus their share of each stream since
export function liveEarned(earned: Streams, rates: Streams, balance: bigint, supply: bigint, since: number, now: number) {
    if (supply === 0n || balance === 0n) return earned;
    const seconds = BigInt(Math.max(0, Math.floor((now - since) / 1000)));
    return {
        btc: earned.btc + (rates.btc * seconds * balance) / supply,
        musd: earned.musd + (rates.musd * seconds * balance) / supply,
    };
}

// A year of the current streams over what the holders' BTC is worth, in the same dollars
export function streamApr(rates: Streams, supply: bigint, price: bigint) {
    if (supply === 0n || price === 0n) return 0;
    const perSecond = (rates.btc * price) / WAD + rates.musd;
    const value = (supply * price) / WAD;
    return Number((perSecond * BigInt(YEAR) * 10_000n) / value) / 10_000;
}

// The ladder's boost, each rung weighed by its BTC
export function ladderBoost(rungs: Rung[]) {
    const total = rungs.reduce((sum, rung) => sum + rung.amount, 0n);
    if (total === 0n) return 1;
    return rungs.reduce((sum, rung) => sum + rung.boost * Number((rung.amount * 10_000n) / total), 0) / 10_000;
}
