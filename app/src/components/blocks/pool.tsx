"use client";

import { useEffect, useId, useMemo, useRef, useState, type ReactNode } from "react";
import NumberFlow from "@number-flow/react";
import {
    ArrowDownIcon,
    ArrowTrendingDownIcon,
    ArrowTrendingUpIcon,
    ArrowUpIcon,
    BanknotesIcon,
    CheckIcon,
    ReceiptPercentIcon,
    ScaleIcon,
    SparklesIcon,
} from "@heroicons/react/16/solid";
import { AnimatePresence, motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { EXPLORER } from "@/lib/chain";
import { smoothPath } from "@/lib/chart-path";
import { useSavingsApr, useVault, useYield } from "@/lib/hooks";
import { btcParts, formatBtc, LIQUIDATION_CR, priceAtRatio, ratioOf, WAD } from "@/lib/math";
import { flow, pop, rise, springy } from "@/lib/motion";
import { usePoolHistory, usePoolState, type PoolEvent, type PoolSample } from "@/lib/pool";
import { cn } from "@/lib/utils";
import { Block, BlockHeader, BlockLabel, CloseButton, Eyebrow, FigureRow, Reveal } from "../block";
import { Wordmark } from "../frame";

// Headroom over the highest sample as a share of the chart, so a flat pool reads as a level line
const HEADROOM = 0.12;
const BOTTOM = 28;
// Samples sit this far inside the chart's edges so the hover dot is never cut by the block's corner
const INSET = 12;

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
const day = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" });
const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const whole = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
const percent = (value: number, digits = 0) =>
    value.toLocaleString("en-US", { style: "percent", maximumFractionDigits: digits });
// A true minus like the activity list, Intl's own sign is a hyphen
const signed = (value: bigint, text: (abs: bigint) => string) =>
    `${value < 0n ? "−" : "+"}${text(value < 0n ? -value : value)}`;

const figure = "font-heading text-[34px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";
const draw = { duration: 0.9, ease: [0.3, 0.7, 0.2, 1] } as const;
const follow = { type: "spring", visualDuration: 0.15, bounce: 0 } as const;

export function PoolView() {
    const { data: history, isError } = usePoolHistory();
    // A failed refetch keeps the last history, only a first load that never landed shows as failed
    const failed = isError && !history;
    const [pointed, setPointed] = useState<number | null>(null);
    const sample = pointed !== null ? history?.samples[pointed] : undefined;

    return (
        <div className="grid gap-3 lg:h-full lg:grid-cols-[400px_1fr]">
            <PoolBalance
                samples={history?.samples}
                sample={sample}
                active={sample ? pointed : null}
                failed={failed}
                onPoint={setPointed}
            />
            <div
                data-family=""
                className="grid gap-1.5 sm:grid-cols-2 lg:h-full lg:grid-rows-[136px_136px_1fr] [&>*]:min-h-[136px]"
            >
                <SinceLaunch launch={history?.launch} sample={sample} />
                <YearlyYield />
                <LoanHealth />
                <Savings />
                <PoolActivity activity={history?.activity} depositors={history?.depositors} failed={failed} />
            </div>
        </div>
    );
}

/* Pool balance */

function PoolBalance({
    samples,
    sample,
    active,
    failed,
    onPoint,
}: {
    samples: PoolSample[] | undefined;
    sample: PoolSample | undefined;
    active: number | null;
    failed: boolean;
    onPoint: (index: number | null) => void;
}) {
    const live = usePoolState().parts;
    const parts = sample?.parts ?? live;

    return (
        <Block className="pb-0">
            <BlockHeader>
                <Wordmark />
                <CloseButton />
            </BlockHeader>
            <Eyebrow>
                {sample ? (
                    when.format(sample.time * 1000)
                ) : (
                    <BlockLabel tip="All the BTC in the pool. Withdrawals take the BTC kept aside first and then free some from the loan, and the last row is what the dollar savings hold beyond what the loan owes.">
                        Pool balance
                    </BlockLabel>
                )}
            </Eyebrow>
            <FigureRow>
                <Reveal ready={!!parts} placeholder={<Skeleton className="h-10 w-60" />}>
                    <BtcFigure wei={parts?.total ?? 0n} />
                </Reveal>
            </FigureRow>
            <dl
                data-row="chip"
                className="mt-3 grid grid-cols-[auto_1fr] items-baseline gap-x-3 text-[15px] leading-7 text-muted-foreground"
            >
                <Part label="Backing the loan" wei={parts?.loan} />
                <Part label="Kept aside" wei={parts?.aside} />
                <Part label="Savings minus loan" wei={parts?.rest} />
            </dl>
            <PoolChart samples={samples} active={active} failed={failed} onPoint={onPoint} />
        </Block>
    );
}

// Whole satoshis, the last four digits quieter so the first ones read at a glance
function BtcFigure({ wei }: { wei: bigint }) {
    const { head, tail } = btcParts(wei);
    return (
        <p className="font-heading text-[44px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums">
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
            <span className="ml-2 text-[18px] tracking-normal text-muted-foreground">BTC</span>
        </p>
    );
}

function Part({ label, wei }: { label: string; wei: bigint | undefined }) {
    return (
        <>
            <dt className="whitespace-nowrap">{label}</dt>
            <dd className="text-[22px] font-medium tracking-[-0.01em] tabular-nums">
                <Reveal ready={wei !== undefined} placeholder={<PartPlaceholder />}>
                    <NumberFlow
                        {...flow}
                        value={Number((wei ?? 0n) / 10n ** 10n) / 1e8}
                        prefix={wei !== undefined && wei < 0n ? "−" : undefined}
                        format={{ minimumFractionDigits: 8, maximumFractionDigits: 8, signDisplay: "never" }}
                    />
                    <span className="ml-1.5 text-[15px] font-normal tracking-normal">BTC</span>
                </Reveal>
            </dd>
        </>
    );
}

// A hidden NumberFlow gives the placeholder the same line box and width as the amount it stands for
function PartPlaceholder() {
    return (
        <span className="relative inline-block">
            <span className="invisible">
                <NumberFlow value={0} format={{ minimumFractionDigits: 8, maximumFractionDigits: 8 }} />
                <span className="ml-1.5 text-[15px] font-normal tracking-normal">BTC</span>
            </span>
            <Skeleton className="absolute inset-x-0 top-1/2 h-5 -translate-y-1/2" />
        </span>
    );
}

// The pool's BTC at evenly spaced blocks since its first deposit, drawn to the block's edges
function PoolChart({
    samples,
    active,
    failed,
    onPoint,
}: {
    samples: PoolSample[] | undefined;
    active: number | null;
    failed: boolean;
    onPoint: (index: number | null) => void;
}) {
    const box = useRef<HTMLDivElement>(null);
    const gradient = useId().replace(/[^\w-]/g, "");
    const [size, setSize] = useState({ width: 0, height: 0 });

    // Drawn at the box's own pixel size so strokes and the dot never stretch
    useEffect(() => {
        const observer = new ResizeObserver(([entry]) =>
            setSize({ width: entry.contentRect.width, height: entry.contentRect.height }),
        );
        observer.observe(box.current!);
        return () => observer.disconnect();
    }, []);

    const chart = useMemo(() => {
        if (!samples?.length || size.width === 0) return null;
        const { width, height } = size;
        const values = samples.map((s) => Number(s.parts.total) / 1e18);
        const high = Math.max(...values);
        const low = Math.min(...values);
        // A floor under the lowest sample keeps small moves visible instead of pressing them flat on zero
        const floor = high > low ? Math.max(0, low - (high - low) * 0.5) : low * 0.5;
        const top = height * HEADROOM;
        const y = (v: number) =>
            high > floor ? top + (1 - (v - floor) / (high - floor)) * (height - top - BOTTOM) : height / 2;
        const t0 = samples[0].time;
        const span = samples.at(-1)!.time - t0 || 1;
        const xy = samples.map(
            (s, i) =>
                [
                    samples.length > 1 ? INSET + ((s.time - t0) / span) * (width - 2 * INSET) : width - INSET,
                    y(values[i]),
                ] as const,
        );
        // The line runs on flat to both edges so it still bleeds full width past the inset samples
        const line = smoothPath([[0, xy[0][1]], ...xy, [width, xy.at(-1)![1]]]);
        return { xy, line, area: `${line}L${width},${height}L0,${height}Z` };
    }, [samples, size]);

    const point = (event: React.PointerEvent<SVGSVGElement>) => {
        if (!chart) return;
        const at = event.clientX - event.currentTarget.getBoundingClientRect().left;
        let nearest = 0;
        for (let i = 1; i < chart.xy.length; i++)
            if (Math.abs(chart.xy[i][0] - at) < Math.abs(chart.xy[nearest][0] - at)) nearest = i;
        onPoint(nearest);
    };

    const [x, y] = chart ? chart.xy[active ?? chart.xy.length - 1] : [0, 0];

    return (
        <div ref={box} className="relative -mx-6 mt-6 min-h-[170px] flex-1 lg:min-h-0">
            <AnimatePresence initial={false}>
                {chart ? (
                    <motion.svg
                        key="chart"
                        viewBox={`0 0 ${size.width} ${size.height}`}
                        width={size.width}
                        height={size.height}
                        className="absolute inset-0 cursor-crosshair touch-pan-y overflow-visible"
                        aria-hidden="true"
                        onPointerMove={point}
                        onPointerDown={point}
                        onPointerLeave={() => onPoint(null)}
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={rise}
                    >
                        <defs>
                            <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
                                <stop offset="0%" stopColor="var(--gold)" stopOpacity={0.3} />
                                <stop offset="100%" stopColor="var(--gold)" stopOpacity={0} />
                            </linearGradient>
                        </defs>
                        <rect width={size.width} height={size.height} fill="transparent" />
                        <motion.path
                            d={chart.area}
                            fill={`url(#${gradient})`}
                            initial={{ opacity: 0 }}
                            animate={{ opacity: 1 }}
                            transition={{ duration: 0.5, delay: 0.2 }}
                        />
                        <motion.path
                            d={chart.line}
                            fill="none"
                            stroke="var(--gold)"
                            strokeWidth={2.5}
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            initial={{ pathLength: 0 }}
                            animate={{ pathLength: 1 }}
                            transition={draw}
                        />
                        {active !== null && (
                            <motion.line
                                y1={0}
                                y2={size.height}
                                stroke="var(--muted-foreground)"
                                strokeOpacity={0.4}
                                strokeWidth={1.5}
                                strokeDasharray="3 4"
                                initial={{ x1: x, x2: x }}
                                animate={{ x1: x, x2: x }}
                                transition={follow}
                            />
                        )}
                        <AnimatePresence>
                            {active !== null && (
                                <motion.circle
                                    key="dot"
                                    fill="var(--gold)"
                                    stroke="var(--card)"
                                    strokeWidth={2.5}
                                    r={5.5}
                                    initial={{ scale: 0, cx: x, cy: y }}
                                    animate={{ scale: 1, cx: x, cy: y }}
                                    exit={{ scale: 0 }}
                                    transition={{ default: follow, scale: pop }}
                                    style={{ transformBox: "fill-box", transformOrigin: "center" }}
                                />
                            )}
                        </AnimatePresence>
                    </motion.svg>
                ) : failed ? (
                    <motion.p
                        key="failed"
                        className="absolute inset-x-6 top-0 bottom-6 grid place-items-center text-[15px] text-muted-foreground"
                        initial={{ opacity: 0, scale: 0.96 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={rise}
                    >
                        Couldn’t load the history
                    </motion.p>
                ) : (
                    <motion.div
                        key="waiting"
                        className="absolute inset-x-6 top-0 bottom-6"
                        exit={{ opacity: 0, transition: { duration: 0.12 } }}
                    >
                        <Skeleton className="size-full rounded-tile" />
                    </motion.div>
                )}
            </AnimatePresence>
        </div>
    );
}

/* Tiles */

function Tile({
    label,
    tip,
    ready,
    placeholder,
    children,
}: {
    label: string;
    tip: string;
    ready: boolean;
    placeholder: ReactNode;
    children: ReactNode;
}) {
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={tip}>{label}</BlockLabel>
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <div className="min-w-0 flex-1">
                    <Reveal ready={ready} placeholder={placeholder}>
                        {children}
                    </Reveal>
                </div>
            </div>
        </Block>
    );
}

// One share's BTC value against the exact 1 BTC it was worth before anyone deposited
function SinceLaunch({ launch, sample }: { launch: number | undefined; sample: PoolSample | undefined }) {
    const { perShare } = usePoolState();
    const shown = sample?.perShare ?? perShare;
    const change = Number(shown ?? WAD) / 1e18 - 1;
    // Under half a hundredth of a percent rounds to 0.00%, which takes no sign
    const sign = Math.abs(change) < 0.00005 ? "" : change > 0 ? "+" : "−";
    const tip =
        launch !== undefined && perShare !== undefined
            ? `One BTC put in when the pool opened on ${day.format(launch * 1000)} is worth ${formatBtc(perShare)} BTC today.`
            : "How much one BTC put in when the pool opened is worth today.";

    return (
        <Tile
            label="Since launch"
            tip={tip}
            ready={shown !== undefined}
            placeholder={<Skeleton className="h-9 w-32" />}
        >
            <p className={figure}>
                <NumberFlow
                    {...flow}
                    value={change}
                    prefix={sign}
                    format={{
                        style: "percent",
                        minimumFractionDigits: 2,
                        maximumFractionDigits: 2,
                        signDisplay: "never",
                    }}
                />
            </p>
        </Tile>
    );
}

function YearlyYield() {
    const value = useYield();
    return (
        <Tile
            label="Yearly yield"
            tip="If today’s rates hold, a year in the pool adds this much to every BTC in it. You can take yours out whenever you like."
            ready={value !== undefined}
            placeholder={<Skeleton className="h-9 w-36" />}
        >
            <p className={figure}>
                <NumberFlow
                    {...flow}
                    value={value ?? 0}
                    format={{ style: "percent", minimumFractionDigits: 2, maximumFractionDigits: 2 }}
                />
            </p>
        </Tile>
    );
}

function LoanHealth() {
    const { data } = useVault();
    const { maxCR } = usePoolState();
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const levels = data &&
        maxCR !== undefined && {
            repay: Number(data.minCR) / 1e18,
            target: Number(data.targetCR) / 1e18,
            ceiling: Number(maxCR) / 1e18,
        };
    const price = data ? Number(data.price) / 1e18 : 0;

    const tip =
        ratio === undefined || !data
            ? "How much the pool’s BTC is worth against the dollars it borrowed."
            : ratio === null
              ? "No loan is open right now. The pool borrows against its BTC once enough of it is in."
              : `The pool’s BTC is worth ${percent(ratio)} of its loan and is steered back to ${percent(Number(data.targetCR) / 1e18)}. If BTC falls to ${usd.format(priceAtRatio(price, ratio, Number(data.minCR) / 1e18))} it repays some of the loan from savings, and only at ${usd.format(priceAtRatio(price, ratio, LIQUIDATION_CR))} could it be liquidated.`;

    return (
        <Tile
            label="Loan health"
            tip={tip}
            ready={ratio !== undefined && !!levels}
            placeholder={<Skeleton className="h-9 w-full" />}
        >
            <div className="flex items-center gap-4">
                <p className={figure}>
                    {ratio ? (
                        <NumberFlow {...flow} value={ratio} format={{ style: "percent", maximumFractionDigits: 0 }} />
                    ) : (
                        "—"
                    )}
                </p>
                {levels && <Meter ratio={ratio ?? null} {...levels} />}
            </div>
        </Tile>
    );
}

// Where the ratio sits between liquidation, the repay floor, the target and the borrow-more ceiling
function Meter({
    ratio,
    repay,
    target,
    ceiling,
}: {
    ratio: number | null;
    repay: number;
    target: number;
    ceiling: number;
}) {
    const low = 1;
    const high = Math.max(ceiling * 1.12, (ratio ?? 0) * 1.06);
    const at = (r: number) => `${(Math.min(Math.max((r - low) / (high - low), 0), 1) * 100).toFixed(2)}%`;
    const span = (from: number, to: number) => ({ left: at(from), right: `calc(100% - ${at(to)})` });

    // Two tiles a row leave too little width for the zones to read apart
    return (
        <div className="relative h-2 min-w-0 flex-1 rounded-full bg-secondary sm:max-lg:hidden">
            <span className="absolute inset-y-0 rounded-l-full bg-danger" style={span(low, LIQUIDATION_CR)} />
            <span className="absolute inset-y-0 bg-danger/25" style={span(LIQUIDATION_CR, repay)} />
            <span className="absolute inset-y-0 bg-second" style={span(repay, ceiling)} />
            <span
                className="absolute -inset-y-1 w-0.5 -translate-x-1/2 rounded-full bg-foreground/30"
                style={{ left: at(target) }}
            />
            {ratio !== null && (
                <motion.span
                    className="absolute top-1/2 size-4 rounded-full bg-gold ring-[3px] ring-card"
                    style={{ x: "-50%", y: "-50%" }}
                    initial={{ left: at(low) }}
                    animate={{ left: at(ratio) }}
                    transition={springy}
                />
            )}
        </div>
    );
}

function Savings() {
    const { data } = useVault();
    const { gasComp } = usePoolState();
    const apr = useSavingsApr().data;
    // The trove's debt counts a gas deposit Mezo hands back on close, so the pool owes that much less
    const tip =
        data?.trove.active && apr !== undefined && gasComp !== undefined
            ? `The pool owes ${whole.format(Number(data.trove.debt - gasComp) / 1e18)} MUSD on its loan and keeps the borrowed dollars in Mezo’s savings vault, earning ${percent(apr, 2)} a year while the loan costs ${percent(data.troveRateBps / 1e4, 2)}.`
            : "The dollars the pool borrows wait in Mezo’s savings vault, earning more than the loan costs.";

    return (
        <Tile label="Savings" tip={tip} ready={!!data} placeholder={<Skeleton className="h-9 w-40" />}>
            <p className={figure}>
                <NumberFlow
                    {...flow}
                    value={Number(data?.savings ?? 0n) / 1e18}
                    format={{ maximumFractionDigits: 0 }}
                />
                <span className="ml-2 text-[18px] tracking-normal text-muted-foreground">MUSD</span>
            </p>
        </Tile>
    );
}

/* Activity */

const kinds = {
    deposit: { title: "Deposit", icon: ArrowDownIcon },
    withdraw: { title: "Withdrawal", icon: ArrowUpIcon },
    harvest: { title: "Savings income", icon: SparklesIcon },
    shortfall: { title: "Loan cost paid", icon: ReceiptPercentIcon },
    open: { title: "Loan opened", icon: BanknotesIcon },
    borrow: { title: "Borrowed more", icon: ArrowTrendingUpIcon },
    repay: { title: "Loan paid down", icon: ArrowTrendingDownIcon },
    close: { title: "Loan repaid", icon: CheckIcon },
    collateral: { title: "Collateral added", icon: ScaleIcon },
} as const;

function PoolActivity({
    activity,
    depositors,
    failed,
}: {
    activity: PoolEvent[] | undefined;
    depositors: number | undefined;
    failed: boolean;
}) {
    const [hovered, setHovered] = useState<string | null>(null);

    return (
        <Block className="h-[240px] pb-0 sm:col-span-2 lg:h-full">
            <BlockHeader>
                <BlockLabel tip="Everyone’s deposits and withdrawals, each change to the pool’s loan, the savings income turned into BTC and the BTC spent on the loan’s fees and interest.">
                    Pool activity
                </BlockLabel>
                {!failed && (
                    <Reveal ready={depositors !== undefined} placeholder={<Skeleton className="h-5 w-24" />}>
                        <span className="block text-[15px] leading-6 text-muted-foreground tabular-nums">
                            <NumberFlow
                                {...flow}
                                value={depositors ?? 0}
                                suffix={depositors === 1 ? " depositor" : " depositors"}
                            />
                        </span>
                    </Reveal>
                )}
            </BlockHeader>
            <div className="relative -mx-3 mt-3 min-h-0 flex-1">
                <div className="absolute inset-0 overflow-y-auto pb-10 [mask-image:linear-gradient(to_bottom,black_calc(100%-40px),transparent)] [scrollbar-width:none]">
                    <Reveal ready={!!activity || failed} placeholder={<RowsPlaceholder />}>
                        {!activity || activity.length === 0 ? (
                            <p className="px-3 text-[15px] leading-6 text-muted-foreground">
                                {failed ? "Couldn’t load activity" : "No activity yet"}
                            </p>
                        ) : (
                            <ul className="isolate" onPointerLeave={() => setHovered(null)}>
                                {activity.map((event) => (
                                    <li key={event.id}>
                                        <a
                                            href={`${EXPLORER}/tx/${event.hash}`}
                                            target="_blank"
                                            rel="noreferrer"
                                            className="relative flex items-center gap-3 rounded-tile px-3 py-2.5 outline-none"
                                            onPointerEnter={() => setHovered(event.id)}
                                            onFocus={() => setHovered(event.id)}
                                            onBlur={() => setHovered(null)}
                                        >
                                            {hovered === event.id && (
                                                <motion.span
                                                    layoutId="pool-activity-hover"
                                                    className="absolute inset-0 -z-10 rounded-tile bg-secondary"
                                                    transition={pop}
                                                />
                                            )}
                                            <Row event={event} />
                                        </a>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </Reveal>
                </div>
            </div>
        </Block>
    );
}

function Row({ event }: { event: PoolEvent }) {
    const { title, icon: Icon } = kinds[event.kind];
    const who = "owner" in event ? `${event.owner.slice(0, 6)}…${event.owner.slice(-4)}` : null;
    return (
        <>
            <span
                className={cn(
                    "grid size-9 shrink-0 place-items-center rounded-full",
                    event.kind === "harvest" ? "bg-highlight" : "bg-secondary",
                )}
            >
                <Icon className="size-4" />
            </span>
            <span className="min-w-0 flex-1">
                <span className="block text-[15px] leading-5 font-medium">{title}</span>
                <span className="block truncate text-[13px] leading-5 text-muted-foreground">
                    {when.format(event.time * 1000)}
                    {/* Narrow rows keep the date whole and drop the address */}
                    {who && <span className="hidden lg:inline"> · {who}</span>}
                </span>
            </span>
            <span className="text-[15px] font-medium whitespace-nowrap tabular-nums">
                <Amount event={event} />
            </span>
        </>
    );
}

// BTC in and out of the pool in full, loan moves muted since they stay inside it
function Amount({ event }: { event: PoolEvent }) {
    const btc = (abs: bigint) => `${formatBtc(abs)} BTC`;
    switch (event.kind) {
        case "deposit":
        case "withdraw":
            return signed(event.kind === "deposit" ? event.assets : -event.assets, btc);
        case "harvest":
            return signed(event.btc, btc);
        case "shortfall":
            return signed(-event.btc, btc);
        case "collateral":
            return <span className="text-muted-foreground">{signed(event.btc, btc)}</span>;
        default:
            return (
                <span className="text-muted-foreground">
                    {signed(event.musd, (abs) => `${whole.format(Number(abs) / 1e18)} MUSD`)}
                </span>
            );
    }
}

function RowsPlaceholder() {
    return (
        <div>
            {[0, 1, 2].map((i) => (
                <div key={i} className="flex items-center gap-3 px-3 py-2.5">
                    <Skeleton className="size-9 shrink-0" />
                    <div className="flex-1">
                        <Skeleton className="my-1 h-3 w-24" />
                        <Skeleton className="my-1 h-3 w-36" />
                    </div>
                    <Skeleton className="h-4 w-36" />
                </div>
            ))}
        </div>
    );
}
