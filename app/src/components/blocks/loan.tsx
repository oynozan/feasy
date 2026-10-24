"use client";

import NumberFlow from "@number-flow/react";
import { motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault } from "@/lib/hooks";
import { dropToLiquidation, ratioOf } from "@/lib/math";
import { flow, grow } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

// The gauge runs from Mezo's 110% liquidation line to a comfortable 300%
const EMPTY = 1.1;
const FULL = 3;
const ARC = "M 10 90 A 80 80 0 0 1 170 90";

const percent = new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 0 });

export function Loan() {
    const { data } = useVault();
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const fill = ratio ? Math.min(1, Math.max(0, (ratio - EMPTY) / (FULL - EMPTY))) : 0;

    return (
        <Block>
            <BlockHeader>
                <BlockLabel>Pool loan</BlockLabel>
            </BlockHeader>
            <div className="mt-auto">
                <Reveal
                    ready={ratio !== undefined}
                    placeholder={<Skeleton className="h-[92px] w-[166px] rounded-t-full rounded-b-none" />}
                >
                    <div className="relative h-[92px] w-[166px]">
                        <svg viewBox="0 0 180 100" className="size-full overflow-visible" aria-hidden="true">
                            <path
                                d={ARC}
                                fill="none"
                                strokeWidth={16}
                                strokeLinecap="round"
                                className="stroke-second/45"
                            />
                            <motion.path
                                d={ARC}
                                fill="none"
                                strokeWidth={16}
                                strokeLinecap="round"
                                className="stroke-gold"
                                initial={{ pathLength: 0 }}
                                animate={{ pathLength: fill, opacity: fill > 0 ? 1 : 0 }}
                                transition={grow}
                            />
                        </svg>
                        <p className="absolute inset-x-0 bottom-0 text-center font-heading text-[26px] leading-none font-bold">
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
                <p className="mt-3 h-6 text-[15px] leading-6 text-muted-foreground">
                    {ratio === undefined
                        ? ""
                        : ratio
                          ? `Safe until BTC falls ${percent.format(dropToLiquidation(ratio))}`
                          : "Opens once enough BTC is pooled"}
                </p>
            </div>
        </Block>
    );
}
