"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { ArrowPathIcon, ArrowTopRightOnSquareIcon, CheckIcon, XMarkIcon } from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Button } from "@/components/ui/button";
import { BRIDGE_MINUTES, useBridge, useTbtc, type BridgeState } from "@/lib/bridge";
import { EXPLORER } from "@/lib/chain";
import { useVault, useVaultTx, useWalletBtc, type TxState } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { pop, rise, springy } from "@/lib/motion";
import { cn } from "@/lib/utils";
import { Block, BlockHeader, BlockLabel, CloseButton, Eyebrow, FigureRow, InfoTip, Press } from "../block";

// Enough gas for this deposit and a later withdrawal, a Bitcoin wallet's smart account pays both refunds from here
const GAS_RESERVE = 3_000_000n;
const SEPOLIA_EXPLORER = "https://sepolia.etherscan.io";

type Source = "btc" | "tbtc";
type Connect = { label: string; run: () => void } | undefined;

export function Deposit() {
    const { address, isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const wallet = useWalletBtc();
    const gasPrice = useGasPrice().data;
    const { data } = useVault();
    const tx = useVaultTx();
    const tbtc = useTbtc();
    const bridge = useBridge(address);
    const [source, setSource] = useState<Source>("btc");
    const [prefill, setPrefill] = useState("");

    const reserve = GAS_RESERVE * (gasPrice ?? 0n);
    const fromWallet = wallet === undefined ? undefined : wallet > reserve ? wallet - reserve : 0n;
    const max = fromWallet !== undefined && data ? min(fromWallet, data.maxDeposit) : undefined;
    const blocked = data?.maxDeposit === 0n ? (data.stale ? "Prices are updating" : "Deposits are paused") : undefined;
    const status = bridge.state.status;
    const bridging = status === "approve" || status === "bridge" || status === "locking" || status === "arriving";
    const connectMezo: Connect = isConnected ? undefined : { label: "Connect wallet", run: () => openConnectModal?.() };

    // A bridge picked up again after a reload brings its progress back into view
    useEffect(() => {
        if (status === "arriving") setSource("tbtc");
    }, [status]);

    // Bridged BTC lands in the wallet, so the form flips back to BTC with it filled in for one tap
    useEffect(() => {
        if (bridge.state.status !== "arrived") return;
        setPrefill(formatBtc(bridge.state.amount - min(bridge.state.amount, reserve)));
        setSource("btc");
        bridge.reset();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [status]);

    const title = <SourceToggle value={source} onChange={setSource} bridging={bridging} />;

    if (source === "tbtc") {
        return (
            <>
                <BridgeSteps state={bridge.state} />
                <AmountForm
                    key="tbtc"
                    title={title}
                    source="On Ethereum"
                    unit="tBTC"
                    verb="Bridge to Mezo"
                    busy="Bridging"
                    over="Not enough tBTC"
                    max={tbtc.balance}
                    least={tbtc.min}
                    blocked={tbtc.available ? undefined : "No Ethereum wallet found"}
                    connect={
                        connectMezo ??
                        (tbtc.available && !tbtc.account
                            ? { label: "Connect Ethereum wallet", run: tbtc.connect }
                            : undefined)
                    }
                    tx={asTx(bridge.state)}
                    onEdit={bridge.reset}
                    onSubmit={bridge.send}
                />
            </>
        );
    }

    return (
        <>
            <TxSteps tx={tx.state} done="Deposited" />
            <AmountForm
                key="btc"
                title={title}
                source="Wallet"
                unit="BTC"
                verb="Deposit"
                busy="Depositing"
                over="Not enough BTC"
                max={max}
                blocked={blocked}
                connect={connectMezo}
                initial={prefill}
                tx={tx.state}
                onEdit={tx.reset}
                onSubmit={(amount) => tx.send({ functionName: "depositBTC", args: [address!], value: amount })}
            />
        </>
    );
}

export function Withdraw() {
    const { address, isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const { data } = useVault();
    const tx = useVaultTx();

    const blocked = !data
        ? undefined
        : data.shares === 0n
          ? "Nothing to withdraw"
          : data.maxWithdraw === 0n && data.stale
            ? "Prices are updating"
            : undefined;

    return (
        <>
            <TxSteps tx={tx.state} done="Withdrawn" />
            <AmountForm
                title={<BlockLabel>Withdraw BTC</BlockLabel>}
                source="Available"
                unit="BTC"
                verb="Withdraw"
                busy="Withdrawing"
                over="More than you can withdraw"
                max={data?.maxWithdraw}
                blocked={blocked}
                connect={isConnected ? undefined : { label: "Connect wallet", run: () => openConnectModal?.() }}
                tx={tx.state}
                onEdit={tx.reset}
                onSubmit={(amount) => {
                    // The oracle moves between reading the max and sending, so a full exit asks a hair under it
                    if (data && amount * 100_000n >= data.maxWithdraw * 99_999n) {
                        const shares = data.maxRedeem - data.maxRedeem / 100_000n;
                        return tx.send({ functionName: "redeem", args: [shares, address!, address!] });
                    }
                    return tx.send({ functionName: "withdraw", args: [amount, address!, address!] });
                }}
            />
        </>
    );
}

// Which BTC the deposit starts from, tBTC crosses over from Ethereum first
function SourceToggle({
    value,
    onChange,
    bridging,
}: {
    value: Source;
    onChange: (next: Source) => void;
    bridging: boolean;
}) {
    return (
        <div className="flex items-center gap-2">
            <h2 className="text-[15px] leading-6 font-medium text-muted-foreground">Deposit</h2>
            <div role="radiogroup" aria-label="Deposit from" className="flex rounded-full bg-secondary p-1">
                {(["btc", "tbtc"] as const).map((option) => (
                    <button
                        key={option}
                        type="button"
                        role="radio"
                        aria-checked={value === option}
                        onClick={() => onChange(option)}
                        className={cn(
                            "relative flex h-7 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-medium transition-colors",
                            value === option ? "text-foreground" : "text-muted-foreground hover:text-foreground",
                        )}
                    >
                        {value === option && (
                            <motion.span
                                layoutId="deposit-source"
                                className="absolute inset-0 rounded-full bg-card"
                                transition={springy}
                            />
                        )}
                        <span className="relative">{option === "btc" ? "BTC" : "tBTC"}</span>
                        {option === "tbtc" && bridging && (
                            <span aria-hidden="true" className="relative size-1.5 animate-pulse rounded-full bg-gold" />
                        )}
                    </button>
                ))}
            </div>
            <InfoTip>
                tBTC is Bitcoin on Ethereum. Send it from any Ethereum wallet and it lands here as BTC in about{" "}
                {BRIDGE_MINUTES} minutes, with no bridge fee. Holding WBTC or cbBTC? Swap it to tBTC on Ethereum first.
                Wrapped BTC already on Mezo can’t be deposited.
            </InfoTip>
        </div>
    );
}

type AmountFormProps = {
    title: ReactNode;
    source: string;
    unit: string;
    verb: string;
    busy: string;
    over: string;
    max: bigint | undefined;
    least?: bigint;
    blocked: string | undefined;
    connect: Connect;
    initial?: string;
    tx: TxState;
    onEdit: () => void;
    onSubmit: (amount: bigint) => Promise<boolean>;
};

function AmountForm({
    title,
    source,
    unit,
    verb,
    busy,
    over,
    max,
    least,
    blocked,
    connect,
    initial,
    tx,
    onEdit,
    onSubmit,
}: AmountFormProps) {
    const [text, setText] = useState(initial ?? "");
    const input = useRef<HTMLInputElement>(null);
    const [hovered, setHovered] = useState(false);
    const [focused, setFocused] = useState(false);
    const amount = parseAmount(text);
    const working = tx.status === "wallet" || tx.status === "pending";
    const tooMuch = !!amount && max !== undefined && amount > max;
    const tooLittle = !!amount && least !== undefined && amount < least;
    const ready = !connect && !working && !blocked && !!amount && max !== undefined && !tooMuch && !tooLittle;

    const label = connect
        ? connect.label
        : tx.status === "wallet"
          ? "Confirm in your wallet"
          : tx.status === "pending"
            ? `${busy}…`
            : (blocked ??
              (tooLittle && least !== undefined
                  ? `At least ${formatUnits(least, 18)} ${unit}`
                  : tooMuch
                    ? over
                    : verb));

    const edit = (next: string) => {
        setText(next);
        if (tx.status !== "wallet" && tx.status !== "pending") onEdit();
    };

    return (
        <Block>
            <form
                className="flex flex-1 flex-col"
                onSubmit={async (event) => {
                    event.preventDefault();
                    if (connect) return connect.run();
                    if (ready && amount && (await onSubmit(amount))) setText("");
                }}
            >
                <BlockHeader>
                    {title}
                    <CloseButton />
                </BlockHeader>
                {/* The whole pane focuses the amount, so a click anywhere in it starts typing */}
                <div
                    className="-mx-3 mt-4 cursor-text rounded-tile bg-secondary px-3 py-3"
                    onClick={(event) => {
                        if (!(event.target as HTMLElement).closest("button")) input.current?.focus();
                    }}
                    onPointerEnter={() => setHovered(true)}
                    onPointerLeave={() => setHovered(false)}
                    onFocus={() => setFocused(true)}
                    onBlur={(event) => {
                        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setFocused(false);
                    }}
                >
                    <FigureRow className="mt-0">
                        <span className="flex min-w-0 items-baseline">
                            <input
                                ref={input}
                                aria-label={`Amount in ${unit}`}
                                inputMode="decimal"
                                autoComplete="off"
                                placeholder="0"
                                value={text}
                                disabled={working}
                                onChange={(event) => edit(cleanAmount(event.target.value))}
                                className="max-w-full min-w-[1ch] bg-transparent font-heading text-[44px] leading-none font-bold tracking-[-0.03em] outline-none [field-sizing:content] placeholder:text-muted-foreground/40"
                            />
                            <span className="ml-2 text-[18px] text-muted-foreground">{unit}</span>
                        </span>
                    </FigureRow>
                    <AnimatePresence initial={false}>
                        {(hovered || focused) && (
                            <motion.div
                                key="available"
                                className="overflow-hidden"
                                initial={{ height: 0, opacity: 0 }}
                                animate={{ height: "auto", opacity: 1 }}
                                exit={{ height: 0, opacity: 0 }}
                                transition={rise}
                            >
                                <Eyebrow className="mt-2">
                                    <span>{source}</span>
                                    <span className="text-foreground tabular-nums">
                                        {max === undefined || connect ? "–" : `${formatBtc(max)} ${unit}`}
                                    </span>
                                    {!connect && !!max && (
                                        <Press className="ml-auto">
                                            <button
                                                type="button"
                                                disabled={working}
                                                onClick={() => edit(formatBtc(max))}
                                                className="h-6 rounded-full bg-card px-2.5 text-[13px] font-medium text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
                                            >
                                                Max
                                            </button>
                                        </Press>
                                    )}
                                </Eyebrow>
                            </motion.div>
                        )}
                    </AnimatePresence>
                </div>
                <Press className="mt-auto" disabled={!connect && !ready}>
                    <Button
                        type="submit"
                        size="lg"
                        className="h-12 overflow-hidden text-base"
                        disabled={!connect && !ready}
                    >
                        <AnimatePresence mode="popLayout" initial={false}>
                            <motion.span
                                key={label}
                                initial={{ opacity: 0, y: 14 }}
                                animate={{ opacity: 1, y: 0 }}
                                exit={{ opacity: 0, y: -14 }}
                                transition={pop}
                            >
                                {label}
                            </motion.span>
                        </AnimatePresence>
                    </Button>
                </Press>
            </form>
        </Block>
    );
}

function TxSteps({ tx, done }: { tx: TxState; done: string }) {
    const hash = tx.status === "pending" || tx.status === "done" || tx.status === "error" ? tx.hash : undefined;
    return (
        <Steps
            labels={["Amount", "Sign", "Confirm", done]}
            at={{ idle: 0, wallet: 1, pending: 2, done: 4, error: hash ? 2 : 1 }[tx.status]}
            failed={tx.status === "error"}
            spinning={tx.status === "wallet" || tx.status === "pending"}
            link={hash && { at: 2, href: `${EXPLORER}/tx/${hash}` }}
            message={tx.status === "error" ? tx.message : undefined}
        />
    );
}

function BridgeSteps({ state }: { state: BridgeState }) {
    const hash = "hash" in state ? state.hash : undefined;
    const left = useMinutesLeft(state.status === "arriving" ? state.lockedAt : undefined);
    return (
        <Steps
            labels={["Amount", "Approve", "Bridge", "Arrive"]}
            at={
                { idle: 0, approve: 1, bridge: 2, locking: 2, arriving: 3, arrived: 4, error: hash ? 2 : 1 }[
                    state.status
                ]
            }
            failed={state.status === "error"}
            spinning={state.status !== "idle" && state.status !== "arrived" && state.status !== "error"}
            link={hash && { at: 2, href: `${SEPOLIA_EXPLORER}/tx/${hash}` }}
            note={left === undefined ? undefined : { at: 3, text: left > 0 ? `~${left} min` : "Any minute" }}
            message={state.status === "error" ? state.message : undefined}
        />
    );
}

// Minutes until a lock usually mints on Mezo, never counting from before the lock itself
function useMinutesLeft(lockedAt: number | undefined) {
    const [now, setNow] = useState(() => Date.now());
    useEffect(() => {
        if (lockedAt === undefined) return;
        const id = setInterval(() => setNow(Date.now()), 15_000);
        return () => clearInterval(id);
    }, [lockedAt]);
    if (lockedAt === undefined) return undefined;
    return Math.ceil((lockedAt + BRIDGE_MINUTES * 60 - Math.max(now / 1000, lockedAt)) / 60);
}

type StepsProps = {
    labels: string[];
    at: number;
    failed: boolean;
    spinning: boolean;
    link?: { at: number; href: string };
    note?: { at: number; text: string };
    message?: string;
};

// Where a transfer is, each step's label sits under its dot on one shared track
function Steps({ labels, at, failed, spinning, link, note, message }: StepsProps) {
    const last = labels.length - 1;
    return (
        <Block className="shrink-0 justify-center lg:h-[136px]">
            <motion.ol
                layout
                transition={rise}
                className="relative grid"
                style={{ gridTemplateColumns: `repeat(${labels.length}, minmax(0, 1fr))` }}
            >
                <li
                    aria-hidden="true"
                    className="absolute top-[15px] h-0.5 overflow-hidden rounded-full bg-secondary"
                    style={{ insetInline: `${50 / labels.length}%` }}
                >
                    <motion.span
                        className="block h-full origin-left bg-gold"
                        initial={false}
                        animate={{ scaleX: Math.min(at, last) / last }}
                        transition={rise}
                    />
                </li>
                {labels.map((label, i) => {
                    const state = failed && i === at ? "failed" : i < at ? "done" : i === at ? "current" : "next";
                    const text = cn(
                        "text-[13px] leading-4 font-medium transition-colors",
                        state === "next" && "text-muted-foreground",
                        state === "failed" && "text-danger",
                    );
                    return (
                        <li
                            key={label}
                            aria-current={state === "current" ? "step" : undefined}
                            className="relative flex flex-col items-center gap-2"
                        >
                            <StepDot state={state} n={i + 1} spinning={spinning} />
                            {link?.at === i ? (
                                <a href={link.href} target="_blank" rel="noreferrer" aria-label="View transaction">
                                    <span className={cn(text, "inline-flex items-center gap-1 hover:underline")}>
                                        {label}
                                        <ArrowTopRightOnSquareIcon className="size-3" />
                                    </span>
                                </a>
                            ) : (
                                <span className={text}>{label}</span>
                            )}
                            <AnimatePresence initial={false}>
                                {note?.at === i && (
                                    <motion.span
                                        key="note"
                                        className="-mt-1.5 text-[13px] leading-4 text-muted-foreground tabular-nums"
                                        initial={{ opacity: 0, y: -4 }}
                                        animate={{ opacity: 1, y: 0 }}
                                        exit={{ opacity: 0 }}
                                        transition={pop}
                                    >
                                        {note.text}
                                    </motion.span>
                                )}
                            </AnimatePresence>
                        </li>
                    );
                })}
            </motion.ol>
            <AnimatePresence initial={false}>
                {failed && (
                    <motion.p
                        key="error"
                        className="mt-3 truncate text-center text-[13px] leading-5 font-medium text-danger"
                        initial={{ opacity: 0, y: 6 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0, y: 6 }}
                        transition={pop}
                    >
                        {message}
                    </motion.p>
                )}
            </AnimatePresence>
        </Block>
    );
}

function StepDot({
    state,
    n,
    spinning,
}: {
    state: "done" | "current" | "next" | "failed";
    n: number;
    spinning: boolean;
}) {
    const icon =
        state === "done" ? (
            <CheckIcon className="size-4" />
        ) : state === "failed" ? (
            <XMarkIcon className="size-4" />
        ) : state === "current" && spinning ? (
            <ArrowPathIcon className="size-4 animate-spin" />
        ) : (
            n
        );
    return (
        <motion.span
            className={cn(
                "relative grid size-8 place-items-center overflow-hidden rounded-full text-[13px] font-semibold tabular-nums ring-4 ring-card transition-colors duration-300",
                state === "done" && "bg-gold text-foreground",
                state === "current" && "bg-highlight text-foreground",
                state === "next" && "bg-secondary text-muted-foreground",
                state === "failed" && "bg-danger text-white",
            )}
            animate={{ scale: state === "current" ? 1.1 : 1 }}
            transition={springy}
        >
            <AnimatePresence mode="popLayout" initial={false}>
                <motion.span
                    key={`${state}-${spinning}`}
                    className="grid place-items-center"
                    initial={{ opacity: 0, scale: 0.4 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.4 }}
                    transition={pop}
                >
                    {icon}
                </motion.span>
            </AnimatePresence>
        </motion.span>
    );
}

// The form only needs to know whether the wallet or the network is busy with the bridge
function asTx(state: BridgeState): TxState {
    if (state.status === "approve" || state.status === "bridge") return { status: "wallet" };
    if (state.status === "locking" || state.status === "arriving") return { status: "pending", hash: state.hash };
    if (state.status === "error") return state;
    return { status: "idle" };
}

// Digits and one decimal point, at most eight decimals since BTC stops at satoshis
function cleanAmount(text: string) {
    const [whole = "", ...rest] = text
        .replace(/,/g, ".")
        .replace(/[^\d.]/g, "")
        .split(".");
    return rest.length ? `${whole}.${rest.join("").slice(0, 8)}` : whole;
}

function parseAmount(text: string) {
    if (!text || text === ".") return undefined;
    const amount = parseUnits(text.startsWith(".") ? `0${text}` : text, 18);
    return amount > 0n ? amount : undefined;
}

function min(a: bigint, b: bigint) {
    return a < b ? a : b;
}
