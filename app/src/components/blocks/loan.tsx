"use client";

import NumberFlow from "@number-flow/react";
import { motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault } from "@/lib/hooks";
import { LIQUIDATION_CR, priceAtRatio, ratioOf } from "@/lib/math";
import { flow, grow, pop } from "@/lib/motion";
import { cn } from "@/lib/utils";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

// The track between today's price and the liquidation price, rows hang off it at their real distance
const TRACK = 124;
const ROW = 36;

const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const compact = { style: "currency", currency: "USD", notation: "compact", maximumFractionDigits: 1 } as const;

type Level = { key: string; price: number; label: string; dot: string };

export function Loan() {
    const { data } = useVault();
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const price = data ? Number(data.price) / 1e18 : 0;
    const repay = ratio && data ? priceAtRatio(price, ratio, Number(data.minCR) / 1e18) : 0;
    const liquidation = ratio ? priceAtRatio(price, ratio, LIQUIDATION_CR) : 0;

    const tip = ratio
        ? `The pool borrows dollars against its BTC. If BTC drops to ${usd.format(repay)}, the pool pays part of the loan back from its savings. Only below ${usd.format(liquidation)} could the loan be liquidated.`
        : "The pool borrows dollars against its BTC once enough BTC is in. No loan is open right now.";

    const levels: Level[] = [
        {
            key: "now",
            price,
            label: repay >= price ? "Now, repaying" : "Now",
            dot: "size-4 bg-safe ring-4 ring-safe/25",
        },
        ...(repay < price
            ? [{ key: "repay", price: repay, label: "Pool repays part", dot: "size-3.5 border-2 border-safe bg-card" }]
            : []),
        { key: "liquidation", price: liquidation, label: "Liquidation", dot: "size-4 bg-danger ring-4 ring-danger/20" },
    ];

    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={tip}>Pool loan</BlockLabel>
            </BlockHeader>
            <div className="flex flex-1 items-center justify-center">
                <Reveal
                    ready={ratio !== undefined}
                    placeholder={<Skeleton className="h-[160px] w-[140px] rounded-tile" />}
                >
                    {ratio ? (
                        <Ladder levels={levels} top={price} bottom={liquidation} />
                    ) : (
                        <p className="text-[15px] leading-6 text-muted-foreground">No loan open yet</p>
                    )}
                </Reveal>
            </div>
        </Block>
    );
}

function Ladder({ levels, top, bottom }: { levels: Level[]; top: number; bottom: number }) {
    const at = (price: number) => (top > bottom ? ((top - price) / (top - bottom)) * TRACK : 0);
    return (
        // Rows stay in the flow so the ladder is only as wide as its longest label and centres cleanly
        <div className="relative flex w-max flex-col" style={{ height: TRACK + ROW }}>
            <motion.span
                aria-hidden="true"
                className="absolute left-[5px] w-1.5 origin-top rounded-full bg-linear-to-b from-safe to-danger"
                style={{ top: ROW / 2, height: TRACK }}
                initial={{ scaleY: 0 }}
                animate={{ scaleY: 1 }}
                transition={grow}
            />
            {levels.map((level, i) => (
                <motion.div
                    key={level.key}
                    className="relative flex shrink-0 items-center gap-3"
                    style={{ height: ROW }}
                    initial={{ marginTop: 0, opacity: 0 }}
                    animate={{
                        marginTop: i === 0 ? 0 : at(level.price) - at(levels[i - 1].price) - ROW,
                        opacity: 1,
                    }}
                    transition={{ ...grow, delay: i * 0.06 }}
                >
                    <span className="grid w-4 place-items-center">
                        <motion.span
                            className={cn("rounded-full", level.dot)}
                            initial={{ scale: 0 }}
                            animate={{ scale: 1 }}
                            transition={{ ...pop, delay: 0.15 + i * 0.06 }}
                        />
                    </span>
                    <span>
                        <span className="block font-heading text-[17px] leading-5 font-bold tabular-nums">
                            <NumberFlow {...flow} value={level.price} format={compact} />
                        </span>
                        <span className="block text-[13px] leading-4 text-muted-foreground">{level.label}</span>
                    </span>
                </motion.div>
            ))}
        </div>
    );
}
