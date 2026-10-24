"use client";

import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { ArrowRightIcon } from "@heroicons/react/20/solid";
import { motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault, useYield } from "@/lib/hooks";
import { btcParts } from "@/lib/math";
import { flow, springy } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

const figure = "font-heading text-[34px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";

export function Yield() {
    const value = useYield();
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip="If today’s rates hold, a year in the pool adds this much to your BTC. You can take it out whenever you like.">
                    Yearly yield
                </BlockLabel>
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <Reveal ready={value !== undefined} placeholder={<Skeleton className="h-9 w-36" />}>
                    <p className={figure}>
                        <NumberFlow
                            {...flow}
                            value={value ?? 0}
                            format={{ style: "percent", minimumFractionDigits: 2, maximumFractionDigits: 2 }}
                        />
                    </p>
                </Reveal>
            </div>
        </Block>
    );
}

export function PoolSize() {
    const { data } = useVault();
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip="All the BTC in the pool right now, everyone’s deposits plus what they have earned.">
                    Pool balance
                </BlockLabel>
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <Reveal ready={!!data} placeholder={<Skeleton className="h-9 w-40" />}>
                    <p className={figure}>
                        <BtcDigits wei={data?.totalAssets ?? 0n} />
                        <span className="ml-2 text-[18px] tracking-normal text-muted-foreground">BTC</span>
                    </p>
                </Reveal>
            </div>
        </Block>
    );
}

// Half a tile tall and gold, the whole tile is the link to the pool view
export function PoolStats() {
    return (
        <motion.div className="shrink-0 lg:h-[68px]" whileHover="hover" whileTap={{ scale: 0.97 }} transition={springy}>
            <Link
                href="/pool"
                className="flex h-full min-h-[68px] items-center justify-between rounded-block bg-gold px-6 text-base font-medium text-foreground transition-colors hover:bg-[color-mix(in_oklab,var(--gold),var(--white)_16%)]"
            >
                Pool stats
                <motion.span variants={{ hover: { x: 5 } }} transition={springy}>
                    <ArrowRightIcon className="size-5" />
                </motion.span>
            </Link>
        </motion.div>
    );
}

function BtcDigits({ wei }: { wei: bigint }) {
    const { head, tail } = btcParts(wei);
    return (
        <>
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
        </>
    );
}
