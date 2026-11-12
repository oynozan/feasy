"use client";

import { useState } from "react";
import NumberFlow from "@number-flow/react";
import { ArrowRightIcon, ClockIcon, LockClosedIcon } from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import type { Address } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Skeleton } from "@/components/ui/skeleton";
import { FAUCET, locker, MEZO_LOCKER, MEZO_MAINNET, MEZO_TOKEN, mezoLocker, token, VE_BTC, VE_MEZO, veNft } from "@/lib/chain";
import { GAS_RESERVE, useVaultTx, useWalletBtc } from "@/lib/hooks";
import {
    ladderBoost,
    liveEarned,
    streamApr,
    useLocker,
    useNow,
    type LockerState,
    type Request,
    type Rung,
    type VeLock,
} from "@/lib/locker";
import { btcParts, formatBtc } from "@/lib/math";
import { flow, grow, rise, springy } from "@/lib/motion";
import { cn } from "@/lib/utils";
import { Block, BlockHeader, BlockLabel, InfoTip, Press, Reveal } from "../block";
import { AmountForm, TxSteps, type Connect } from "./amount";
import { Tile } from "./pool";

type Mode = "btc" | "mezo" | "redeem";

const WEEK = 7 * 24 * 60 * 60;
const figure = "font-heading text-[34px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";
// Locks end at midnight UTC on a Thursday, which a local zone west of UTC would call Wednesday
const thursday = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" });
const longThursday = new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
});
const whole = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
const percent = (bps: number) => `${bps / 100}%`;

export function LockView() {
    const { data } = useLocker();
    const [mode, setMode] = useState<Mode>("btc");

    return (
        <div className="grid gap-3 lg:h-full lg:grid-cols-[400px_1fr]">
            {/* Below lg the steps keep 136px and the form takes the rest of 560 */}
            <div
                data-family=""
                className="flex flex-col gap-1.5 max-lg:[&>*:first-child]:h-[136px] max-lg:[&>*:last-child]:min-h-[418px] [&>*:last-child]:flex-1"
            >
                <LockForm mode={mode} onMode={setMode} state={data} />
            </div>
            <div
                data-family=""
                className="grid gap-1.5 sm:grid-cols-2 lg:h-full lg:grid-rows-[136px_136px_1fr] [&>*]:min-h-[136px]"
            >
                <YearlyRate state={data} />
                <Boost state={data} />
                <Holdings state={data} />
                <Rewards state={data} />
                <Ladder state={data} />
            </div>
        </div>
    );
}

/* The form */

function ModeToggle({ value, onChange }: { value: Mode; onChange: (next: Mode) => void }) {
    const labels: Record<Mode, string> = { btc: "Lock BTC", mezo: "Lock MEZO", redeem: "Redeem" };
    return (
        <div role="radiogroup" aria-label="What to do" className="flex rounded-full bg-secondary p-1">
            {(["btc", "mezo", "redeem"] as const).map((option) => (
                <button
                    key={option}
                    type="button"
                    role="radio"
                    aria-checked={value === option}
                    onClick={() => onChange(option)}
                    className={cn(
                        "relative flex h-7 items-center rounded-full px-3.5 text-[13px] font-medium whitespace-nowrap transition-colors",
                        value === option ? "text-foreground" : "text-muted-foreground hover:text-foreground",
                    )}
                >
                    {value === option && (
                        <motion.span
                            layoutId="lock-mode"
                            className="absolute inset-0 rounded-full bg-card"
                            transition={springy}
                        />
                    )}
                    <span className="relative">{labels[option]}</span>
                </button>
            ))}
        </div>
    );
}

