"use client";

import { useState, type ReactNode } from "react";
import { ArrowDownIcon, ArrowUpIcon } from "@heroicons/react/16/solid";
import { motion } from "motion/react";
import { Skeleton } from "@/components/ui/skeleton";
import { EXPLORER } from "@/lib/chain";
import { useHistory, useVault } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { pop } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function Activity() {
    const { data } = useHistory();
    const [hovered, setHovered] = useState<number | null>(null);

    return (
        <Block>
            <BlockHeader>
                <BlockLabel>Activity</BlockLabel>
            </BlockHeader>
            <Reveal ready={!!data} placeholder={<Skeleton className="mt-3 h-14 w-full rounded-tile" />}>
                {data?.activity.length === 0 ? (
                    <p className="mt-3 text-[15px] leading-6 text-muted-foreground">No activity yet</p>
                ) : (
                    <ul
                        className="-mx-3 mt-3 max-h-[300px] overflow-y-auto [scrollbar-width:none]"
                        onPointerLeave={() => setHovered(null)}
                    >
                        {data?.activity.map((a, i) => (
                            <li key={`${a.hash}-${a.kind}`}>
                                <a
                                    href={`${EXPLORER}/tx/${a.hash}`}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="relative flex items-center gap-3 rounded-tile px-3 py-2.5 outline-none"
                                    onPointerEnter={() => setHovered(i)}
                                    onFocus={() => setHovered(i)}
                                    onBlur={() => setHovered(null)}
                                >
                                    {hovered === i && (
                                        <motion.span
                                            layoutId="activity-hover"
                                            className="absolute inset-0 -z-10 rounded-tile bg-secondary"
                                            transition={pop}
                                        />
                                    )}
                                    <Step>
                                        {a.kind === "deposit" ? (
                                            <ArrowDownIcon className="size-4" />
                                        ) : (
                                            <ArrowUpIcon className="size-4" />
                                        )}
                                    </Step>
                                    <span className="flex-1">
                                        <span className="block text-[15px] leading-5 font-medium">
                                            {a.kind === "deposit" ? "Deposit" : "Withdrawal"}
                                        </span>
                                        <span className="block text-[13px] leading-5 text-muted-foreground">
                                            {when.format(a.time * 1000)}
                                        </span>
                                    </span>
                                    <span className="text-[15px] font-medium tabular-nums">
                                        {a.kind === "deposit" ? "+" : "−"}
                                        {formatBtc(a.assets)} BTC
                                    </span>
                                </a>
                            </li>
                        ))}
                    </ul>
                )}
            </Reveal>
        </Block>
    );
}

export function HowItWorks() {
    const { data } = useVault();
    const rate = data ? `${(data.currentRateBps / 100).toLocaleString()}%` : "a fixed rate";
    const steps = [
        "You deposit BTC.",
        `The pool borrows MUSD against it at ${rate} and saves it.`,
        "What the savings earn above the loan cost becomes more BTC.",
    ];

    return (
        <Block>
            <BlockHeader>
                <BlockLabel>How it works</BlockLabel>
            </BlockHeader>
            <ol className="mt-3 flex flex-col gap-1">
                {steps.map((step, i) => (
                    <li key={i} className="flex items-center gap-3 py-2.5">
                        <Step>{i + 1}</Step>
                        <span className="flex-1 text-[15px] leading-5">{step}</span>
                    </li>
                ))}
            </ol>
        </Block>
    );
}

function Step({ children }: { children: ReactNode }) {
    return (
        <span className="grid size-9 shrink-0 place-items-center rounded-full bg-secondary text-[14px] font-medium">
            {children}
        </span>
    );
}
