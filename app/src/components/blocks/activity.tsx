"use client";

import { ArrowDownIcon, ArrowUpIcon } from "@heroicons/react/16/solid";
import { EXPLORER } from "@/lib/chain";
import { useHistory } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { Block, BlockLabel } from "../block";

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function Activity() {
    const { data } = useHistory();

    return (
        <Block>
            <BlockLabel>Activity</BlockLabel>
            {!data ? (
                <div className="mt-4 h-14 animate-pulse rounded-tile bg-secondary" />
            ) : data.activity.length === 0 ? (
                <p className="mt-4 text-[15px] text-muted-foreground">Nothing yet</p>
            ) : (
                <ul className="-mx-3 mt-2 max-h-[264px] overflow-y-auto [scrollbar-width:none]">
                    {data.activity.map((a) => (
                        <li key={`${a.hash}-${a.kind}`}>
                            <a
                                href={`${EXPLORER}/tx/${a.hash}`}
                                target="_blank"
                                rel="noreferrer"
                                className="flex items-center gap-3 rounded-tile px-3 py-2.5 transition-colors hover:bg-secondary focus-visible:bg-secondary focus-visible:outline-none"
                            >
                                <span className="grid size-9 place-items-center rounded-full bg-secondary">
                                    {a.kind === "deposit" ? (
                                        <ArrowDownIcon className="size-4" />
                                    ) : (
                                        <ArrowUpIcon className="size-4" />
                                    )}
                                </span>
                                <span className="flex-1">
                                    <span className="block text-[15px] font-medium">
                                        {a.kind === "deposit" ? "Deposit" : "Withdrawal"}
                                    </span>
                                    <span className="block text-[13px] text-muted-foreground">
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
        </Block>
    );
}
