"use client";

import { useId, useMemo, useRef, useState } from "react";
import NumberFlow from "@number-flow/react";
import { AnimatePresence, motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { smoothPath } from "@/lib/chart-path";
import { useBtcHistory, useVault } from "@/lib/hooks";
import { LIQUIDATION_CR, loanState, priceAtRatio, ratioOf } from "@/lib/math";
import { flow, pop } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

// The chart's drawing size, it runs to the tile's edges and scales with it
const WIDTH = 279;
const HEIGHT = 144;
const TOP = 12;
const BOTTOM = 14;

const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const compact = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: "compact",
    maximumFractionDigits: 1,
});

const draw = { duration: 0.9, ease: [0.3, 0.7, 0.2, 1] } as const;
const follow = { type: "spring", visualDuration: 0.15, bounce: 0 } as const;

export function Loan() {
    const { data } = useVault();
    const history = useBtcHistory().data;
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const price = data ? Number(data.price) / 1e18 : 0;
    const repay = ratio && data ? priceAtRatio(price, ratio, Number(data.minCR) / 1e18) : null;
    const liquidation = ratio ? priceAtRatio(price, ratio, LIQUIDATION_CR) : null;
    const [active, setActive] = useState<number | null>(null);

    const state = data && loanState(data.trove, data.borrowing);
    const tip =
        repay && liquidation
            ? `The pool borrows dollars against its BTC. If BTC drops to ${usd.format(repay)}, the pool pays part of the loan back from its savings. Only below ${usd.format(liquidation)} could the loan be liquidated.${state === "paused" ? " Borrowing is paused, so the loan won’t grow." : ""}`
            : state === "off"
              ? "The pool isn’t borrowing right now, so its BTC sits idle. It opens a loan once borrowing is turned on."
              : "The pool borrows dollars against its BTC once enough BTC is in. No loan is open right now.";
    const shown = active !== null && history ? history[active][1] : price;

    return (
        <Block className="pb-0">
            <BlockHeader>
                <BlockLabel tip={tip}>Pool loan</BlockLabel>
                {data && (
                    <span className="font-heading text-[17px] leading-6 font-bold tabular-nums">
                        <NumberFlow
                            {...flow}
                            value={shown}
                            format={{ style: "currency", currency: "USD", maximumFractionDigits: 0 }}
                        />
                    </span>
                )}
            </BlockHeader>
            <div className="-mx-6 mt-auto">
                <Reveal
                    ready={!!history && !!data}
                    placeholder={<Skeleton className="mx-6 mb-6 h-[120px] rounded-tile" />}
                >
                    {history && (
                        <PriceChart points={history} lines={[repay, liquidation]} active={active} onPoint={setActive} />
                    )}
                </Reveal>
            </div>
        </Block>
    );
}

// BTC's price over the last week, with the repay and liquidation prices drawn as red strokes under it
function PriceChart({
    points,
    lines,
    active,
    onPoint,
}: {
    points: [number, number][];
    lines: [number | null, number | null];
    active: number | null;
    onPoint: (index: number | null) => void;
}) {
    const gradient = useId().replace(/[^\w-]/g, "");
    const svg = useRef<SVGSVGElement>(null);
    const [repay, liquidation] = lines;

    const chart = useMemo(() => {
        const prices = points.map(([, p]) => p);
        const high = Math.max(...prices);
        // The floor reaches down to the liquidation price, so the gap between it and today is the picture
        const low = Math.min(...prices, ...(liquidation ? [liquidation] : []), ...(repay ? [repay] : []));
        const floor = liquidation ? low * 0.94 : low - (high - low) * 0.3;
        const y = (p: number) => TOP + (1 - (p - floor) / (high - floor)) * (HEIGHT - TOP - BOTTOM);
        const t0 = points[0][0];
        const t1 = points.at(-1)![0];
        const xy = points.map(([t, p]) => [((t - t0) / (t1 - t0 || 1)) * WIDTH, y(p)] as const);
        const line = smoothPath(xy);
        return { xy, line, area: `${line}L${WIDTH},${HEIGHT}L0,${HEIGHT}Z`, y };
    }, [points, repay, liquidation]);

    const point = (clientX: number) => {
        const rect = svg.current?.getBoundingClientRect();
        if (!rect) return;
        const at = ((clientX - rect.left) / rect.width) * WIDTH;
        let nearest = 0;
        for (let i = 1; i < chart.xy.length; i++)
            if (Math.abs(chart.xy[i][0] - at) < Math.abs(chart.xy[nearest][0] - at)) nearest = i;
        onPoint(nearest);
    };

    const [x, y] = chart.xy[active ?? chart.xy.length - 1];

    return (
        <svg
            ref={svg}
            viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
            className="block h-auto w-full cursor-crosshair touch-pan-y overflow-visible"
            aria-hidden="true"
            onPointerMove={(event) => point(event.clientX)}
            onPointerDown={(event) => point(event.clientX)}
            onPointerLeave={() => onPoint(null)}
        >
            <defs>
                <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="var(--gold)" stopOpacity={0.3} />
                    <stop offset="100%" stopColor="var(--gold)" stopOpacity={0} />
                </linearGradient>
            </defs>
            <rect width={WIDTH} height={HEIGHT} fill="transparent" />
            {[repay, liquidation].map((level, i) =>
                level ? (
                    <motion.g
                        key={i}
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ ...pop, delay: 0.3 + i * 0.08 }}
                    >
                        <line
                            x1={0}
                            x2={WIDTH}
                            y1={chart.y(level)}
                            y2={chart.y(level)}
                            stroke="var(--danger)"
                            strokeWidth={1.5}
                            strokeDasharray={i === 0 ? "4 5" : undefined}
                            strokeOpacity={i === 0 ? 0.7 : 1}
                        />
                        <text
                            x={WIDTH - 24}
                            y={chart.y(level) - 6}
                            textAnchor="end"
                            className="fill-danger text-[11px] font-medium tabular-nums"
                        >
                            {compact.format(level)}
                        </text>
                    </motion.g>
                ) : null,
            )}
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
                    y2={HEIGHT}
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
        </svg>
    );
}