function LockForm({
    mode,
    onMode,
    state,
}: {
    mode: Mode;
    onMode: (next: Mode) => void;
    state: LockerState | undefined;
}) {
    const { address, isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const wallet = useWalletBtc();
    const gasPrice = useGasPrice().data;
    const tx = useVaultTx();

    const reserve = GAS_RESERVE * (gasPrice ?? 0n);
    const fromWallet = wallet === undefined ? undefined : wallet > reserve ? wallet - reserve : 0n;
    const connect: Connect = isConnected ? undefined : { label: "Connect wallet", run: () => openConnectModal?.() };
    const faucet: Connect =
        !MEZO_MAINNET && fromWallet === 0n
            ? { label: "Get testnet BTC", run: () => window.open(FAUCET, "_blank", "noopener") }
            : undefined;
    const paused = state && !state.open ? "Locking is paused" : undefined;
    const title = <ModeToggle value={mode} onChange={onMode} />;
    const ladder = { address: locker.address as Address, abi: locker.abi };
    const boost = { address: MEZO_LOCKER as Address, abi: mezoLocker };

    // An allowance or a lock approval goes first when it is missing, then the call itself
    async function bring(lock: VeLock, kind: "btc" | "mezo") {
        const target = kind === "btc" ? ladder : boost;
        const nft = { address: (kind === "btc" ? VE_BTC : VE_MEZO) as Address, abi: veNft };
        if (!lock.approved) {
            const ok = await tx.send({ target: nft, functionName: "approve", args: [target.address, lock.id] });
            if (!ok) return;
        }
        await tx.send({ target, functionName: "depositLock", args: [lock.id, address!] });
    }

    if (mode === "mezo") {
        return (
            <>
                <TxSteps tx={tx.state} done="Locked" />
                <AmountForm
                    key="mezo"
                    title={title}
                    source="Wallet"
                    unit="MEZO"
                    decimals={2}
                    verb="Lock MEZO"
                    busy="Locking"
                    over="Not enough MEZO"
                    max={state?.mezo.wallet}
                    blocked={paused}
                    connect={connect}
                    tx={tx.state}
                    onEdit={tx.reset}
                    extra={() => (
                        <Locks
                            kind="mezo"
                            locks={state?.veMezo}
                            busy={tx.state.status === "wallet" || tx.state.status === "pending"}
                            onBring={(lock) => bring(lock, "mezo")}
                        />
                    )}
                    onSubmit={async (amount) => {
                        if (state!.mezo.allowance < amount) {
                            const approve = { address: MEZO_TOKEN as Address, abi: token };
                            const ok = await tx.send({
                                target: approve,
                                functionName: "approve",
                                args: [MEZO_LOCKER, amount],
                            });
                            if (!ok) return false;
                        }
                        return tx.send({ target: boost, functionName: "deposit", args: [amount, address!] });
                    }}
                />
            </>
        );
    }

    if (mode === "redeem") {
        return (
            <>
                <TxSteps tx={tx.state} done="In line" />
                <AmountForm
                    key="redeem"
                    title={title}
                    source="Yours"
                    unit="fveBTC"
                    verb="Redeem"
                    busy="Redeeming"
                    over="Not enough fveBTC"
                    max={state?.balance}
                    blocked={undefined}
                    connect={connect}
                    tx={tx.state}
                    onEdit={tx.reset}
                    extra={() => (
                        <Requests
                            requests={state?.requests}
                            busy={tx.state.status === "wallet" || tx.state.status === "pending"}
                            onClaim={(id) =>
                                void tx.send({ target: ladder, functionName: "claimRedeem", args: [id] })
                            }
                        />
                    )}
                    onSubmit={(amount) => tx.send({ target: ladder, functionName: "requestRedeem", args: [amount] })}
                />
            </>
        );
    }

    return (
        <>
            <TxSteps tx={tx.state} done="Locked" />
            <AmountForm
                key="btc"
                title={title}
                source="Wallet"
                unit="BTC"
                verb="Lock BTC"
                busy="Locking"
                over="Not enough BTC"
                max={fromWallet}
                least={10n ** 14n}
                blocked={paused}
                connect={connect ?? faucet}
                tx={tx.state}
                onEdit={tx.reset}
                extra={() => (
                    <Locks
                        kind="btc"
                        locks={state?.veBtc}
                        busy={tx.state.status === "wallet" || tx.state.status === "pending"}
                        onBring={(lock) => bring(lock, "btc")}
                    />
                )}
                onSubmit={(amount) =>
                    tx.send({ target: ladder, functionName: "deposit", args: [address!], value: amount })
                }
            />
        </>
    );
}

const lockTips = {
    btc: "Locks you already hold in Mezo can come in too. Each one merges into the Feasy lock that ends the same Thursday or the next one after it, and you get fveBTC for all its BTC. A lock that votes has to reset its votes in Mezo first.",
    mezo: "veMEZO you already hold can come in too. It merges into Feasy’s permanent lock and you get fveMEZO for all of it. Mezo can’t merge a permanent lock, so unlock one from permanent in Mezo first, and reset its votes if it votes.",
};

const blockedTips: Record<string, string> = {
    Voting: "Votes",
    Permanent: "Permanent",
    Ended: "Ended",
    "No match": "Wait for Thursday",
};

// The wallet's own veBTC or veMEZO locks, each one tap away from becoming fveBTC or fveMEZO
function Locks({
    kind,
    locks,
    busy,
    onBring,
}: {
    kind: "btc" | "mezo";
    locks: VeLock[] | undefined;
    busy: boolean;
    onBring: (lock: VeLock) => void;
}) {
    if (!locks?.length) return null;
    const symbol = kind === "btc" ? "BTC" : "MEZO";
    return (
        <motion.div
            className="mt-4 flex min-h-0 flex-col"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={rise}
        >
            <div className="flex h-6 items-center gap-1.5">
                <h3 className="text-[15px] font-medium text-muted-foreground">
                    Your {kind === "btc" ? "veBTC" : "veMEZO"} locks
                </h3>
                <InfoTip>{lockTips[kind]}</InfoTip>
            </div>
            <ul className="-mx-3 mt-1 max-h-[156px] overflow-y-auto [scrollbar-width:none]">
                {locks.map((lock, i) => (
                    <motion.li
                        key={lock.id.toString()}
                        className="flex items-center gap-3 rounded-tile px-3 py-1.5"
                        initial={{ opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ ...rise, delay: i * 0.04 }}
                    >
                        <span className="grid size-9 shrink-0 place-items-center rounded-full bg-secondary">
                            <LockClosedIcon className="size-4" />
                        </span>
                        <span className="min-w-0 flex-1">
                            <span className="block text-[15px] leading-5 font-medium tabular-nums">
                                {kind === "btc"
                                    ? formatBtc(lock.amount)
                                    : whole.format(Number(lock.amount / 10n ** 16n) / 100)}{" "}
                                {symbol}
                            </span>
                            <span className="block truncate text-[13px] leading-5 text-muted-foreground">
                                {lock.permanent ? "Permanent" : `Ends ${longThursday.format(lock.end * 1000)}`}
                            </span>
                        </span>
                        {lock.blocked ? (
                            <span className="rounded-full bg-secondary px-2.5 py-1 text-[13px] font-medium whitespace-nowrap text-muted-foreground">
                                {blockedTips[lock.blocked]}
                            </span>
                        ) : (
                            <Press disabled={busy}>
                                <button
                                    type="button"
                                    disabled={busy}
                                    onClick={() => onBring(lock)}
                                    className="h-8 rounded-full bg-primary px-3.5 text-[13px] font-medium text-primary-foreground transition-opacity disabled:opacity-50"
                                >
                                    Bring in
                                </button>
                            </Press>
                        )}
                    </motion.li>
                ))}
            </ul>
        </motion.div>
    );
}

// Open exit requests, paid in order by the locks that end first
function Requests({
    requests,
    busy,
    onClaim,
}: {
    requests: Request[] | undefined;
    busy: boolean;
    onClaim: (id: bigint) => void;
}) {
    if (!requests?.length) return null;
    return (
        <motion.div
            className="mt-4 flex min-h-0 flex-col"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={rise}
        >
            <div className="flex h-6 items-center gap-1.5">
                <h3 className="text-[15px] font-medium text-muted-foreground">On its way</h3>
                <InfoTip>
                    Redeeming burns fveBTC and puts you in line for BTC. Each Thursday the lock that ends pays the line
                    first, so you wait for the next locks to end, four weeks at most. Once it’s ready, claim it here.
                </InfoTip>
            </div>
            <ul className="-mx-3 mt-1 max-h-[156px] overflow-y-auto [scrollbar-width:none]">
                {requests.map((request, i) => {
                    const left = request.amount - request.claimed;
                    const ready = request.claimable > 0n;
                    return (
                        <motion.li
                            key={request.id.toString()}
                            className="flex items-center gap-3 rounded-tile px-3 py-1.5"
                            initial={{ opacity: 0, y: 10 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ ...rise, delay: i * 0.04 }}
                        >
                            <span
                                className={cn(
                                    "grid size-9 shrink-0 place-items-center rounded-full",
                                    ready ? "bg-highlight" : "bg-secondary",
                                )}
                            >
                                <ClockIcon className="size-4" />
                            </span>
                            <span className="min-w-0 flex-1">
                                <span className="block text-[15px] leading-5 font-medium tabular-nums">
                                    {formatBtc(ready ? request.claimable : left)} BTC
                                </span>
                                <span className="block truncate text-[13px] leading-5 text-muted-foreground">
                                    {ready
                                        ? "Ready"
                                        : request.readyBy
                                          ? `Ready ${longThursday.format(request.readyBy * 1000)}`
                                          : "In line"}
                                </span>
                            </span>
                            {ready && (
                                <Press disabled={busy}>
                                    <button
                                        type="button"
                                        disabled={busy}
                                        onClick={() => onClaim(request.id)}
                                        className="h-8 rounded-full bg-primary px-3.5 text-[13px] font-medium text-primary-foreground transition-opacity disabled:opacity-50"
                                    >
                                        Claim
                                    </button>
                                </Press>
                            )}
                        </motion.li>
                    );
                })}
            </ul>
        </motion.div>
    );
}

/* Tiles */

function YearlyRate({ state }: { state: LockerState | undefined }) {
    const apr = state ? streamApr(state.rates, state.supply, state.price) : 0;
    const cuts = state
        ? ` That is after ${percent(state.boostBps)} to fveMEZO holders for the boost and ${percent(state.feeBps)} to Feasy.`
        : "";
    const tip =
        state && apr === 0
            ? "What fveBTC earns in a year, from the income streaming to holders right now. The first week’s fees reach holders after the Thursday roll that claims them, so this fills in then."
            : `What fveBTC earns in a year if this week holds. The ladder’s veBTC collects Mezo’s gauge fees in MUSD and its BTC rebates, and each week’s income streams to holders over the week after it lands.${cuts}`;
    return (
        <Tile label="Yearly rate" tip={tip} ready={!!state} placeholder={<Skeleton className="h-9 w-32" />}>
            {/* Nothing streams before the first week's income, which a dash says better than 0% */}
            <p className={figure}>
                {apr === 0 ? (
                    <span className="text-muted-foreground">–</span>
                ) : (
                    <NumberFlow
                        {...flow}
                        value={apr}
                        format={{ style: "percent", minimumFractionDigits: 2, maximumFractionDigits: 2 }}
                    />
                )}
            </p>
        </Tile>
    );
}

function Boost({ state }: { state: LockerState | undefined }) {
    const boost = state ? ladderBoost(state.rungs) : 1;
    const mezo = state ? Number(state.mezo.supply / 10n ** 16n) / 100 : 0;
    const tip = `MEZO locked through Feasy becomes fveMEZO and votes as one permanent veMEZO lock for every Feasy veBTC lock, which multiplies its weight up to 5× and so its share of the fees. fveMEZO holders get ${state ? percent(state.boostBps) : "a part"} of the ladder’s income for it. The MEZO stays locked for good, fveMEZO is how you trade out.`;
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={tip}>Boost</BlockLabel>
                {state && state.mezo.supply > 0n && (
                    <span className="text-[15px] font-medium text-muted-foreground tabular-nums">
                        {whole.format(mezo)} <span className="font-normal">veMEZO</span>
                    </span>
                )}
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <div className="min-w-0 flex-1">
                    <Reveal ready={!!state} placeholder={<Skeleton className="h-9 w-24" />}>
                        <p className={figure}>
                            <NumberFlow
                                {...flow}
                                value={boost}
                                format={{ minimumFractionDigits: 2, maximumFractionDigits: 2 }}
                            />
                            <span className="ml-0.5 tracking-normal text-muted-foreground">×</span>
                        </p>
                    </Reveal>
                </div>
            </div>
        </Block>
    );
}

