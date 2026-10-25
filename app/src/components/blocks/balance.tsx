"use client";

import { useState } from "react";
import Link from "next/link";
import NumberFlow from "@number-flow/react";
import { ArrowDownRightIcon, ArrowsRightLeftIcon, ArrowUpRightIcon, PlusIcon } from "@heroicons/react/16/solid";
import { useBitcoinAccount } from "@mezo-org/orangekit";
import { ConnectButton, useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { useAccount, useConnect, useConnections, useConnectors, useSwitchAccount } from "wagmi";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { isBitcoinWallet, useHistory, useHoldings, useSignedOut, type Bar } from "@/lib/hooks";
import { btcParts, formatBtc } from "@/lib/math";
import { flow, grow, pop, rise, springy } from "@/lib/motion";
import { Block, BlockHeader, Chip, Eyebrow, FigureRow, Press, Reveal } from "../block";
import { Wordmark } from "../frame";
import { Magnet } from "../magnet";

const BARS = 32;

const when = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export function Balance() {
    const signedOut = useSignedOut();
    const [hovered, setHovered] = useState(false);
    const [focused, setFocused] = useState(false);

    return (
        <Block
            data-balance=""
            onPointerEnter={() => setHovered(true)}
            onPointerLeave={() => setHovered(false)}
            onFocus={(event) => setFocused(event.target.matches(":focus-visible"))}
            onBlur={(event) => {
                if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setFocused(false);
            }}
        >
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
                    {signedOut ? <SignedOut /> : <SignedIn open={hovered || focused} />}
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

function SignedIn({ open }: { open: boolean }) {
    const holdings = useHoldings();
    const history = useHistory().data;
    const [pointed, setPointed] = useState<number | null>(null);
    const bar = pointed !== null ? history?.bars[pointed] : undefined;
    const pool = bar?.pool ?? holdings?.pool;
    const inWallet = bar?.wallet ?? holdings?.wallet;
    const ready = pool !== undefined && inWallet !== undefined;
    // Both sides come from the same history read, so a fresh deposit never shows up as a gain
    const last = history?.bars.at(-1);
    const earned = history && last && history.deposited > 0n ? last.pool - history.deposited : null;

    return (
        <>
            <Eyebrow>
                {bar ? when.format(bar.time * 1000) : "Your BTC"}
                <AnimatePresence mode="popLayout" initial={false}>
                    {earned !== null && !bar && (
                        <Chip
                            key="earned"
                            tone={earned >= 0n ? "gain" : "flat"}
                            className="ml-auto h-6 gap-1 px-2.5 text-[13px]"
                        >
                            {earned >= 0n ? (
                                <ArrowUpRightIcon className="size-3.5" />
                            ) : (
                                <ArrowDownRightIcon className="size-3.5" />
                            )}
                            {earned >= 0n ? "+" : ""}
                            {formatBtc(earned)}
                        </Chip>
                    )}
                </AnimatePresence>
            </Eyebrow>
            <FigureRow>
                <Reveal ready={ready} placeholder={<Skeleton className="h-10 w-60" />}>
                    <BtcFigure wei={(pool ?? 0n) + (inWallet ?? 0n)} />
                </Reveal>
            </FigureRow>
            {/* The split under the total opens while the block is hovered or focused */}
            <AnimatePresence initial={false}>
                {open && (
                    <motion.div
                        key="parts"
                        className="overflow-hidden"
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: "auto", opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        transition={rise}
                    >
                        <dl
                            data-row="chip"
                            className="mt-3 grid grid-cols-[auto_1fr] items-baseline gap-x-3 text-[15px] leading-7 text-muted-foreground"
                        >
                            <Part label="Wallet" wei={inWallet} />
                            <Part label="Pool" wei={pool} />
                        </dl>
                    </motion.div>
                )}
            </AnimatePresence>
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

// One side of the total, quieter and smaller than it
function Part({ label, wei }: { label: string; wei: bigint | undefined }) {
    return (
        <>
            <dt>{label}</dt>
            <dd className="text-[22px] font-medium tracking-[-0.01em] tabular-nums">
                {wei === undefined ? (
                    "–"
                ) : (
                    <NumberFlow
                        {...flow}
                        value={Number(wei) / 1e18}
                        format={{ minimumFractionDigits: 8, maximumFractionDigits: 8 }}
                    />
                )}
                <span className="ml-1.5 text-[15px] font-normal tracking-normal">BTC</span>
            </dd>
        </>
    );
}

function WalletPill() {
    const { btcAddress } = useBitcoinAccount();
    return (
        <div className="flex items-center gap-1.5">
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
            <WalletSwitch />
        </div>
    );
}

// Adds a wallet from the other family, or swaps which connected wallet signs
function WalletSwitch() {
    const { connector } = useAccount();
    const connections = useConnections();
    const connectors = useConnectors();
    const { connect } = useConnect();
    const { switchAccount } = useSwitchAccount();
    const [open, setOpen] = useState(false);
    const other = connections.find((c) => c.connector.uid !== connector?.uid);
    const bitcoin = isBitcoinWallet(connector);
    const options = [
        ...new Map(
            connectors
                .filter((c) => isBitcoinWallet(c) !== bitcoin && !connections.some((k) => k.connector.uid === c.uid))
                .map((c) => [c.name, c]),
        ).values(),
    ];
    const round =
        "grid size-9 place-items-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground";

    if (other) {
        const to = other.accounts[0];
        return (
            <Press>
                <button
                    type="button"
                    aria-label={`Switch to ${to.slice(0, 6)}…${to.slice(-4)}`}
                    title={`Switch to ${to.slice(0, 6)}…${to.slice(-4)}`}
                    onClick={() => switchAccount({ connector: other.connector })}
                    className={round}
                >
                    <ArrowsRightLeftIcon className="size-4" />
                </button>
            </Press>
        );
    }
    if (options.length === 0) return null;
    return (
        <div className="relative">
            <Press>
                <button
                    type="button"
                    aria-label="Add a wallet"
                    aria-expanded={open}
                    onClick={() => setOpen((was) => !was)}
                    className={round}
                >
                    <motion.span animate={{ rotate: open ? 45 : 0 }} transition={springy}>
                        <PlusIcon className="size-4" />
                    </motion.span>
                </button>
            </Press>
            <AnimatePresence>
                {open && (
                    <>
                        <button
                            type="button"
                            aria-hidden="true"
                            tabIndex={-1}
                            className="fixed inset-0 z-40 cursor-default"
                            onClick={() => setOpen(false)}
                        />
                        <motion.ul
                            key="wallets"
                            className="absolute top-11 right-0 z-50 w-52 origin-top-right rounded-tile bg-card p-1.5 shadow-[0_16px_40px_-16px_rgb(24_23_23/0.35)] ring-1 ring-foreground/5"
                            initial={{ opacity: 0, scale: 0.9, y: -6 }}
                            animate={{ opacity: 1, scale: 1, y: 0 }}
                            exit={{ opacity: 0, scale: 0.95, y: -4, transition: { duration: 0.12 } }}
                            transition={pop}
                        >
                            {options.map((option) => (
                                <li key={option.uid}>
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setOpen(false);
                                            connect({ connector: option });
                                        }}
                                        className="flex h-10 w-full items-center rounded-[14px] px-3 text-left text-[15px] font-medium transition-colors hover:bg-secondary"
                                    >
                                        {option.name}
                                    </button>
                                </li>
                            ))}
                        </motion.ul>
                    </>
                )}
            </AnimatePresence>
        </div>
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
    const values = bars && bars.length > 1 ? bars.map((b) => Number(b.pool + b.wallet)) : null;
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
