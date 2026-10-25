import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
    BaseError,
    ChainMismatchError,
    ContractFunctionRevertedError,
    createPublicClient,
    createWalletClient,
    custom,
    defineChain,
    fallback,
    formatUnits,
    getAddress,
    http,
    InsufficientFundsError,
    parseAbi,
    parseEventLogs,
    ResourceUnavailableRpcError,
    SwitchChainError,
    UserRejectedRequestError,
    WaitForTransactionReceiptTimeoutError,
    zeroAddress,
    type Address,
    type EIP1193Provider,
    type Hash,
    type WalletClient,
} from "viem";
import { mainnet, mezo, mezoTestnet, sepolia } from "viem/chains";
import { useAccount, useConnections } from "wagmi";
import { MAINNET_RPC, MEZO_MAINNET, vault } from "./chain";
import { bestRoute, fromToken, swapCall, toToken, WRAPPED, type Source } from "./swap";

export const BRIDGE_MINUTES = 16;

export type BridgeState =
    | { status: "idle" }
    | { status: "swap" }
    | { status: "swapping"; hash: Hash }
    | { status: "approve" }
    | { status: "bridge" }
    | { status: "locking"; hash: Hash }
    | { status: "arriving"; hash: Hash; amount: bigint; sequence: bigint; lockedAt: number }
    | { status: "arrived"; hash: Hash; amount: bigint }
    | { status: "error"; message: string; hash?: Hash; at?: 1 | 2 };

type Arriving = Extract<BridgeState, { status: "arriving" }>;

// Sepolia pairs with Mezo testnet and Ethereum with Mezo mainnet, each RPC is keyless and open to browsers
const NET = MEZO_MAINNET
    ? {
          chain: mainnet,
          rpcs: ["https://ethereum-rpc.publicnode.com", "https://mainnet.gateway.tenderly.co"],
          tbtc: "0x18084fbA666a33d37592fA2633fD49a74DD93a88" as Address,
          bridge: "0xF6680EA3b480cA2b72D96ea13cCAF2cFd8e6908c" as Address,
          explorer: "https://etherscan.io",
          gas: "ETH",
          mezo,
          mezoRpc: MAINNET_RPC,
      }
    : {
          chain: sepolia,
          rpcs: ["https://ethereum-sepolia-rpc.publicnode.com", "https://sepolia.gateway.tenderly.co"],
          tbtc: "0x517f2982701695D4E52f1ECFBEf3ba31Df470161" as Address,
          bridge: "0x3a3BaE133739f92a885070DbF3300d61B232497C" as Address,
          explorer: "https://sepolia.etherscan.io",
          gas: "Sepolia ETH",
          mezo: mezoTestnet,
          mezoRpc: undefined,
      };

// WBTC and cbBTC only have real tBTC pools on Ethereum mainnet
export const SWAPS = MEZO_MAINNET;
export const ETHEREUM_EXPLORER = NET.explorer;

const STORE = "feasy.bridge";
const POLL = 30_000;
const RECEIPT_TIMEOUT = 10 * 60_000;
// The swap may pay this much less than its quote before it reverts
const SLIPPAGE_BPS = 30n;

const ethereum = defineChain({ ...NET.chain, rpcUrls: { default: { http: NET.rpcs } } });
const eth = createPublicClient({ chain: ethereum, transport: fallback(NET.rpcs.map((url) => http(url))) });
const mezoClient = createPublicClient({ chain: NET.mezo, transport: http(NET.mezoRpc) });

const erc20 = parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
    "event Transfer(address indexed from, address indexed to, uint256 value)",
]);

const tbtc = { address: NET.tbtc, abi: erc20 } as const;

const mezoBridge = {
    address: NET.bridge,
    abi: parseAbi([
        "function minTBTCAmount() view returns (uint256)",
        "function bridgeTBTC(uint256 amount, address recipient)",
        "event AssetsLocked(uint256 indexed sequenceNumber, address indexed recipient, address indexed token, uint256 amount)",
        "error AmountBelowMinTBTCAmount()",
        "error BTCRecipientIsZeroAddress()",
    ]),
} as const;

// Mezo's tip passes a sequence number once the BTC locked under it is minted
const assetsBridge = {
    address: "0x7B7C000000000000000000000000000000000012",
    abi: parseAbi(["function getCurrentSequenceTip() view returns (uint256)"]),
} as const;