function Holdings({ state }: { state: LockerState | undefined }) {
    const { head, tail } = btcParts(state?.balance ?? 0n);
    const fveMezo = state?.mezo.balance ?? 0n;
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip="fveBTC is your share of the ladder, one for every BTC you locked, and it earns while you hold it. Send it like any token, or redeem it for BTC. fveMEZO is your part of the veMEZO lock that boosts the ladder.">
                    Your fveBTC
                </BlockLabel>
                {fveMezo > 0n && (
                    <span className="text-[15px] font-medium text-muted-foreground tabular-nums">
                        {whole.format(Number(fveMezo / 10n ** 16n) / 100)} <span className="font-normal">fveMEZO</span>
                    </span>
                )}
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <div className="min-w-0 flex-1">
                    <Reveal ready={!!state} placeholder={<Skeleton className="h-9 w-44" />}>
                        <p className={figure}>
                            <NumberFlow
                                {...flow}
                                value={Number(head)}
                                format={{ minimumFractionDigits: 4, maximumFractionDigits: 4 }}
                            />
                            <NumberFlow
                                {...flow}
                                value={Number(tail)}
                                format={{ minimumIntegerDigits: 4, useGrouping: false }}
                                className="text-muted-foreground"
                            />
                        </p>
                    </Reveal>
                </div>
            </div>
        </Block>
    );
}

