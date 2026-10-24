import { parseAbi } from "viem";

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
        "function targetCR() view returns (uint256)",
        "function depositBTC(address receiver) payable returns (uint256)",
        "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
        "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
        "event Transfer(address indexed from, address indexed to, uint256 value)",
        "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
        "event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)",
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

export const savings = {
    address: "0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16",
    abi: parseAbi(["function yieldIndex() view returns (uint256)"]),
} as const;
