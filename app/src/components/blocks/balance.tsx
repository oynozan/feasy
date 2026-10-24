"use client";

import { useState } from "react";
import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { ArrowDownRightIcon, ArrowUpRightIcon } from "@heroicons/react/16/solid";
import { useBitcoinAccount } from "@mezo-org/orangekit";
import { ConnectButton, useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useHistory, useSignedOut, useVault, type Bar } from "@/lib/hooks";
import { btcParts, formatBtc } from "@/lib/math";
import { flow, grow, rise } from "@/lib/motion";
import { Block, BlockHeader, Chip, ChipRow, Eyebrow, FigureRow, Press, Reveal } from "../block";
import { Wordmark } from "../frame";
import { Magnet } from "../magnet";

const BARS = 32;

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function Balance() {
    const signedOut = useSignedOut();

    return (
        <Block data-balance="">
            <BlockHeader>
                <Wordmark />
                {!signedOut && <WalletPill />}
            </BlockHeader>
            <AnimatePresence mode="popLayout" initial={false}>
                <motion.div
                    key={signedOut ? "out" : "in"}
                    className="flex flex-1 flex-col"
                    initial={{ opacity: 0, y: 16 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8, transition: { duration: 0.12 } }}
                    transition={rise}
                >
                    {signedOut ? <SignedOut /> : <SignedIn />}
                </motion.div>
            </AnimatePresence>
        </Block>
    );
}

function SignedOut() {
    const { openConnectModal } = useConnectModal();
    return (
        <>
            <p className="mt-8 font-heading text-[44px] leading-[1.05] font-bold tracking-[-0.03em] text-balance">
                Earn BTC on your BTC.
            </p>
            <Press className="mt-auto pt-6">
                <Button size="lg" className="h-12 text-base" onClick={openConnectModal}>
                    Connect wallet
                </Button>
            </Press>
        </>
    );
}

function SignedIn() {
    const { data } = useVault();
    const history = useHistory().data;
    const [pointed, setPointed] = useState<number | null>(null);
    const bar = pointed !== null ? history?.bars[pointed] : undefined;
    const shown = bar?.btc ?? data?.position;
    // Both sides come from the same history read, so a fresh deposit never shows up as a gain
    const last = history?.bars.at(-1);
    const earned = history && last && history.deposited > 0n ? last.btc - history.deposited : null;

    return (
        <>
            <Eyebrow>{bar ? when.format(bar.time * 1000) : "Your BTC"}</Eyebrow>
            <FigureRow>
                <Reveal ready={shown !== undefined} placeholder={<Skeleton className="h-10 w-60" />}>
                    <BtcFigure wei={shown ?? 0n} />
                </Reveal>
            </FigureRow>
            <ChipRow>
                <AnimatePresence mode="popLayout" initial={false}>
                    {earned !== null && !bar && (
                        <Chip key="earned" tone={earned >= 0n ? "gain" : "flat"}>
                            {earned >= 0n ? (
                                <ArrowUpRightIcon className="size-4" />
                            ) : (
                                <ArrowDownRightIcon className="size-4" />
                            )}
                            {earned >= 0n ? "+" : ""}
                            {formatBtc(earned)} BTC
                        </Chip>
                    )}
                </AnimatePresence>
            </ChipRow>
            <Bars bars={history?.bars} pointed={pointed} onPoint={setPointed} />
            <div className="mt-6 grid grid-cols-2 gap-2">
                <Press>
                    <Button asChild size="lg" className="h-12 text-base">
                        <Link href="/deposit">Deposit</Link>
                    </Button>
                </Press>
                <Press>
                    <Button asChild size="lg" variant="secondary" className="h-12 text-base">
                        <Link href="/withdraw">Withdraw</Link>
                    </Button>
                </Press>
            </div>
        </>
    );
}

function WalletPill() {
    const { btcAddress } = useBitcoinAccount();
    return (
        <ConnectButton.Custom>
            {({ account, chain, mounted, openAccountModal, openChainModal }) =>
                !mounted || !account ? (
                    <Skeleton className="h-9 w-32" />
                ) : (
                    <Magnet padding={24} magnetStrength={4}>
                        <Press>
                            {chain?.unsupported ? (
                                <Button variant="secondary" onClick={openChainModal}>
                                    Switch to Mezo
                                </Button>
                            ) : (
                                <Button variant="secondary" onClick={openAccountModal} className="gap-2 px-4">
                                    <span aria-hidden="true" className="size-2 rounded-full bg-gold" />
                                    {btcAddress
                                        ? `${btcAddress.slice(0, 6)}…${btcAddress.slice(-4)}`
                                        : account.displayName}
                                </Button>
                            )}
                        </Press>
                    </Magnet>
                )
            }
        </ConnectButton.Custom>
    );
}

// Whole satoshis, the last four digits quieter so the first ones read at a glance
function BtcFigure({ wei }: { wei: bigint }) {
    const { head, tail } = btcParts(wei);
    return (
        <p className="font-heading text-[44px] leading-none font-bold tracking-[-0.03em] whitespace-nowrap tabular-nums">
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
            <span className="ml-2 text-[18px] tracking-normal text-muted-foreground">BTC</span>
        </p>
    );
}

// Your BTC at evenly spaced blocks since your first deposit, pointing at a bar rolls the figure to it
function Bars({
    bars,
    pointed,
    onPoint,
}: {
    bars: Bar[] | undefined;
    pointed: number | null;
    onPoint: (index: number | null) => void;
}) {
    const values = bars && bars.length > 1 ? bars.map((b) => Number(b.btc)) : null;
    const high = values ? Math.max(...values) : 0;
    const active = values ? (pointed ?? values.length - 1) : null;

    const point = (event: React.PointerEvent<HTMLDivElement>) => {
        if (!values) return;
        const rect = event.currentTarget.getBoundingClientRect();
        const index = Math.floor(((event.clientX - rect.left) / rect.width) * values.length);
        onPoint(Math.min(values.length - 1, Math.max(0, index)));
    };

    return (
        <div
            aria-hidden="true"
            className="mt-6 flex min-h-24 flex-1 touch-pan-y items-end gap-[3px]"
            onPointerMove={point}
            onPointerDown={point}
            onPointerLeave={() => onPoint(null)}
        >
            {(values ?? Array.from({ length: BARS }, () => 0)).map((value, i) => (
                <span key={`${values ? "on" : "off"}-${i}`} className="flex h-full min-w-0 flex-1 items-end">
                    <motion.span
                        className={`w-full rounded-full transition-colors duration-150 ${
                            !values ? "bg-secondary" : i === active ? "bg-gold" : "bg-second/70"
                        }`}
                        initial={{ height: "0%" }}
                        animate={{ height: `${high > 0 ? Math.max(4, (value / high) * 100) : 4}%` }}
                        transition={{ ...grow, delay: Math.min(i, 40) * 0.012 }}
                    />
                </span>
            ))}
        </div>
    );
}