function injected() {
    if (typeof window === "undefined") return undefined;
    return (window as unknown as { ethereum?: EIP1193Provider }).ethereum;
}

/* BTC on Ethereum */

// The picked token's balance in 18 decimals, so satoshi tokens line up with tBTC and Mezo's BTC
export function useEthereumBtc(source: Source): {
    available: boolean;
    account: Address | undefined;
    balance: bigint | undefined;
    min: bigint | undefined;
    connect: () => void;
} {
    const { provider, account, connect } = useEthereum();
    const token = source === "tBTC" ? NET.tbtc : WRAPPED[source].address;
    const balance = useQuery({
        queryKey: ["ethereum-btc", source, account],
        enabled: !!account && (source === "tBTC" || SWAPS),
        refetchInterval: 15_000,
        queryFn: async () =>
            fromToken(
                await eth.readContract({ address: token, abi: erc20, functionName: "balanceOf", args: [account!] }),
                source,
            ),
    }).data;
    const min = useQuery({
        queryKey: ["tbtc-min"],
        staleTime: 60 * 60_000,
        queryFn: () => eth.readContract({ ...mezoBridge, functionName: "minTBTCAmount" }),
    }).data;
    return { available: !!provider, account, balance: account ? balance : undefined, min, connect };
}

// The tBTC a swap would pay right now, quoted once typing pauses
export function useSwapQuote(source: Source, amount: bigint | undefined) {
    const [settled, setSettled] = useState(amount);
    useEffect(() => {
        const timer = setTimeout(() => setSettled(amount), 300);
        return () => clearTimeout(timer);
    }, [amount]);
    return useQuery({
        queryKey: ["swap-quote", source, settled?.toString()],
        enabled: SWAPS && source !== "tBTC" && !!settled,
        staleTime: 15_000,
        refetchInterval: 15_000,
        queryFn: async () =>
            source === "tBTC" ? null : ((await bestRoute(eth, source, toToken(settled!, source)))?.out ?? null),
    }).data;
}

// Signs with the connected EVM wallet when there is one, window.ethereum may belong to another
function useEthereum() {
    const { connector, address } = useAccount();
    const connections = useConnections();
    // The active wallet when it is an EVM one, otherwise an EVM wallet connected beside a Bitcoin one
    const evm = [
        ...(connector && address ? [{ connector, account: address }] : []),
        ...connections.map((c) => ({ connector: c.connector, account: c.accounts[0] })),
    ].find((c) => typeof (c.connector as { getBitcoinProvider?: unknown }).getBitcoinProvider !== "function");
    const provider =
        useQuery({
            queryKey: ["ethereum-provider", evm ? evm.connector.uid : "injected"],
            staleTime: Infinity,
            structuralSharing: false,
            queryFn: async () =>
                evm ? ((await evm.connector.getProvider()) as EIP1193Provider) : (injected() ?? null),
        }).data ?? undefined;
    const [asked, setAsked] = useState<Address>();
    const listened = useInjectedAccount(evm ? undefined : provider);
    const account = evm ? evm.account : (asked ?? listened);
    const connect = () => {
        void provider?.request({ method: "eth_requestAccounts" }).then(
            (accounts) => accounts[0] && setAsked(getAddress(accounts[0])),
            () => {},
        );
    };
    return { provider, account, connect };
}

function useInjectedAccount(provider: EIP1193Provider | undefined) {
    const [account, setAccount] = useState<Address>();
    useEffect(() => {
        if (!provider) return;
        let live = true;
        const update = (accounts: readonly Address[]) => {
            if (live) setAccount(accounts[0] ? getAddress(accounts[0]) : undefined);
        };
        provider.request({ method: "eth_accounts" }).then(update, () => {});
        provider.on("accountsChanged", update);
        return () => {
            live = false;
            provider.removeListener("accountsChanged", update);
        };
    }, [provider]);
    return account;
}

/* Bridge */

type Entry = { owner: string | undefined; state: BridgeState };

class Failed extends Error {}

// A send keeps running when the account changes, so its updates only land on the recipient it started for
const forOwner = (owner: string | undefined, state: BridgeState) => (current: Entry) =>
    current.owner === owner ? { owner, state } : current;

