"use client";

import { PolarAngleAxis, RadialBar, RadialBarChart } from "recharts";
import { ChartContainer } from "@/components/ui/chart";
import { useVault } from "@/lib/hooks";
import { dropToLiquidation, ratioOf } from "@/lib/math";
import { Block, BlockLabel } from "../block";

// The gauge runs from Mezo's 110% liquidation line to a comfortable 300%
const EMPTY = 1.1;
const FULL = 3;

const percent = new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 0 });

export function Loan() {
    const { data } = useVault();
    const ratio = data ? ratioOf(data.trove, data.price) : undefined;
    const fill = ratio ? Math.min(100, Math.max(0, ((ratio - EMPTY) / (FULL - EMPTY)) * 100)) : 0;

    return (
        <Block className="min-h-[200px]">
            <BlockLabel>Loan</BlockLabel>
            {ratio === undefined ? (
                <div className="mx-auto mt-6 h-24 w-44 animate-pulse rounded-t-full bg-secondary" />
            ) : (
                <>
                    <div className="relative mx-auto mt-2 h-[104px] w-[208px]">
                        <ChartContainer config={{ ratio: { label: "Ratio" } }} className="aspect-auto size-full">
                            <RadialBarChart
                                data={[{ ratio: fill }]}
                                startAngle={180}
                                endAngle={0}
                                innerRadius="140%"
                                outerRadius="190%"
                                cy="100%"
                            >
                                <PolarAngleAxis type="number" domain={[0, 100]} tick={false} axisLine={false} />
                                <RadialBar
                                    dataKey="ratio"
                                    cornerRadius={99}
                                    fill="var(--gold)"
                                    background={{ fill: "var(--second)", opacity: 0.45 }}
                                />
                            </RadialBarChart>
                        </ChartContainer>
                        <p className="absolute inset-x-0 bottom-0 text-center font-heading text-[28px] leading-none font-bold">
                            {ratio ? percent.format(ratio) : "–"}
                        </p>
                    </div>
                    <p className="mt-3 text-center text-[15px] text-muted-foreground">
                        {ratio
                            ? `Safe until BTC falls ${percent.format(dropToLiquidation(ratio))}`
                            : "No loan open yet"}
                    </p>
                </>
            )}
        </Block>
    );
}
