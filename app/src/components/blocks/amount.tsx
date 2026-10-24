"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowPathIcon, ArrowTopRightOnSquareIcon, CheckIcon, XMarkIcon } from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { AnimatePresence, motion } from "motion/react";
import { parseUnits, type Hash } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Button } from "@/components/ui/button";
import { EXPLORER } from "@/lib/chain";
import { useVault, useVaultTx, useWalletBtc, useYield, type TxState } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { pop, springy } from "@/lib/motion";
import { Block, BlockHeader, BlockLabel, Chip, ChipRow, Eyebrow, FigureRow, Press } from "../block";

// About twice a padded deposit's gas limit, left in the wallet so the deposit itself can pay for gas
const GAS_RESERVE = 600_000n;

export function Deposit() {
    const { address } = useAccount();
    const wallet = useWalletBtc();
    const gasPrice = useGasPrice().data;
    const { data } = useVault();
    const rate = useYield();
    const tx = useVaultTx();

    const reserve = GAS_RESERVE * (gasPrice ?? 0n);
    const fromWallet = wallet === undefined ? undefined : wallet > reserve ? wallet - reserve : 0n;
    const max = fromWallet !== undefined && data ? min(fromWallet, data.maxDeposit) : undefined;
    const blocked = data?.maxDeposit === 0n ? (data.stale ? "Prices are updating" : "Deposits are paused") : undefined;

    return (
        <AmountForm
            title="Deposit BTC"
            source="In your wallet"
            note="Your BTC joins the pool and grows with it. Withdraw anytime, earnings included."
            verb="Deposit"
            busy="Depositing"
            done="Deposited"
            over="Not enough BTC"
            max={max}
            blocked={blocked}
            estimate={(amount) => {
                if (rate === undefined) return undefined;
                const yearly = (amount * BigInt(Math.round(rate * 1e6))) / 1_000_000n;
                return `≈ ${yearly >= 0n ? "+" : ""}${formatBtc(yearly)} BTC a year`;
            }}
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
            source="Available now"
            note="The pool repays part of its loan from savings to free your BTC. No BTC is sold."
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
    note: string;
    verb: string;
    busy: string;
    done: string;
    over: string;
    max: bigint | undefined;
    blocked: string | undefined;
    estimate?: (amount: bigint) => string | undefined;
    tx: TxState;
    onEdit: () => void;
    onSubmit: (amount: bigint) => Promise<boolean>;
};

function AmountForm({
    title,
    source,
    note,
    verb,
    busy,
    done,
    over,
    max,
    blocked,
    estimate,
    tx,
    onEdit,
    onSubmit,
}: AmountFormProps) {
    const { isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const [text, setText] = useState("");
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
                <Eyebrow>
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
                                className="h-6 rounded-full bg-secondary px-2.5 text-[13px] font-medium text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
                            >
                                Max
                            </button>
                        </Press>
                    )}
                </Eyebrow>
                <FigureRow>
                    <label className="flex min-w-0 items-baseline">
                        <span className="sr-only">Amount in BTC</span>
                        <input
                            inputMode="decimal"
                            autoComplete="off"
                            placeholder="0"
                            value={text}
                            disabled={working}
                            onChange={(event) => edit(cleanAmount(event.target.value))}
                            className="max-w-full min-w-[1ch] bg-transparent font-heading text-[44px] leading-none font-bold tracking-[-0.03em] outline-none [field-sizing:content] placeholder:text-muted-foreground/40"
                        />
                        <span className="ml-2 text-[18px] text-muted-foreground">BTC</span>
                    </label>
                </FigureRow>
                <ChipRow>
                    <AnimatePresence mode="popLayout" initial={false}>
                        <TxChip key={chipKey(tx, amount)} tx={tx} done={done} busy={busy}>
                            {amount && estimate?.(amount)}
                        </TxChip>
                    </AnimatePresence>
                </ChipRow>
                <p className="mt-auto pt-6 text-[15px] leading-6 text-muted-foreground">{note}</p>
                <Press className="mt-6" disabled={isConnected && !ready}>
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

function chipKey(tx: TxState, amount: bigint | undefined) {
    return tx.status === "idle" || tx.status === "wallet" ? (amount ? "estimate" : "none") : tx.status;
}

// The chip row tells the transaction's story once one is sent, and the yearly estimate before that
function TxChip({ tx, done, busy, children }: { tx: TxState; done: string; busy: string; children: React.ReactNode }) {
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
    return children ? <Chip tone="gain">{children}</Chip> : <span />;
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