// The whole tile claims, its figure counts up every second as the streams pay out
function Rewards({ state }: { state: LockerState | undefined }) {
    const now = useNow();
    const tx = useVaultTx();
    const [hover, setHover] = useState(false);
    const since = state?.fetchedAt ?? now;
    const ladder = state ? liveEarned(state.earned, state.rates, state.balance, state.supply, since, now) : undefined;
    const boost = state
        ? liveEarned(state.mezo.earned, state.mezo.rates, state.mezo.balance, state.mezo.supply, since, now)
        : undefined;
    const btc = (ladder?.btc ?? 0n) + (boost?.btc ?? 0n);
    const musd = (ladder?.musd ?? 0n) + (boost?.musd ?? 0n);
    const dollars = state ? Number((btc * state.price) / 10n ** 18n + musd) / 1e18 : 0;
    const working = tx.state.status === "wallet" || tx.state.status === "pending";
    const claimable = dollars > 0 && !working;

    // Each token claims on its own, so a wallet holding only one of them signs once
    async function claim() {
        if (ladder && ladder.btc + ladder.musd > 0n) {
            const target = { address: locker.address as Address, abi: locker.abi };
            if (!(await tx.send({ target, functionName: "claim", args: [] }))) return;
        }
        if (boost && boost.btc + boost.musd > 0n) {
            const target = { address: MEZO_LOCKER as Address, abi: mezoLocker };
            await tx.send({ target, functionName: "claim", args: [] });
        }
    }

    return (
        // A div with a button's role, since the tip inside it is a button of its own
        <motion.div
            role="button"
            tabIndex={claimable ? 0 : -1}
            aria-disabled={!claimable}
            aria-label="Claim rewards"
            onClick={(event) => {
                if (claimable && !(event.target as HTMLElement).closest("button")) void claim();
            }}
            onKeyDown={(event) => {
                if (claimable && (event.key === "Enter" || event.key === " ")) {
                    event.preventDefault();
                    void claim();
                }
            }}
            onHoverStart={() => setHover(true)}
            onHoverEnd={() => setHover(false)}
            whileTap={claimable ? { scale: 0.97 } : undefined}
            transition={springy}
            className={cn("h-full outline-none", claimable && "cursor-pointer")}
        >
            <Block>
                <BlockHeader>
                    <BlockLabel
                        tip={`${formatBtc(btc)} BTC and ${(Number(musd / 10n ** 14n) / 1e4).toFixed(4)} MUSD so far, from fveBTC and fveMEZO. They stream in every second while you hold, and a tap on this tile claims them to your wallet.`}
                    >
                        Rewards
                    </BlockLabel>
                    <AnimatePresence initial={false}>
                        {claimable && (
                            <motion.span
                                key="claim"
                                className="flex items-center gap-1 text-[15px] font-medium"
                                initial={{ opacity: 0, x: -6 }}
                                animate={{ opacity: hover ? 1 : 0.6, x: hover ? 3 : 0 }}
                                exit={{ opacity: 0 }}
                                transition={springy}
                            >
                                Claim
                                <ArrowRightIcon className="size-4" />
                            </motion.span>
                        )}
                    </AnimatePresence>
                </BlockHeader>
                <div className="mt-auto flex h-12 items-center">
                    <div className="min-w-0 flex-1">
                        <Reveal ready={!!state} placeholder={<Skeleton className="h-9 w-32" />}>
                            <p className={figure}>
                                <NumberFlow
                                    {...flow}
                                    value={dollars}
                                    format={{
                                        style: "currency",
                                        currency: "USD",
                                        minimumFractionDigits: dollars < 1 ? 4 : 2,
                                        maximumFractionDigits: dollars < 1 ? 4 : 2,
                                    }}
                                />
                            </p>
                        </Reveal>
                    </div>
                </div>
            </Block>
        </motion.div>
    );
}

