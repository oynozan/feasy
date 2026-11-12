"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { BookOpenIcon, ChartBarIcon, LockClosedIcon } from "@heroicons/react/20/solid";
import { AnimatePresence, motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault, useYield } from "@/lib/hooks";
import { btcParts, loanState, type LoanState } from "@/lib/math";
import { fadeIn, fadeOut, flow, glide, springy } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

const figure = "font-heading text-[34px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";

// What the yield means for where the loan stands, and that it is already net of the fee
export function yieldTip(state: LoanState | undefined, feeBps = 0) {
    if (state === "off") {
        return "The pool isn’t borrowing right now, so its BTC sits idle and earns nothing. The yield starts once borrowing is turned on.";
    }
    const fee = feeBps > 0 ? ` That is after Feasy keeps ${feeBps / 100}% of the profit.` : "";
    if (state === "paused") {
        return `Borrowing is paused, so the pool won’t borrow more, but what it already saved keeps earning. At Mezo mainnet’s rates from the last 12 weeks, a year in the pool adds this much to your BTC.${fee}`;
    }
    return `Worked out from Mezo mainnet’s savings and loan rates over the last 12 weeks, since testnet’s are made up. If they hold, a year in the pool adds this much to your BTC.${fee}`;
}

export function Yield() {
    const value = useYield();
    const { data } = useVault();
    return (
        <Block>
            <BlockHeader>
                <BlockLabel tip={yieldTip(data && loanState(data.trove, data.borrowing), data?.feeBps)}>
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

// Half a tile tall, the gold pool link and a square docs link that opens to its label
export function PoolStats() {
    const [open, setOpen] = useState<"lock" | "docs" | null>(null);
    return (
        <div className="flex shrink-0 gap-1.5 lg:h-[68px]">
            {/* Every tile starts square, the open one takes the rest, Pool stats otherwise */}
            <motion.div
                className="min-w-0 basis-[68px]"
                initial={false}
                animate={{ flexGrow: open ? 0 : 1 }}
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
                        animate={{ opacity: open ? 0 : 1, width: open ? 0 : "auto" }}
                        transition={{ width: glide, opacity: open ? fadeOut : fadeIn }}
                    >
                        Pool stats
                    </motion.span>
                    {/* Squared up beside an open tile it shows a chart, at rest its label fills it */}
                    <AnimatePresence mode="popLayout" initial={false}>
                        {open && (
                            <motion.span
                                key="chart"
                                className="shrink-0"
                                initial={{ opacity: 0, scale: 0.4, rotate: -45 }}
                                animate={{ opacity: 1, scale: 1, rotate: 0 }}
                                exit={{ opacity: 0, scale: 0.4, rotate: 45 }}
                                transition={springy}
                            >
                                <ChartBarIcon className="size-5" />
                            </motion.span>
                        )}
                    </AnimatePresence>
                </Link>
            </motion.div>
            <OpenTile
                href="/lock"
                label="veBTC"
                icon={<LockClosedIcon className="size-5 shrink-0" />}
                open={open === "lock"}
                onOpen={(on) => setOpen(on ? "lock" : null)}
            />
            <OpenTile
                href="https://docs.feasy.org"
                external
                label="Docs"
                icon={<BookOpenIcon className="size-5 shrink-0" />}
                open={open === "docs"}
                onOpen={(on) => setOpen(on ? "docs" : null)}
            />
        </div>
    );
}

// A square icon tile that widens to show its label while it is hovered or focused
function OpenTile({
    href,
    external,
    label,
    icon,
    open,
    onOpen,
}: {
    href: string;
    external?: boolean;
    label: string;
    icon: ReactNode;
    open: boolean;
    onOpen: (open: boolean) => void;
}) {
    return (
        <motion.div
            className="min-w-0 basis-[68px] overflow-hidden rounded-block bg-card"
            initial={false}
            animate={{ flexGrow: open ? 1 : 0 }}
            whileTap={{ scale: 0.95 }}
            transition={{ default: glide, scale: springy }}
            onHoverStart={() => onOpen(true)}
            onHoverEnd={() => onOpen(false)}
        >
            <Link
                href={href}
                target={external ? "_blank" : undefined}
                rel={external ? "noreferrer" : undefined}
                aria-label={label}
                onFocus={() => onOpen(true)}
                onBlur={() => onOpen(false)}
                className="flex h-full min-h-[68px] items-center gap-2 px-6 text-base font-medium whitespace-nowrap text-muted-foreground transition-colors outline-none hover:text-foreground focus-visible:text-foreground"
            >
                {icon}
                <motion.span
                    aria-hidden="true"
                    animate={{ opacity: open ? 1 : 0, x: open ? 0 : -8 }}
                    transition={{ x: glide, opacity: open ? fadeIn : fadeOut }}
                >
                    {label}
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
