"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { ArrowPathIcon, ArrowTopRightOnSquareIcon, CheckIcon, XMarkIcon } from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { parseUnits, type Hash } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Button } from "@/components/ui/button";
import { EXPLORER } from "@/lib/chain";
import { useVault, useVaultTx, useWalletBtc, type TxState } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { pop, rise, springy } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Chip, ChipRow, Eyebrow, FigureRow, Press } from "../block";

// Enough gas for this deposit and a later withdrawal, a Bitcoin wallet's smart account pays both refunds from here
const GAS_RESERVE = 3_000_000n;

export function Deposit() {
    const { address } = useAccount();
    const wallet = useWalletBtc();
    const gasPrice = useGasPrice().data;
    const { data } = useVault();
    const tx = useVaultTx();

    const reserve = GAS_RESERVE * (gasPrice ?? 0n);
    const fromWallet = wallet === undefined ? undefined : wallet > reserve ? wallet - reserve : 0n;
    const max = fromWallet !== undefined && data ? min(fromWallet, data.maxDeposit) : undefined;
    const blocked = data?.maxDeposit === 0n ? (data.stale ? "Prices are updating" : "Deposits are paused") : undefined;

    return (
        <AmountForm
            title="Deposit BTC"
            source="Wallet"
            verb="Deposit"
            busy="Depositing"
            done="Deposited"
            over="Not enough BTC"
            max={max}
            blocked={blocked}
            tx={tx.state}
            onEdit={tx.reset}
            onSubmit={(amount) => tx.send({ functionName: "depositBTC", args: [address!], value: amount })}
        />
    );
}

export function Withdraw() {
    const { address } = useAccount();
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
        <AmountForm
            title="Withdraw BTC"
            source="Available"
            verb="Withdraw"
            busy="Withdrawing"
            done="Withdrawn"
            over="More than you can withdraw"
            max={data?.maxWithdraw}
            blocked={blocked}
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
    );
}

type AmountFormProps = {
    title: string;
    source: string;
    verb: string;
    busy: string;
    done: string;
    over: string;
    max: bigint | undefined;
    blocked: string | undefined;
    tx: TxState;
    onEdit: () => void;
    onSubmit: (amount: bigint) => Promise<boolean>;
};

function AmountForm({ title, source, verb, busy, done, over, max, blocked, tx, onEdit, onSubmit }: AmountFormProps) {
    const { isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const [text, setText] = useState("");
    const input = useRef<HTMLInputElement>(null);
    const [hovered, setHovered] = useState(false);
    const [focused, setFocused] = useState(false);
    const amount = parseAmount(text);
    const working = tx.status === "wallet" || tx.status === "pending";
    const tooMuch = !!amount && max !== undefined && amount > max;
    const ready = isConnected && !working && !blocked && !!amount && max !== undefined && !tooMuch;

    const label = !isConnected
        ? "Connect wallet"
        : tx.status === "wallet"
          ? "Confirm in your wallet"
          : tx.status === "pending"
            ? `${busy}…`
            : (blocked ?? (tooMuch ? over : verb));

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
                    if (!isConnected) return openConnectModal?.();
                    if (ready && amount && (await onSubmit(amount))) setText("");
                }}
            >
                <BlockHeader>
                    <BlockLabel>{title}</BlockLabel>
                    <CloseButton />
                </BlockHeader>
                {/* The whole pane focuses the amount, its figure sits level with the balance figure */}
                <div
                    className="-mx-3 mt-13 cursor-text rounded-tile bg-secondary px-3 py-3"
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
                                aria-label="Amount in BTC"
                                inputMode="decimal"
                                autoComplete="off"
                                placeholder="0"
                                value={text}
                                disabled={working}
                                onChange={(event) => edit(cleanAmount(event.target.value))}
                                className="max-w-full min-w-[1ch] bg-transparent font-heading text-[44px] leading-none font-bold tracking-[-0.03em] outline-none [field-sizing:content] placeholder:text-muted-foreground/40"
                            />
                            <span className="ml-2 text-[18px] text-muted-foreground">BTC</span>
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
                                        {max === undefined || !isConnected ? "–" : `${formatBtc(max)} BTC`}
                                    </span>
                                    {isConnected && !!max && (
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
                <ChipRow>
                    <AnimatePresence mode="popLayout" initial={false}>
                        <TxChip key={tx.status} tx={tx} done={done} busy={busy} />
                    </AnimatePresence>
                </ChipRow>
                <Press className="mt-auto" disabled={isConnected && !ready}>
                    <Button
                        type="submit"
                        size="lg"
                        className="h-12 overflow-hidden text-base"
                        disabled={isConnected && !ready}
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

// The chip row tells the transaction's story once one is sent
function TxChip({ tx, done, busy }: { tx: TxState; done: string; busy: string }) {
    if (tx.status === "error") {
        return (
            <Chip>
                <span className="max-w-[440px] truncate text-destructive">{tx.message}</span>
            </Chip>
        );
    }
    if (tx.status === "pending") {
        return (
            <TxLink hash={tx.hash}>
                <Chip>
                    <ArrowPathIcon className="size-4 animate-spin" />
                    {busy} <ArrowTopRightOnSquareIcon className="size-3.5" />
                </Chip>
            </TxLink>
        );
    }
    if (tx.status === "done") {
        return (
            <TxLink hash={tx.hash}>
                <Chip tone="gain">
                    <CheckIcon className="size-4" />
                    {done} <ArrowTopRightOnSquareIcon className="size-3.5" />
                </Chip>
            </TxLink>
        );
    }
    return <span />;
}

function TxLink({ hash, children }: { hash: Hash; children: React.ReactNode }) {
    return (
        <a href={`${EXPLORER}/tx/${hash}`} target="_blank" rel="noreferrer" aria-label="View transaction">
            {children}
        </a>
    );
}

function CloseButton() {
    return (
        <motion.div whileHover={{ rotate: 90, scale: 1.06 }} whileTap={{ scale: 0.9 }} transition={springy}>
            <Button asChild variant="secondary" size="icon" aria-label="Close">
                <Link href="/">
                    <XMarkIcon />
                </Link>
            </Button>
        </motion.div>
    );
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