/* The ladder */

type Column = { end: number; rung?: Rung; queued: bigint };

// The next four Thursdays, each with the lock that ends then and what of it pays the exit line
function columns(state: LockerState, now: number): Column[] {
    const start = now - (now % WEEK);
    let line = state.queue;
    return [1, 2, 3, 4].map((k) => {
        const end = start + k * WEEK;
        const rung = state.rungs.find((r) => r.end === end);
        const queued = rung ? (line < rung.amount ? line : rung.amount) : 0n;
        line -= queued;
        return { end, rung, queued };
    });
}

function Ladder({ state }: { state: LockerState | undefined }) {
    const now = Math.floor(useNow(60_000) / 1000);
    const cols = state ? columns(state, now) : undefined;
    const weights = cols?.map((c) => (c.rung ? Number(c.rung.amount) * c.rung.boost : 0)) ?? [];
    const top = Math.max(...weights, 1);
    const releasing = state?.rungs.filter((r) => r.end <= now) ?? [];
    const releasingBtc = releasing.reduce((sum, r) => sum + r.amount, 0n);

    return (
        <Block className="h-[288px] sm:col-span-2 lg:h-auto">
            <BlockHeader>
                <BlockLabel tip="Every BTC locked through Feasy sits in one of four veBTC locks that end on the next four Thursdays, and each one votes for Mezo’s sMUSD savings gauge. A bar is the BTC in that lock, its lighter top the extra weight veMEZO adds. Each Thursday the lock that ends pays the people redeeming first, the dark part, and the rest locks again four weeks out.">
                    veBTC ladder
                </BlockLabel>
                <span className="text-[15px] font-medium tabular-nums">
                    {releasingBtc > 0n ? (
                        <span className="text-muted-foreground">
                            {formatBtc(releasingBtc, 4)} <span className="font-normal">releasing</span>
                        </span>
                    ) : (
                        state && (
                            <>
                                {formatBtc(state.locked, 4)}{" "}
                                <span className="font-normal text-muted-foreground">BTC locked</span>
                            </>
                        )
                    )}
                </span>
            </BlockHeader>
            <div className="mt-3 grid flex-1 grid-cols-4 gap-3 sm:gap-4">
                {(cols ?? [1, 2, 3, 4].map((k) => ({ end: now - (now % WEEK) + k * WEEK, queued: 0n }))).map(
                    (col, i) => (
                        <LadderColumn key={col.end} col={col} index={i} top={top} ready={!!state} />
                    ),
                )}
            </div>
        </Block>
    );
}

