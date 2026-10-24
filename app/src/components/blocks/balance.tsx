"use client";

import { useState } from "react";
import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { ArrowDownRightIcon, ArrowUpRightIcon } from "@heroicons/react/16/solid";
import { useBitcoinAccount } from "@mezo-org/orangekit";
import { ConnectButton, useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { Bar, BarChart, Cell, YAxis } from "recharts";
import { useAccount } from "wagmi";
import { Button } from "@/components/ui/button";
import { ChartContainer } from "@/components/ui/chart";
import { useHistory, useVault, type Bar as HistoryBar } from "@/lib/hooks";
import { btcParts, formatBtc } from "@/lib/math";
import { Block, rise } from "../block";

const pop = { type: "spring", visualDuration: 0.3, bounce: 0.35 } as const;

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function Balance() {
    const { isConnected } = useAccount();
    return (
        <motion.div layout transition={rise} className="flex">
            <Block className="flex-1 items-center justify-center text-center">
                {isConnected ? <Connected /> : <Disconnected />}
            </Block>
        </motion.div>
    );
}

function Disconnected() {
    const { openConnectModal } = useConnectModal();
    return (
        <div className="flex flex-col items-center gap-8 py-10">
            <p className="max-w-[12ch] font-heading text-[40px] leading-[1.05] font-bold tracking-[-0.03em] text-balance">
                Deposit BTC, get more BTC.
            </p>
            <Button size="lg" className="h-12 px-6 text-base" onClick={openConnectModal}>
                Connect wallet
            </Button>
        </div>
    );
}

function Connected() {
    const { data } = useVault();
    const history = useHistory().data;
    const [pointed, setPointed] = useState<number | null>(null);
    const bar = pointed !== null ? history?.bars[pointed] : undefined;
    const shown = bar?.btc ?? data?.position;
    const earned = data && history && history.deposited > 0n ? data.position - history.deposited : null;

    return (
        <div className="flex w-full flex-1 flex-col items-center">
            <WalletPill />
            {shown === undefined ? (
                <div className="mt-8 h-14 w-56 animate-pulse rounded-full bg-secondary" />
            ) : (
                <BtcFigure wei={shown} />
            )}
            <div className="mt-3 flex h-8 items-center">
                <AnimatePresence mode="popLayout" initial={false}>
                    {bar ? (
                        <Chip key="when">{when.format(bar.time * 1000)}</Chip>
                    ) : earned !== null ? (
                        <Chip key="earned" tone={earned >= 0n ? "gain" : "flat"}>
                            {earned >= 0n ? (
                                <ArrowUpRightIcon className="size-4" />
                            ) : (
                                <ArrowDownRightIcon className="size-4" />
                            )}
                            {earned >= 0n ? "+" : ""}
                            {formatBtc(earned)} BTC
                        </Chip>
                    ) : null}
                </AnimatePresence>
            </div>
            <div className="mt-7 grid w-full grid-cols-2 gap-2">
                <Button asChild size="lg" className="h-12 text-base">
                    <Link href="/deposit">Deposit</Link>
                </Button>
                <Button asChild size="lg" variant="secondary" className="h-12 text-base">
                    <Link href="/withdraw">Withdraw</Link>
                </Button>
            </div>
            {history && history.bars.length > 1 && (
                <BalanceChart bars={history.bars} pointed={pointed} onPoint={setPointed} />
            )}
        </div>
    );
}

function WalletPill() {
    const { btcAddress } = useBitcoinAccount();
    return (
        <ConnectButton.Custom>
            {({ account, chain, openAccountModal, openChainModal }) =>
                chain?.unsupported ? (
                    <Button variant="secondary" onClick={openChainModal}>
                        Switch to Mezo
                    </Button>
                ) : (
                    <Button variant="secondary" onClick={openAccountModal} className="gap-2 px-4">
                        <span aria-hidden="true" className="size-2 rounded-full bg-gold" />
                        {btcAddress ? `${btcAddress.slice(0, 6)}…${btcAddress.slice(-4)}` : account?.displayName}
                    </Button>
                )
            }
        </ConnectButton.Custom>
    );
}

// Whole satoshis, the last four digits quieter so the first ones read at a glance
function BtcFigure({ wei }: { wei: bigint }) {
    const { head, tail } = btcParts(wei);
    return (
        <p className="mt-8 font-heading text-[clamp(34px,1rem+3vw,48px)] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums">
            <NumberFlow value={Number(head)} format={{ minimumFractionDigits: 4, maximumFractionDigits: 4 }} />
            <NumberFlow
                value={Number(tail)}
                format={{ minimumIntegerDigits: 4, useGrouping: false }}
                className="text-muted-foreground/50"
            />
            <span className="ml-2 text-[0.42em] tracking-normal text-muted-foreground">BTC</span>
        </p>
    );
}

function Chip({ children, tone = "flat" }: { children: React.ReactNode; tone?: "gain" | "flat" }) {
    return (
        <motion.span
            className={`inline-flex h-8 items-center gap-1 rounded-full px-3 text-[15px] font-medium tabular-nums ${
                tone === "gain" ? "bg-second text-foreground" : "bg-secondary text-muted-foreground"
            }`}
            initial={{ opacity: 0, scale: 0.85 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.9 }}
            transition={pop}
        >
            {children}
        </motion.span>
    );
}

// Your BTC at evenly spaced blocks since your first deposit, pointing at a bar rolls the figure to it
function BalanceChart({
    bars,
    pointed,
    onPoint,
}: {
    bars: HistoryBar[];
    pointed: number | null;
    onPoint: (index: number | null) => void;
}) {
    const data = bars.map((b) => ({ btc: Number(b.btc) / 1e18 }));
    const active = pointed ?? bars.length - 1;

    return (
        <ChartContainer
            config={{ btc: { label: "BTC", color: "var(--gold)" } }}
            className="mt-auto aspect-auto h-[clamp(140px,22vh,200px)] w-full pt-8"
            aria-hidden="true"
        >
            <BarChart
                data={data}
                margin={{ top: 0, right: 0, bottom: 0, left: 0 }}
                barCategoryGap="22%"
                onMouseMove={(state) => {
                    const index = Number(state.activeTooltipIndex);
                    onPoint(Number.isInteger(index) ? index : null);
                }}
                onMouseLeave={() => onPoint(null)}
            >
                <YAxis hide domain={[0, "dataMax"]} />
                <Bar dataKey="btc" radius={4} minPointSize={4} isAnimationActive>
                    {data.map((_, i) => (
                        <Cell key={i} fill={i === active ? "var(--gold)" : "var(--second)"} />
                    ))}
                </Bar>
            </BarChart>
        </ChartContainer>
    );
}