export function useBridge(recipient: Address | undefined): {
    state: BridgeState;
    send: (amount: bigint, source?: Source) => Promise<boolean>;
    reset: () => void;
} {
    const queryClient = useQueryClient();
    const { provider } = useEthereum();
    const owner = recipient?.toLowerCase();
    const [entry, setEntry] = useState<Entry>(() => ({ owner, state: restore(owner) }));
    if (entry.owner !== owner) setEntry({ owner, state: restore(owner) });
    const busy = useRef(false);

    const arriving = entry.state.status === "arriving" ? entry.state : undefined;
    useEffect(() => {
        if (!arriving || !owner) return;
        let live = true;
        const check = async () => {
            const tip = await mezoClient
                .readContract({ ...assetsBridge, functionName: "getCurrentSequenceTip" })
                .catch(() => undefined);
            if (!live || tip === undefined || tip < arriving.sequence) return;
            live = false;
            forget(owner, arriving.sequence);
            setEntry(forOwner(owner, { status: "arrived", hash: arriving.hash, amount: arriving.amount }));
            // The mint fires no log on Mezo, the native balance just grows
            void queryClient.invalidateQueries();
        };
        void check();
        const timer = setInterval(check, POLL);
        return () => {
            live = false;
            clearInterval(timer);
        };
    }, [arriving, owner, queryClient]);

    // Resolves true once the Ethereum lock lands, the Mezo mint follows minutes later
    async function send(amount: bigint, source: Source = "tBTC") {
        if (busy.current) return false;
        const target = owner;
        const set = (state: BridgeState) => setEntry(forOwner(target, state));
        const refused = refuse(recipient, amount);
        if (refused || !recipient) {
            set({ status: "error", message: refused ?? "Connect your Mezo account first." });
            return false;
        }
        if (!provider) {
            set({ status: "error", message: "Install an Ethereum wallet like MetaMask to bridge tBTC." });
            return false;
        }
        busy.current = true;
        const wallet = createWalletClient({ chain: ethereum, transport: custom(provider) });
        let back: number | undefined;
        let hash: Hash | undefined;
        // The step a failure belongs to, the swap or tBTC approval first and the bridge second
        let at: 1 | 2 = 1;
        let swapped = false;
        try {
            set({ status: "idle" });
            const [account] = await wallet.requestAddresses();
            if (!account) throw new Failed("Unlock your Ethereum wallet and try again.");
            const amountIn = toToken(amount, source);
            const token = source === "tBTC" ? NET.tbtc : WRAPPED[source].address;

            // Checked before the switch so a doomed bridge never moves the wallet off its chain
            const [held, min, gas, from, route] = await Promise.all([
                eth.readContract({ address: token, abi: erc20, functionName: "balanceOf", args: [account] }),
                eth.readContract({ ...mezoBridge, functionName: "minTBTCAmount" }),
                eth.getBalance({ address: account }),
                wallet.getChainId().catch(() => NET.mezo.id),
                source === "tBTC" ? undefined : bestRoute(eth, source, amountIn),
            ]);
            if (held < amountIn) throw new Failed(`Not enough ${source} in your Ethereum wallet.`);
            if (gas === 0n) throw new Failed(`You need some ${NET.gas} for gas.`);
            if (source !== "tBTC" && !route) throw new Failed("No swap route is open right now, try again soon.");
            // A thin pool can quietly eat a large swap, so losing more than 3% stops here
            if (route && route.out * 100n < amount * 97n) {
                throw new Failed("There isn’t enough liquidity for that size right now.");
            }
            if ((route?.out ?? amount) < min)
                throw new Failed(`The bridge takes at least ${formatUnits(min, 18)} tBTC.`);
            const toEthereum = async () => {
                if (back !== undefined || from === ethereum.id) return;
                await switchToEthereum(wallet);
                back = from;
            };

            let bridged = amount;
            if (route) {
                set({ status: "swap" });
                await toEthereum();
                await approveIfShort(wallet, account, token, route.spender, amountIn);
                const minOut = route.out - (route.out * SLIPPAGE_BPS) / 10_000n;
                // Either venue's call, viem cannot narrow the union of the two
                const { request } = await eth.simulateContract({
                    ...swapCall(route, amountIn, minOut, account),
                    account,
                } as Parameters<typeof eth.simulateContract>[0]);
                hash = await wallet.writeContract(request as never);
                set({ status: "swapping", hash });
                const receipt = await eth.waitForTransactionReceipt({ hash, timeout: RECEIPT_TIMEOUT });
                if (receipt.status !== "success") throw new Failed("The swap didn't go through.");
                // Bridge what the pool really paid, the quote only set the floor
                bridged = parseEventLogs({
                    abi: erc20,
                    eventName: "Transfer",
                    logs: receipt.logs.filter((log) => log.address.toLowerCase() === NET.tbtc.toLowerCase()),
                })
                    .filter((log) => log.args.to.toLowerCase() === account.toLowerCase())
                    .reduce((sum, log) => sum + log.args.value, 0n);
                if (bridged === 0n) throw new Failed("The swap paid no tBTC.");
                swapped = true;
                hash = undefined;
                at = 2;
            }

            const allowance = await eth.readContract({
                ...tbtc,
                functionName: "allowance",
                args: [account, NET.bridge],
            });
            set({ status: allowance < bridged ? "approve" : "bridge" });
            await toEthereum();
            await approveIfShort(wallet, account, NET.tbtc, NET.bridge, bridged);
            set({ status: "bridge" });
            at = 2;

            const { request } = await eth.simulateContract({
                ...mezoBridge,
                functionName: "bridgeTBTC",
                args: [bridged, recipient],
                account,
            });
            hash = await wallet.writeContract(request);
            set({ status: "locking", hash });
            const receipt = await eth.waitForTransactionReceipt({ hash, timeout: RECEIPT_TIMEOUT });
            // A sped up transaction lands under a new hash
            hash = receipt.transactionHash;
            const [locked] = parseEventLogs({
                abi: mezoBridge.abi,
                eventName: "AssetsLocked",
                logs: receipt.logs.filter((log) => log.address.toLowerCase() === NET.bridge.toLowerCase()),
            });
            if (receipt.status !== "success" || !locked) throw new Failed("The bridge transaction didn't go through.");
            // The tBTC is locked by now, a missing block only blurs the countdown
            const block = await eth.getBlock({ blockNumber: receipt.blockNumber }).catch(() => undefined);
            const next: Arriving = {
                status: "arriving",
                hash,
                amount: locked.args.amount,
                sequence: locked.args.sequenceNumber,
                lockedAt: block ? Number(block.timestamp) : Math.floor(Date.now() / 1000),
            };
            if (target) remember(target, next);
            set(next);
            return true;
        } catch (error) {
            const failed = errorState(error);
            // Once the swap is through the tBTC waits in the wallet, so even a rejected bridge needs saying
            if (swapped) {
                set({
                    status: "error",
                    message: "Swapped. The tBTC is in your Ethereum wallet, bridge it from the tBTC option.",
                    hash,
                    at,
                });
            } else set(failed.status === "error" ? { ...failed, hash, at } : failed);
            return false;
        } finally {
            busy.current = false;
            // wagmi only knows Mezo, so a wallet left on Ethereum reads as the wrong network
            if (back !== undefined) void wallet.switchChain({ id: back }).catch(() => {});
        }
    }

    function reset() {
        if (owner && arriving) forget(owner, arriving.sequence);
        setEntry({ owner, state: { status: "idle" } });
    }

    return { state: entry.state, send, reset };
}

