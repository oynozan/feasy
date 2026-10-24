"use client";

import NumberFlow from "@number-flow/react";
import { Skeleton } from "@/components/ui/skeleton";
import { useYield } from "@/lib/hooks";
import { flow } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Reveal } from "../block";

export function Yield() {
    const value = useYield();

    return (
        <Block>
            <BlockHeader>
                <BlockLabel>Yearly yield</BlockLabel>
            </BlockHeader>
            <div className="mt-auto">
                <div className="flex h-12 items-center">
                    <Reveal ready={value !== undefined} placeholder={<Skeleton className="h-10 w-36" />}>
                        <p className="font-heading text-[44px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap">
                            <NumberFlow
                                {...flow}
                                value={value ?? 0}
                                format={{ style: "percent", maximumFractionDigits: 2 }}
                            />
                        </p>
                    </Reveal>
                </div>
                <p className="mt-3 h-6 text-[15px] leading-6 text-muted-foreground">Paid in BTC, no lock-up</p>
            </div>
        </Block>
    );
}
