"use client";

import NumberFlow from "@number-flow/react";
import { motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault } from "@/lib/hooks";
import { dropToLiquidation, ratioOf } from "@/lib/math";
import { flow, grow } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

// Drawn from the right end, so the red arc is today's price falling toward the liquidation price
const ARC = "M 170 90 A 80 80 0 0 0 10 90";

const percent = new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 0 });

export function Loan() {
    const { data } = useVault();
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const drop = ratio ? dropToLiquidation(ratio) : 0;
    const tip = ratio
        ? `The pool borrows dollars against its BTC and keeps them in savings. BTC would have to fall ${percent.format(drop)} from today, the red part, before that loan is at risk.`
        : "The pool borrows dollars against its BTC once enough BTC is in. No loan is open right now.";

    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={tip}>Pool loan</BlockLabel>
            </BlockHeader>
            <div className="mt-auto flex justify-center">
                <Reveal
                    ready={ratio !== undefined}
                    placeholder={
                        <Skeleton className="aspect-[9/5] w-[232px] max-w-full rounded-t-full rounded-b-none" />
                    }
                >
                    <div className="relative aspect-[9/5] w-[232px] max-w-full">
                        <svg viewBox="0 0 180 100" className="size-full overflow-visible" aria-hidden="true">
                            <path d={ARC} fill="none" strokeWidth={16} strokeLinecap="round" className="stroke-track" />
                            <motion.path
                                d={ARC}
                                fill="none"
                                strokeWidth={16}
                                strokeLinecap="round"
                                className="stroke-danger"
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: drop, opacity: drop > 0 ? 1 : 0 }}
                                transition={grow}
                            />
                        </svg>
                        <p className="absolute inset-x-0 bottom-0 text-center font-heading text-[36px] leading-none font-bold">
                            {ratio ? (
                                <NumberFlow
                                    {...flow}
                                    value={ratio}
                                    format={{ style: "percent", maximumFractionDigits: 0 }}
                                />
                            ) : (
                                "–"
                            )}
                        </p>
                    </div>
                </Reveal>
            </div>
        </Block>
    );
}
