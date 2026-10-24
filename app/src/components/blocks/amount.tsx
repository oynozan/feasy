"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowTopRightOnSquareIcon, XMarkIcon } from "@heroicons/react/16/solid";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { parseUnits } from "viem";
import { useAccount, useGasPrice } from "wagmi";
import { Button } from "@/components/ui/button";
import { EXPLORER } from "@/lib/chain";
import { useVault, useVaultTx, useWalletBtc, type TxState } from "@/lib/hooks";
import { formatBtc } from "@/lib/math";
import { Block, BlockLabel } from "../block";

// About twice a padded deposit's gas limit, left in the wallet so the deposit itself can pay for gas
const GAS_RESERVE = 600_000n;

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
            title="Deposit"
            verb="Deposit"
            busy="Depositing…"
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
            title="Withdraw"
            verb="Withdraw"
            busy="Withdrawing…"
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
    verb: string;
    busy: string;
    done: string;
    over: string;
    max: bigint | undefined;
    blocked: string | undefined;
    tx: TxState;
    onEdit: () => void;
    onSubmit: (amount: bigint) => Promise<void>;
};

function AmountForm({ title, verb, busy, done, over, max, blocked, tx, onEdit, onSubmit }: AmountFormProps) {
    const { isConnected } = useAccount();
    const { openConnectModal } = useConnectModal();
    const [text, setText] = useState("");
    const amount = parseAmount(text);
    const working = tx.status === "wallet" || tx.status === "pending";

    const label = !isConnected
        ? "Connect wallet"
        : tx.status === "wallet"
          ? "Confirm in your wallet"
          : tx.status === "pending"
            ? busy
            : tx.status === "done" && !text
              ? done
              : (blocked ?? (amount && max !== undefined && amount > max ? over : verb));
    const ready = isConnected && !working && !blocked && !!amount && max !== undefined && amount <= max;

    return (
        <Block className="min-h-[200px]">
            <div className="flex items-center justify-between">
                <BlockLabel>{title}</BlockLabel>
                <Button asChild variant="secondary" size="icon-sm" aria-label="Close">
                    <Link href="/">
                        <XMarkIcon />
                    </Link>
                </Button>
            </div>
            <form
                className="mt-6 flex flex-col gap-6"
                onSubmit={async (event) => {
                    event.preventDefault();
                    if (!isConnected) return openConnectModal?.();
                    if (!ready || !amount) return;
                    await onSubmit(amount);
                    setText("");
                }}
            >
                <label className="flex items-baseline gap-2">
                    <span className="sr-only">Amount in BTC</span>
                    <input
                        inputMode="decimal"
                        autoComplete="off"
                        placeholder="0"
                        value={text}
                        disabled={working}
                        onChange={(event) => {
                            setText(cleanAmount(event.target.value));
                            onEdit();
                        }}
                        className="w-full min-w-0 bg-transparent font-heading text-[clamp(40px,1.5rem+3vw,56px)] leading-none font-bold tracking-[-0.03em] outline-none placeholder:text-muted-foreground/40"
                    />
                    <span className="text-[24px] text-muted-foreground">BTC</span>
                </label>
                {isConnected && (
                    <button
                        type="button"
                        disabled={working || !max}
                        onClick={() => {
                            if (max) setText(formatBtc(max));
                            onEdit();
                        }}
                        className="self-start rounded-full bg-secondary px-3 py-1.5 text-[14px] font-medium tabular-nums text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
                    >
                        Max {max === undefined ? "…" : formatBtc(max)}
                    </button>
                )}
                <Button type="submit" size="lg" className="h-12 text-base" disabled={isConnected && !ready}>
                    {label}
                </Button>
            </form>
            <TxNote tx={tx} />
        </Block>
    );
}

function TxNote({ tx }: { tx: TxState }) {
    if (tx.status === "error") return <p className="mt-3 text-center text-[14px] text-destructive">{tx.message}</p>;
    if (tx.status !== "pending" && tx.status !== "done") return null;
    return (
        <a
            href={`${EXPLORER}/tx/${tx.hash}`}
            target="_blank"
            rel="noreferrer"
            className="mt-3 inline-flex items-center justify-center gap-1 text-[14px] text-muted-foreground hover:text-foreground"
        >
            View transaction <ArrowTopRightOnSquareIcon className="size-3.5" />
        </a>
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