function refuse(recipient: Address | undefined, amount: bigint) {
    if (!recipient) return "Connect your Mezo account first.";
    const to = recipient.toLowerCase();
    // Mezo's precompiles and modules live under 0x7b7c and the bridge itself accepts them
    if (to === zeroAddress || to.startsWith("0x7b7c")) return "That address can't receive bridged BTC.";
    // Minted BTC would raise every holder's share and mint none for the sender
    if (to === vault.address.toLowerCase()) return "Bridge to your own address, not the pool.";
    if (amount <= 0n) return "Enter an amount to bridge.";
}

// Approves exactly the amount, only when the allowance falls short
async function approveIfShort(
    wallet: WalletClient,
    account: Address,
    token: Address,
    spender: Address,
    amount: bigint,
) {
    const allowance = await eth.readContract({
        address: token,
        abi: erc20,
        functionName: "allowance",
        args: [account, spender],
    });
    if (allowance >= amount) return;
    const { request } = await eth.simulateContract({
        address: token,
        abi: erc20,
        functionName: "approve",
        args: [spender, amount],
        account,
    });
    const approval = await wallet.writeContract(request);
    const receipt = await eth.waitForTransactionReceipt({ hash: approval, timeout: RECEIPT_TIMEOUT });
    if (receipt.status !== "success") throw new Failed("The approval didn't go through.");
    await allowanceReaches(token, account, spender, amount);
}

