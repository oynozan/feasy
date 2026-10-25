"use client";

import { useState } from "react";
import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { ArrowRightIcon, BookOpenIcon, ChartBarIcon } from "@heroicons/react/20/solid";
import { AnimatePresence, motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault, useYield } from "@/lib/hooks";
import { btcParts, loanState, type LoanState } from "@/lib/math";
import { fadeIn, fadeOut, flow, glide, springy } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

const figure = "font-heading text-[34px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";

// What the yield means for where the loan stands
export function yieldTip(state: LoanState | undefined) {
    if (state === "off") {
        return "The pool isn’t borrowing right now, so its BTC sits idle and earns nothing. The yield starts once borrowing is turned on.";
    }
    if (state === "paused") {
        return "Borrowing is paused, so the pool won’t borrow more, but what it already saved keeps earning. At Mezo mainnet’s rates from the last 12 weeks, a year in the pool adds this much to your BTC.";
    }
    return "Worked out from Mezo mainnet’s savings and loan rates over the last 12 weeks, since testnet’s are made up. If they hold, a year in the pool adds this much to your BTC.";
}

export function Yield() {
    const value = useYield();
    const { data } = useVault();
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={yieldTip(data && loanState(data.trove, data.borrowing))}>Yearly yield</BlockLabel>
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

// Half a tile tall, the gold pool link and a square docs link that opens to its label
export function PoolStats() {
    const [docs, setDocs] = useState(false);
    return (
        <div className="flex shrink-0 gap-1.5 lg:h-[68px]">
            {/* Both tiles start from a square, whichever is not open stays one and the other takes the rest */}
            <motion.div
                className="min-w-0 basis-[68px]"
                initial={false}
                animate={{ flexGrow: docs ? 0 : 1 }}
                whileHover="hover"
                whileTap={{ scale: 0.97 }}
                transition={{ default: glide, scale: springy }}
            >
                <Link
                    href="/pool"
                    aria-label="Pool stats"
                    className="flex h-full min-h-[68px] items-center justify-between overflow-hidden rounded-block bg-gold px-6 text-base font-medium whitespace-nowrap text-foreground transition-colors hover:bg-[color-mix(in_oklab,var(--gold),var(--white)_16%)]"
                >
                    <motion.span
                        aria-hidden="true"
                        className="overflow-hidden"
                        initial={false}
                        animate={{ opacity: docs ? 0 : 1, width: docs ? 0 : "auto" }}
                        transition={{ width: glide, opacity: docs ? fadeOut : fadeIn }}
                    >
                        Pool stats
                    </motion.span>
                    {/* Squared up beside the docs, the tile says what it opens with a chart instead of an arrow */}
                    <AnimatePresence mode="popLayout" initial={false}>
                        <motion.span
                            key={docs ? "chart" : "arrow"}
                            className="shrink-0"
                            variants={{ hover: { x: docs ? 0 : 5 } }}
                            initial={{ opacity: 0, scale: 0.4, rotate: -45 }}
                            animate={{ opacity: 1, scale: 1, rotate: 0 }}
                            exit={{ opacity: 0, scale: 0.4, rotate: 45 }}
                            transition={springy}
                        >
                            {docs ? <ChartBarIcon className="size-5" /> : <ArrowRightIcon className="size-5" />}
                        </motion.span>
                    </AnimatePresence>
                </Link>
            </motion.div>
            <motion.div
                className="min-w-0 basis-[68px] overflow-hidden rounded-block bg-card"
                initial={false}
                animate={{ flexGrow: docs ? 1 : 0 }}
                whileTap={{ scale: 0.95 }}
                transition={{ default: glide, scale: springy }}
                onHoverStart={() => setDocs(true)}
                onHoverEnd={() => setDocs(false)}
            >
                <Link
                    href="https://docs.feasy.org"
                    target="_blank"
                    rel="noreferrer"
                    aria-label="Documentation"
                    onFocus={() => setDocs(true)}
                    onBlur={() => setDocs(false)}
                    className="flex h-full min-h-[68px] items-center gap-2 px-6 text-base font-medium whitespace-nowrap text-muted-foreground transition-colors outline-none hover:text-foreground focus-visible:text-foreground"
                >
                    <BookOpenIcon className="size-5 shrink-0" />
                    <motion.span
                        aria-hidden="true"
                        animate={{ opacity: docs ? 1 : 0, x: docs ? 0 : -8 }}
                        transition={{ x: glide, opacity: docs ? fadeIn : fadeOut }}
                    >
                        Documentation
                    </motion.span>
                </Link>
            </motion.div>
        </div>
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
