"use client";

import NumberFlow from "@number-flow/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useVault, useYield } from "@/lib/hooks";
import { flow } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

const figure = "font-heading text-[40px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums";

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
                            format={{ style: "percent", maximumFractionDigits: 2 }}
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
                    In the pool
                </BlockLabel>
            </BlockHeader>
            <div className="mt-auto flex h-12 items-center">
                <Reveal ready={!!data} placeholder={<Skeleton className="h-9 w-40" />}>
                    <p className={figure}>
                        <NumberFlow
                            {...flow}
                            value={data ? Number(data.totalAssets) / 1e18 : 0}
                            format={{ minimumFractionDigits: 4, maximumFractionDigits: 4 }}
                        />
                        <span className="ml-2 text-[18px] tracking-normal text-muted-foreground">BTC</span>
                    </p>
                </Reveal>
            </div>
        </Block>
    );
}