function LadderColumn({ col, index, top, ready }: { col: Column; index: number; top: number; ready: boolean }) {
    const rung = col.rung;
    const base = rung ? (Number(rung.amount) / top) * 100 : 0;
    const extra = rung ? (Number(rung.amount) * (rung.boost - 1) * 100) / top : 0;
    const queued = rung && rung.amount > 0n ? Number((col.queued * 10_000n) / rung.amount) / 100 : 0;
    // The bar's share of the column below the room its label needs on top of the tallest bar
    const height = `calc((100% - 28px) * ${rung ? Math.max(base + extra, 4) / 100 : 0})`;
    const delay = index * 0.06;

    return (
        <div className="flex min-w-0 flex-col">
            <div className="relative min-h-24 flex-1">
                <motion.div
                    className="absolute inset-x-0 flex flex-wrap items-baseline justify-center gap-x-1.5 text-center tabular-nums"
                    style={{ bottom: rung ? `calc(${height} + 6px)` : 14 }}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: ready ? 1 : 0, y: 0 }}
                    transition={{ ...rise, delay: delay + 0.15 }}
                >
                    <span className="text-[15px] leading-5 font-medium">{rung ? formatBtc(rung.amount, 4) : "–"}</span>
                    {rung && (
                        <span className="text-[13px] leading-5 text-muted-foreground">
                            {rung.boost > 1.005 ? `${rung.boost.toFixed(2)}×` : "1×"}
                        </span>
                    )}
                </motion.div>
                {rung ? (
                    <motion.div
                        className="absolute inset-x-0 bottom-0 flex origin-bottom flex-col overflow-hidden rounded-inner"
                        style={{ height }}
                        initial={{ scaleY: 0 }}
                        animate={{ scaleY: 1 }}
                        transition={{ ...grow, delay }}
                    >
                        {extra > 0.5 && <div className="w-full bg-second" style={{ flexGrow: extra }} />}
                        <div className="relative w-full bg-gold" style={{ flexGrow: Math.max(base, 1) }}>
                            {queued > 0 && (
                                <motion.div
                                    className="absolute inset-x-0 bottom-0 bg-primary"
                                    initial={{ height: 0 }}
                                    animate={{ height: `${queued}%` }}
                                    transition={{ ...rise, delay: delay + 0.2 }}
                                />
                            )}
                        </div>
                    </motion.div>
                ) : (
                    <div className="absolute inset-x-0 bottom-0 h-2 rounded-full bg-secondary" />
                )}
            </div>
            <p className="mt-2 text-center text-[13px] leading-5 font-medium text-muted-foreground tabular-nums">
                {thursday.format(col.end * 1000)}
            </p>
        </div>
    );
}