async function switchToEthereum(wallet: WalletClient) {
    try {
        await wallet.switchChain({ id: ethereum.id });
    } catch (error) {
        const unknown =
            error instanceof BaseError && !!error.walk((e) => e instanceof SwitchChainError || isCode(e, 4902));
        if (!unknown) throw error;
        await wallet.addChain({ chain: ethereum });
    }
}

// Public RPCs balance across nodes, one may not have the approval's block yet
async function allowanceReaches(token: Address, owner: Address, spender: Address, amount: bigint) {
    for (let tries = 0; tries < 10; tries++) {
        const allowance = await eth.readContract({
            address: token,
            abi: erc20,
            functionName: "allowance",
            args: [owner, spender],
        });
        if (allowance >= amount) return;
        await new Promise((resolve) => setTimeout(resolve, 2_000));
    }
}

function isCode(error: unknown, code: number) {
    return (error as { code?: unknown } | undefined)?.code === code;
}

/* Persistence */

type Saved = { hash: Hash; amount: string; sequence: string; lockedAt: number };

function saved(): Record<string, Saved> {
    try {
        const all = JSON.parse(localStorage.getItem(STORE) ?? "{}");
        return all && typeof all === "object" ? all : {};
    } catch {
        return {};
    }
}

function save(all: Record<string, Saved>) {
    try {
        if (Object.keys(all).length > 0) localStorage.setItem(STORE, JSON.stringify(all));
        else localStorage.removeItem(STORE);
    } catch {}
}

function remember(owner: string, state: Arriving) {
    const { hash, amount, sequence, lockedAt } = state;
    save({ ...saved(), [owner]: { hash, amount: String(amount), sequence: String(sequence), lockedAt } });
}

// Another tab may have stored a newer deposit for the same recipient
function forget(owner: string, sequence: bigint) {
    const all = saved();
    if (all[owner]?.sequence !== String(sequence)) return;
    delete all[owner];
    save(all);
}

function restore(owner: string | undefined): BridgeState {
    const entry = owner ? saved()[owner] : undefined;
    if (!entry) return { status: "idle" };
    try {
        return {
            status: "arriving",
            hash: entry.hash,
            amount: BigInt(entry.amount),
            sequence: BigInt(entry.sequence),
            lockedAt: Number(entry.lockedAt),
        };
    } catch {
        return { status: "idle" };
    }
}

/* Errors */

const REVERTS: Record<string, string> = {
    AmountBelowMinTBTCAmount: "That's below the bridge minimum.",
    BTCRecipientIsZeroAddress: "That address can't receive bridged BTC.",
};

function errorState(error: unknown): BridgeState {
    if (error instanceof Failed) return { status: "error", message: error.message };
    if (error instanceof BaseError) {
        if (error.walk((e) => e instanceof UserRejectedRequestError || isCode(e, 4001))) return { status: "idle" };
        if (error.walk((e) => e instanceof ResourceUnavailableRpcError)) {
            return { status: "error", message: "Your Ethereum wallet has a request waiting, open it." };
        }
        if (error.walk((e) => e instanceof ChainMismatchError || e instanceof SwitchChainError)) {
            return { status: "error", message: `Switch your Ethereum wallet to ${NET.chain.name} and try again.` };
        }
        if (error.walk((e) => e instanceof InsufficientFundsError)) {
            return { status: "error", message: `Not enough ${NET.gas} for gas.` };
        }
        if (error.walk((e) => e instanceof WaitForTransactionReceiptTimeoutError)) {
            return { status: "error", message: "Ethereum is slow right now, check the transaction on Etherscan." };
        }
        const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
        if (revert instanceof ContractFunctionRevertedError) {
            const name = revert.data?.errorName;
            if (name && REVERTS[name]) return { status: "error", message: REVERTS[name] };
            if (revert.reason?.includes("exceeds balance")) {
                return { status: "error", message: "Not enough tBTC in your Ethereum wallet." };
            }
            if (revert.reason?.includes("exceeds allowance")) {
                return { status: "error", message: "The tBTC approval hasn't landed yet, try again." };
            }
        }
    }
    return { status: "error", message: "The transaction didn't go through." };
}
