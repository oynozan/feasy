"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import {
    ArrowPathIcon,
    ArrowRightIcon,
    ArrowTopRightOnSquareIcon,
    CheckIcon,
    ChevronDownIcon,
    XMarkIcon,
} from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Button } from "@/components/ui/button";
import {
    BRIDGE_MINUTES,
    ETHEREUM_EXPLORER,
    SWAPS,
    useBridge,
    useEthereumBtc,
    useSwapQuote,
    type BridgeState,
} from "@/lib/bridge";
import { EXPLORER } from "@/lib/chain";
import { useQueue, useVault, useVaultTx, useWalletBtc, type TxState } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { pop, rise, springy } from "@/lib/motion";
import type { Source as Token } from "@/lib/swap";
import { cn } from "@/lib/utils";
import { Block, BlockHeader, BlockLabel, CloseButton, Eyebrow, FigureRow, InfoTip, Press } from "../block";

// Enough gas for this deposit and a later withdrawal, a Bitcoin wallet's smart account pays both refunds from here
const GAS_RESERVE = 3_000_000n;

type Source = "btc" | "tbtc";
type Connect = { label: string; run: () => void } | undefined;

export function Deposit() {
    const { address, isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const wallet = useWalletBtc();
    const gasPrice = useGasPrice().data;
    const { data } = useVault();
    const tx = useVaultTx();
    const [token, setToken] = useState<Token>("tBTC");
    const ethereum = useEthereumBtc(token);
    const bridge = useBridge(address);
    const [source, setSource] = useState<Source>("btc");
    const [prefill, setPrefill] = useState("");

    const reserve = GAS_RESERVE * (gasPrice ?? 0n);
    const fromWallet = wallet === undefined ? undefined : wallet > reserve ? wallet - reserve : 0n;
    const max = fromWallet !== undefined && data ? min(fromWallet, data.maxDeposit) : undefined;
    const blocked = data?.maxDeposit === 0n ? (data.stale ? "Prices are updating" : "Deposits are paused") : undefined;
    const status = bridge.state.status;
    const bridging = status !== "idle" && status !== "arrived" && status !== "error";
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

    const backlog = !!useQueue()?.backlog;
    const title = <SourceToggle value={source} onChange={setSource} bridging={bridging} backlog={backlog} />;

    if (source === "tbtc") {
        return (
            <>
                <BridgeSteps state={bridge.state} swap={token !== "tBTC"} />
                <AmountForm
                    key="tbtc"
                    title={title}
                    source="On Ethereum"
                    unit={token}
                    picker={SWAPS && <TokenPicker value={token} onChange={setToken} disabled={bridging} />}
                    extra={(amount) => token !== "tBTC" && <SwapQuote token={token} amount={amount} />}
                    verb={token === "tBTC" ? "Bridge to Mezo" : "Swap and bridge"}
                    busy={status === "swap" || status === "swapping" ? "Swapping" : "Bridging"}
                    over={`Not enough ${token}`}
                    max={ethereum.balance}
                    least={ethereum.min}
                    blocked={ethereum.available ? undefined : "No Ethereum wallet found"}
                    connect={
                        connectMezo ??
                        (ethereum.available && !ethereum.account
                            ? { label: "Connect Ethereum wallet", run: ethereum.connect }
                            : undefined)
                    }
                    tx={asTx(bridge.state)}
                    onEdit={bridge.reset}
                    onSubmit={(amount) => bridge.send(amount, token)}
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
    const queue = useQueue();
    const [kind, setKind] = useState<"withdraw" | "request">("withdraw");

    // Only v6 unlocks earnings over a week and queues large exits, v5 gets no question mark here
    const tip =
        [
            data?.unlocking !== undefined &&
                "New earnings unlock into the share price over 7 days, so leaving early hands your still unlocking part to the people who stay.",
            queue &&
                "More than you can take out right now goes into a line that pays in order. A request in line can’t be cancelled.",
            queue &&
                queue.backlog > 0n &&
                "Requests already in line get paid first, so less can be taken out right away.",
        ]
            .filter(Boolean)
            .join(" ") || undefined;

    // A full exit queues every share, otherwise the shares worth the amount now, rounded up
    const requestExit = (amount: bigint) => {
        if (!data?.queue || !address) return Promise.resolve(false);
        const shares =
            amount * 100_000n >= data.position * 99_999n
                ? data.shares
                : min(data.shares, ceilDiv(amount * (data.supply + 10n ** 6n), data.totalAssets + 1n));
        setKind("request");
        return tx.send({ functionName: "requestRedeem", args: [shares, address, address], queue: data.queue });
    };

    const blocked = !data
        ? undefined
        : data.shares === 0n
          ? "Nothing to withdraw"
          : data.maxWithdraw === 0n && data.stale
            ? "Prices are updating"
            : undefined;

    return (
        <>
            <TxSteps tx={tx.state} done={kind === "request" ? "Queued" : "Withdrawn"} />
            <AmountForm
                title={<BlockLabel tip={tip}>Withdraw BTC</BlockLabel>}
                source="Available"
                unit="BTC"
                verb="Withdraw"
                busy="Withdrawing"
                over="More than you can withdraw"
                max={data?.maxWithdraw}
                blocked={blocked}
                connect={isConnected ? undefined : { label: "Connect wallet", run: () => openConnectModal?.() }}
                overflow={
                    data?.queue && {
                        label: "Request exit",
                        confirm: "Can’t be cancelled, request exit?",
                        limit: data.position,
                        run: requestExit,
                    }
                }
                tx={tx.state}
                onEdit={tx.reset}
                onSubmit={(amount) => {
                    setKind("withdraw");
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
    backlog,
}: {
    value: Source;
    onChange: (next: Source) => void;
    bridging: boolean;
    backlog: boolean;
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
                        <span className="relative">{option === "btc" ? "BTC" : SWAPS ? "Ethereum" : "tBTC"}</span>
                        {option === "tbtc" && bridging && (
                            <span aria-hidden="true" className="relative size-1.5 animate-pulse rounded-full bg-gold" />
                        )}
                    </button>
                ))}
            </div>
            <InfoTip>
                {SWAPS
                    ? `Send tBTC, WBTC or cbBTC from any Ethereum wallet. WBTC and cbBTC swap into tBTC first, then it lands here as BTC in about ${BRIDGE_MINUTES} minutes, with no bridge fee. Wrapped BTC already on Mezo can’t be deposited.`
                    : `tBTC is Bitcoin on Ethereum. Send it from any Ethereum wallet and it lands here as BTC in about ${BRIDGE_MINUTES} minutes, with no bridge fee. Holding WBTC or cbBTC? Swap it to tBTC on Ethereum first. Wrapped BTC already on Mezo can’t be deposited.`}
                {backlog &&
                    " Withdrawals are waiting in line and new deposits pay them first, so you may not be able to take this out right away."}
            </InfoTip>
        </div>
    );
}

type AmountFormProps = {
    title: ReactNode;
    source: string;
    unit: string;
    picker?: ReactNode;
    extra?: (amount: bigint | undefined) => ReactNode;
    verb: string;
    busy: string;
    over: string;
    max: bigint | undefined;
    least?: bigint;
    blocked: string | undefined;
    connect: Connect;
    // Above max, up to limit, the form offers this instead and asks a second press before it runs
    overflow?: { label: string; confirm: string; limit: bigint; run: (amount: bigint) => Promise<boolean> } | false;
    initial?: string;
    tx: TxState;
    onEdit: () => void;
    onSubmit: (amount: bigint) => Promise<boolean>;
};

function AmountForm({
    title,
    source,
    unit,
    picker,
    extra,
    verb,
    busy,
    over,
    max,
    least,
    blocked,
    connect,
    overflow,
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
    const [confirming, setConfirming] = useState(false);
    const queueable = !!overflow && tooMuch && !!amount && amount <= overflow.limit;
    const canQueue = !connect && !working && !blocked && queueable;

    const label = connect
        ? connect.label
        : tx.status === "wallet"
          ? "Confirm in your wallet"
          : tx.status === "pending"
            ? `${busy}…`
            : (blocked ??
              (tooLittle && least !== undefined
                  ? `At least ${formatUnits(least, 18)} ${unit}`
                  : queueable && overflow
                    ? confirming
                        ? overflow.confirm
                        : overflow.label
                    : tooMuch
                      ? over
                      : verb));

    const edit = (next: string) => {
        setText(next);
        setConfirming(false);
        if (tx.status !== "wallet" && tx.status !== "pending") onEdit();
    };

    return (
        <Block>
            <form
                className="flex flex-1 flex-col"
                onSubmit={async (event) => {
                    event.preventDefault();
                    if (connect) return connect.run();
                    if (canQueue && overflow && amount) {
                        if (!confirming) return setConfirming(true);
                        setConfirming(false);
                        if (await overflow.run(amount)) setText("");
                        return;
                    }
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
                            {picker || <span className="ml-2 text-[18px] text-muted-foreground">{unit}</span>}
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
                {extra?.(amount)}
                <Press className="mt-auto" disabled={!connect && !ready && !canQueue}>
                    <Button
                        type="submit"
                        size="lg"
                        className="h-12 overflow-hidden text-base"
                        disabled={!connect && !ready && !canQueue}
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

function BridgeSteps({ state, swap }: { state: BridgeState; swap: boolean }) {
    const hash = "hash" in state ? state.hash : undefined;
    const left = useMinutesLeft(state.status === "arriving" ? state.lockedAt : undefined);
    // A swap takes the second step and folds the tBTC approval into the bridge step
    const at =
        state.status === "error"
            ? (state.at ?? (hash ? 2 : 1))
            : {
                  idle: 0,
                  swap: 1,
                  swapping: 1,
                  approve: swap ? 2 : 1,
                  bridge: 2,
                  locking: 2,
                  arriving: 3,
                  arrived: 4,
              }[state.status];
    const linkAt = state.status === "swapping" || (state.status === "error" && state.at === 1) ? 1 : 2;
    return (
        <Steps
            labels={["Amount", swap ? "Swap" : "Approve", "Bridge", "Arrive"]}
            at={at}
            failed={state.status === "error"}
            spinning={state.status !== "idle" && state.status !== "arrived" && state.status !== "error"}
            link={hash && { at: linkAt, href: `${ETHEREUM_EXPLORER}/tx/${hash}` }}
            note={left === undefined ? undefined : { at: 3, text: left > 0 ? `~${left} min` : "Any minute" }}
            message={state.status === "error" ? state.message : undefined}
        />
    );
}

// The token sent from Ethereum, WBTC and cbBTC swap into tBTC before the bridge
function TokenPicker({
    value,
    onChange,
    disabled,
}: {
    value: Token;
    onChange: (next: Token) => void;
    disabled: boolean;
}) {
    const [open, setOpen] = useState(false);
    return (
        <span className="relative ml-2">
            <button
                type="button"
                aria-label={`Token, ${value}`}
                aria-expanded={open}
                disabled={disabled}
                onClick={() => setOpen((was) => !was)}
                className="inline-flex items-center gap-1 rounded-full bg-card py-1 pr-2 pl-3 text-[18px] text-muted-foreground transition-colors hover:text-foreground disabled:opacity-60"
            >
                {value}
                <motion.span animate={{ rotate: open ? 180 : 0 }} transition={springy}>
                    <ChevronDownIcon className="size-4" />
                </motion.span>
            </button>
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
                            key="tokens"
                            className="absolute top-11 left-0 z-50 w-36 origin-top-left rounded-tile bg-card p-1.5 shadow-[0_16px_40px_-16px_rgb(24_23_23/0.35)] ring-1 ring-foreground/5"
                            initial={{ opacity: 0, scale: 0.9, y: -6 }}
                            animate={{ opacity: 1, scale: 1, y: 0 }}
                            exit={{ opacity: 0, scale: 0.95, y: -4, transition: { duration: 0.12 } }}
                            transition={pop}
                        >
                            {(["tBTC", "WBTC", "cbBTC"] as const).map((option) => (
                                <li key={option}>
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setOpen(false);
                                            onChange(option);
                                        }}
                                        className={cn(
                                            "flex h-10 w-full items-center rounded-[14px] px-3 text-left text-[15px] font-medium transition-colors hover:bg-secondary",
                                            option === value && "bg-secondary",
                                        )}
                                    >
                                        {option}
                                    </button>
                                </li>
                            ))}
                        </motion.ul>
                    </>
                )}
            </AnimatePresence>
        </span>
    );
}

// What lands on Mezo after the swap, from a live quote
function SwapQuote({ token, amount }: { token: Token; amount: bigint | undefined }) {
    const out = useSwapQuote(token, amount);
    // The same 3% the bridge hook refuses at, so the warning shows before anyone signs
    const thin = !!amount && !!out && out * 100n < amount * 97n;
    return (
        <AnimatePresence initial={false}>
            {!!amount && (
                <motion.p
                    key="quote"
                    className={cn(
                        "mt-3 flex h-6 items-center gap-1.5 text-[15px] tabular-nums",
                        thin || out === null ? "text-danger" : "text-muted-foreground",
                    )}
                    initial={{ opacity: 0, y: -4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    transition={pop}
                >
                    <ArrowRightIcon className="size-4" />
                    {out === undefined
                        ? "Quoting…"
                        : out === null
                          ? "No swap route for that size"
                          : thin
                            ? "Not enough liquidity for that size"
                            : `${formatBtc(out)} BTC on Mezo`}
                </motion.p>
            )}
        </AnimatePresence>
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
    if (state.status === "swap" || state.status === "approve" || state.status === "bridge") return { status: "wallet" };
    if (state.status === "swapping" || state.status === "locking" || state.status === "arriving") {
        return { status: "pending", hash: state.hash };
    }
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

function ceilDiv(a: bigint, b: bigint) {
    return (a + b - 1n) / b;
}

function min(a: bigint, b: bigint) {
    return a < b ? a : b;
}
