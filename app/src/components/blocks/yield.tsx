"use client";

import NumberFlow from "@number-flow/react";
import { useSavingsApr, useVault } from "@/lib/hooks";
import { vaultYield } from "@/lib/math";
import { Block, BlockLabel } from "../block";

export function Yield() {
    const { data } = useVault();
    const apr = useSavingsApr().data;
    const value = data && apr !== undefined ? vaultYield({ ...data, savingsApr: apr }) : undefined;

    return (
        <Block className="min-h-[200px] justify-between">
            <BlockLabel>Yearly yield</BlockLabel>
            {value === undefined ? (
                <div className="h-12 w-32 animate-pulse rounded-full bg-secondary" />
            ) : (
                <p className="font-heading text-[48px] leading-none font-bold tracking-[-0.03em]">
                    <NumberFlow value={value} format={{ style: "percent", maximumFractionDigits: 2 }} />
                </p>
            )}
        </Block>
    );
}
