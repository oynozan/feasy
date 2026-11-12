import { parseAbi } from "viem";
import { mezoTestnet } from "viem/chains";

export const EXPLORER = "https://explorer.test.mezo.org";
export const FAUCET = "https://faucet.test.mezo.org";

// Logs before the vault's deployment block hold nothing of ours
export const VAULT_FROM_BLOCK = 16_686_260n;

// Older vaults stay live and keep paying exits, a Move row per vault brings what is left there into this one
export const LEGACY_VAULTS: { name: string; address: `0x${string}` }[] = [
    { name: "v7", address: "0x4DA2eb6942cF136126A630e4C968CE43474c0Db6" },
    { name: "v6", address: "0xb7A15aB24483Dfe92056F73279ECF11CE00675db" },
    { name: "v5", address: "0x2964612e8976b4003083E6014cA39f5fD7b41f3A" },
];

export const vault = {
    address: "0x5e7800fB24651038e72ad1e055A2B2AD81a59Ed2",
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
        "function sleeve() view returns (address)",
        "function rawAssets() view returns (uint256)",
        "function recorded() view returns (uint256)",
        "function savingsSleeve() view returns (address)",
        "function feeBps() view returns (uint16)",
        "function nextFeeBps() view returns (uint16)",
        "function nextFeeAt() view returns (uint64)",
        "function feeRecipient() view returns (address)",
        "function closing() view returns (bool)",
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
        "error RollWindow()",
        "error RollGas()",
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
    "event Claimed(uint256 indexed id, address indexed owner, address indexed receiver, uint256 shares, uint256 assets)",
    "error NotVault()",
    "error BadReceiver()",
    "error BadParams()",
]);

// v7 keeps up to sleeveBps of the pool in veBTC locks ending on consecutive Thursdays, at vault.sleeve()
export const veSleeve = parseAbi([
    "function principal() view returns (uint256)",
    "function paused() view returns (bool)",
    "function live() view returns (bool)",
    "function lockWeeks() view returns (uint8)",
    "function sleeveBps() view returns (uint16)",
    "function rungs(uint256 i) view returns (uint256 id, uint128 amount, uint64 end)",
]);

// v8 keeps the borrowed MUSD here as sMUSD and stakes part of it in Mezo's sMUSD gauge for MEZO, at vault.savingsSleeve()
export const savingsSleeve = parseAbi([
    "function savings() view returns (address)",
    "function savingsRate() view returns (uint256)",
    "function loanRate() view returns (uint256)",
    "function spreadOk() view returns (bool)",
    "function staked() view returns (uint256)",
    "function mezoEarned() view returns (uint256)",
    "function booster() view returns (address)",
    "event MezoHarvested(uint256 mezoIn, uint256 btcOut)",
]);

// Holds the fee shares and the veMEZO that boosts the pool's own veBTC locks
export const booster = parseAbi([
    "function veMezoId() view returns (uint256)",
    "function veMezo() view returns (address)",
    "function boostVoter() view returns (address)",
]);

export const erc20 = parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function totalSupply() view returns (uint256)",
]);
export const veMezo = parseAbi(["function votingPowerOfNFT(uint256 tokenId) view returns (uint256)"]);
// A boost of 1e18 is 1x
export const boostVoter = parseAbi(["function getBoost(uint256 tokenId) view returns (uint256)"]);

/* Liquid locker */

// Mezo Earn's veBTC and veMEZO, and the BoostVoter where veMEZO votes boost veBTC locks
export const VE_BTC = "0x38E35d92E6Bfc6787272A62345856B13eA12130a";
export const VE_MEZO = "0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b";
export const BOOST_VOTER = "0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1";
export const MEZO_TOKEN = "0x7B7c000000000000000000000000000000000001";
export const BTC_TOKEN = "0x7b7C000000000000000000000000000000000000";
export const MUSD_TOKEN = "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503";

export const MEZO_LOCKER = "0xaE45e8B6f79Ed678dC3986EbA0871eF85cc8D385";

// fveBTC, the four week veBTC ladder, its exit queue and the rewards its holders earn
export const locker = {
    address: "0x8576C2ea77dbae1D6897d4D5834B1ae247e9032F",
    abi: parseAbi([
        "function totalSupply() view returns (uint256)",
        "function balanceOf(address) view returns (uint256)",
        "function locked() view returns (uint256)",
        "function idle() view returns (uint256)",
        "function reserved() view returns (uint256)",
        "function queued() view returns (uint256)",
        "function filled() view returns (uint256)",
        "function paused() view returns (bool)",
        "function live() view returns (bool)",
        "function boostBps() view returns (uint16)",
        "function feeBps() view returns (uint16)",
        "function mezoLocker() view returns (address)",
        "function rungs(uint256 i) view returns (uint256 id, uint128 amount, uint64 end)",
        "function earned(address token, address account) view returns (uint256)",
        "function rewardRate(address token) view returns (uint256)",
        "function requestsOf(address owner) view returns (uint256[])",
        "function requests(uint256 id) view returns (address owner, uint96 amount, uint128 end, uint128 claimed)",
        "function claimable(uint256 id) view returns (uint256)",
        "function deposit(address receiver) payable returns (uint256)",
        "function depositLock(uint256 id, address receiver) returns (uint256)",
        "function requestRedeem(uint256 amount) returns (uint256)",
        "function claimRedeem(uint256 id) returns (uint256)",
        "function claim() returns (uint256 btcPaid, uint256 musdPaid)",
        "event Deposited(address indexed sender, address indexed receiver, uint256 amount, uint256 veId)",
        "event RedeemRequested(uint256 indexed id, address indexed owner, uint256 amount)",
        "event RedeemClaimed(uint256 indexed id, address indexed owner, uint256 amount)",
        "event Rolled(uint256 released, uint256 relocked)",
        "event Harvested(address indexed token, uint256 income, uint256 boostCut, uint256 fee)",
        "error TooSmall()",
        "error Paused()",
        "error NoRung()",
        "error Voted()",
        "error BadLock()",
        "error LowGas()",
        "error RebatePending()",
    ]),
} as const;

// fveMEZO, one permanent veMEZO lock that boosts the ladder and takes a cut of its income
export const mezoLocker = parseAbi([
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function veMezoId() view returns (uint256)",
    "function earned(address token, address account) view returns (uint256)",
    "function rewardRate(address token) view returns (uint256)",
    "function deposit(uint256 amount, address receiver)",
    "function depositLock(uint256 id, address receiver)",
    "function claim() returns (uint256 btcPaid, uint256 musdPaid)",
    "event Deposited(address indexed sender, address indexed receiver, uint256 amount, uint256 veId)",
    "error TooSmall()",
    "error Paused()",
    "error Voted()",
    "error Permanent()",
    "error Ended()",
    "error RebatePending()",
    "error NoLock()",
]);

// The calls a wallet's own veBTC and veMEZO locks need before they can come in
export const veNft = parseAbi([
    "function balanceOf(address owner) view returns (uint256)",
    "function ownerToNFTokenIdList(address owner, uint256 index) view returns (uint256)",
    "function locked(uint256 id) view returns ((int128 amount, uint256 end, bool isPermanent, uint256 boost))",
    "function voted(uint256 id) view returns (bool)",
    "function getApproved(uint256 id) view returns (address)",
    "function votingPowerOfNFT(uint256 id) view returns (uint256)",
    "function approve(address spender, uint256 id)",
    "event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)",
]);

export const token = parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
]);

export const boostGauges = parseAbi([
    "function getBoost(uint256 tokenId) view returns (uint256)",
    "function boostableTokenIdToGauge(uint256 tokenId) view returns (address)",
]);
