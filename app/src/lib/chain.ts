import { parseAbi } from "viem";
import { mezoTestnet } from "viem/chains";

export const EXPLORER = "https://explorer.test.mezo.org";

// Logs before the vault's deployment block hold nothing of ours
export const VAULT_FROM_BLOCK = 16_337_559n;

export const vault = {
    address: "0x2964612e8976b4003083E6014cA39f5fD7b41f3A",
    abi: parseAbi([
        "function balanceOf(address) view returns (uint256)",
        "function totalAssets() view returns (uint256)",
        "function totalSupply() view returns (uint256)",
        "function convertToAssets(uint256 shares) view returns (uint256)",
        "function maxDeposit(address) view returns (uint256)",
        "function maxWithdraw(address owner) view returns (uint256)",
        "function maxRedeem(address owner) view returns (uint256)",
        "function trove() view returns ((bool active, uint256 coll, uint256 debt))",
        "function savingsValue() view returns (uint256)",
        "function lastPrice() view returns (uint256)",
        "function minCR() view returns (uint256)",
        "function targetCR() view returns (uint256)",
        "function borrowingEnabled() view returns (bool)",
        "function lockedProfit() view returns (uint256)",
        "function profit() view returns (uint128 locked, uint64 lockedAt, uint64 unlockAt)",
        "function queue() view returns (address)",
        "function depositBTC(address receiver) payable returns (uint256)",
        "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
        "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
        "event Transfer(address indexed from, address indexed to, uint256 value)",
        "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
        "event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)",
        "error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max)",
        "error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max)",
        "error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max)",
        "error Illiquid()",
        "error ZeroShares()",
        "error NotQueue()",
        "error NotGuardian()",
    ]),
} as const;

export const priceFeed = {
    address: "0x86bCF0841622a5dAC14A313a15f96A95421b9366",
    abi: parseAbi(["function fetchPrice() view returns (uint256)"]),
} as const;

export const troveManager = {
    address: "0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0",
    abi: parseAbi(["function getTroveInterestRate(address) view returns (uint16)"]),
} as const;

export const rateManager = {
    address: "0xD4D6c36A592A2c5e86035A6bca1d57747a567f37",
    abi: parseAbi(["function interestRate() view returns (uint16)"]),
} as const;

// The app runs on Mezo testnet unless a build sets NEXT_PUBLIC_MEZO_NETWORK to mainnet
export const MEZO_MAINNET = process.env.NEXT_PUBLIC_MEZO_NETWORK === "mainnet";

// Mezo mainnet, read only for the rates the yield is quoted at since testnet's savings pay a made up rate
export const MAINNET_RPC = "https://rpc-http.mezo.boar.network";

export const mainnetSavings = {
    address: "0xb4D498029af77680cD1eF828b967f010d06C51CC",
    abi: parseAbi(["function yieldIndex() view returns (uint256)"]),
} as const;

export const mainnetRates = {
    address: "0x4a453700d157717Fe02fB62E7700ED7845048285",
    abi: rateManager.abi,
} as const;

export const multicall = {
    address: mezoTestnet.contracts.multicall3.address,
    abi: parseAbi(["function getEthBalance(address addr) view returns (uint256 balance)"]),
} as const;

// v6 takes exits larger than the pool can pay at once into this queue, its address comes from vault.queue()
export const redeemQueue = parseAbi([
    "function requestRedeem(uint256 shares, address receiver, address owner) returns (uint256 id)",
    "function claim(uint256[] ids) returns (uint256 assets)",
    "function pendingRedeem(uint256 id) view returns (uint256)",
    "function claimableRedeem(uint256 id) view returns (uint256)",
    "function sharesAhead(uint256 id) view returns (uint256)",
    "function requestsOf(address owner) view returns (uint256[])",
    "function queueState() view returns (uint256 queued, uint256 filled, uint256 reservedBtc, uint256 requests)",
    "error NotVault()",
    "error BadReceiver()",
    "error BadParams()",
]);
