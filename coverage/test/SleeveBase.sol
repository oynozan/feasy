// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "vault/Vault.sol";
import {RedeemQueue} from "vault/RedeemQueue.sol";
import {VeSleeve} from "vault/VeSleeve.sol";
// Imported by path only, so Foundry writes the library artifact it links the vault against
import {SystemMath} from "vault/SystemMath.sol";
import {
    IBorrowerOperations,
    ITroveManager,
    IHintHelpers,
    ISavings,
    IRouter,
    IVoter
} from "vault/interfaces/IMezo.sol";
import {Btc} from "./Btc.sol";

interface IMezoSystem {
    function activePool() external view returns (address);
    function borrowerOperations() external view returns (address);
    function collSurplusPool() external view returns (address);
    function hintHelpers() external view returns (address);
    function pcv() external view returns (address);
    function priceFeed() external view returns (address);
    function sortedTroves() external view returns (address);
    function troveManager() external view returns (address);
    function interestRateManager() external view returns (address);
    function aggregator() external view returns (address);
    function musd() external view returns (address);
    function poolFactory() external view returns (address);
    function router() external view returns (address);
    function exec(address target, bytes calldata data) external payable returns (bytes memory);
    function start(uint256 price, address savings) external;
}

interface IAggregator {
    function setPrice(uint256 price) external returns (bool);
}

interface IRateTester {
    function setInterestRateForTesting(uint16 rate) external;
}

interface IPoolAdmin {
    function createPool(address tokenA, address tokenB, bool stable) external returns (address);
}

interface IRouterLiquidity {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256, uint256, uint256);
}

interface ISavingsAdmin {
    function initialize(address musd) external;
    function setPCV(address pcv) external;
    function receiveProtocolYield(uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceFeedView {
    function fetchPrice() external view returns (uint256);
}

// Calls into Mezo Earn, every one is a function of the verified contracts in src/earn
interface IEarnVe {
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
        uint256 boost;
    }

    function initializeV2() external;
    function setTeam(address team) external;
    function setVoterAndDistributor(address voter, address distributor) external;
    function addSecondaryVoter(address voter) external;
    function voting(uint256 id, bool voted) external;
    function setBooster(address booster) external;
    function createLock(uint256 value, uint256 duration) external returns (uint256);
    function lockPermanent(uint256 id) external;
    function locked(uint256 id) external view returns (LockedBalance memory);
    function ownerOf(uint256 id) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function voted(uint256 id) external view returns (bool);
    function votingPowerOfNFT(uint256 id) external view returns (uint256);
    function totalVotingPower() external view returns (uint256);
    function voter() external view returns (address);
    function distributor() external view returns (address);
    function booster() external view returns (address);
    function token() external view returns (address);
    function team() external view returns (address);
    function supply() external view returns (uint256);
    function isSecondaryVoter(address voter) external view returns (bool);
    function votedVoters(uint256 id) external view returns (address[] memory);
}

interface IEarnVoter {
    function configureSplitterAndTokens(address[] calldata tokens, address splitter) external;
    function createVaultGauge(address gaugeFactory, address vault) external returns (address);
    function setGovernor(address governor) external;
    function setEmergencyCouncil(address council) external;
    function killGauge(address gauge) external;
    function reviveGauge(address gauge) external;
    function vote(uint256 id, address[] calldata pools, uint256[] calldata weights) external;
    function reset(uint256 id) external;
    function poke(uint256 id) external;
    function distribute(address[] memory gauges) external;
    function gauges(address pool) external view returns (address);
    function gaugeToFees(address gauge) external view returns (address);
    function gaugeToBribe(address gauge) external view returns (address);
    function isAlive(address gauge) external view returns (bool);
    function votes(uint256 id, address pool) external view returns (uint256);
    function weights(address pool) external view returns (uint256);
    function usedWeights(uint256 id) external view returns (uint256);
    function lastVoted(uint256 id) external view returns (uint256);
    function poolVote(uint256 id, uint256 index) external view returns (address);
    function totalWeight() external view returns (uint256);
    function claimable(address gauge) external view returns (uint256);
    function splitter() external view returns (address);
    function ve() external view returns (address);
    function governor() external view returns (address);
    function emergencyCouncil() external view returns (address);
}

interface IEarnReward {
    function earned(address token, uint256 id) external view returns (uint256);
    function balanceOf(uint256 id) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function tokenRewardsPerEpoch(address token, uint256 epoch) external view returns (uint256);
    function notifyRewardAmount(address token, uint256 amount) external;
    function isReward(address token) external view returns (bool);
}

interface IEarnDistributor {
    function setDepositor(address depositor) external;
    function claimable(uint256 id) external view returns (uint256);
    function claim(uint256 id) external returns (uint256);
    function depositor() external view returns (address);
    function lastTokenTime() external view returns (uint256);
    function tokensPerWeek(uint256 week) external view returns (uint256);
}

interface ISplitterLike {
    function updatePeriod() external returns (uint256);
    function activePeriod() external view returns (uint256);
    function needle() external view returns (uint256);
}

interface IGaugeLike {
    function deposit(uint256 amount) external;
    function left() external view returns (uint256);
    function rewardToken() external view returns (address);
    function stakingToken() external view returns (address);
    function feesVotingReward() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface INonStakingLike {
    function setSplitter(address splitter) external;
    function setGovernor(address governor) external;
}

interface IOwnableLike {
    function transferOwnership(address owner) external;
}

contract SleeveBase is Test {
    address constant BTC = 0x7b7C000000000000000000000000000000000000;
    // Mezo's MEZO precompile, left without code since nothing the vault touches calls it
    address constant MEZO = 0x7B7c000000000000000000000000000000000001;
    uint256 constant PRICE = 100_000e18;
    uint256 constant GAS_COMP = 200e18;
    uint256 constant WEEK = 7 days;
    // veBTC storage slot 82 on testnet
    uint256 constant MAX_LOCK = 2_419_200;
    // Thursday 2026-10-22 at midnight UTC, the epoch Mezo testnet is in
    uint256 constant E0 = 1_792_627_200;
    // Sunday 2026-10-25 at half past eight UTC
    uint256 constant NOW = E0 + 3 days + 8 hours + 30 minutes;
    // A week of chain fees for the rebate, of emissions for the gauge and of sMUSD protocol yield
    uint256 constant CHAIN_FEES = 0.02 ether;
    uint256 constant EMISSIONS = 0.01 ether;
    uint256 constant WEEKLY_YIELD = 1_000e18;
    // MUSD the whale stakes in the sMUSD gauge, testnet has 469,580 staked
    uint256 constant STAKED = 400_000e18;
    // The bytes of RungStuck(uint256)
    bytes32 constant RUNG_STUCK = keccak256("RungStuck(uint256)");

    string constant EARN = "coverage/src/earn/";
    string constant PROXY = "coverage/src/earn/TransparentUpgradeableProxy/@openzeppelin/contracts/proxy/"
        "transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy";

    IMezoSystem sys;
    IBorrowerOperations bo;
    ITroveManager tm;
    IERC20 musd;
    IERC20 btc = IERC20(BTC);
    address savings;
    address hints;
    address factory;
    address pool;
    IRouter router;
    Vault vault;
    RedeemQueue queue;
    VeSleeve sleeve;

    address forwarder;
    address registry;
    address gaugeFactory;
    IEarnVe ve;
    IEarnVoter voter;
    IEarnDistributor distributor;
    ISplitterLike chainFee;
    ISplitterLike eco;
    address veMezo;
    address booster;
    address thirdParty;
    address gauge;
    IEarnReward fees;
    IEarnReward bribe;
    uint256 daveLock;

    address whale = makeAddr("whale");
    address keeper = makeAddr("keeper");
    address guardian = makeAddr("guardian");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address stranger = makeAddr("stranger");
    // Another veBTC holder voting for the sMUSD gauge, as testnet has 6.1 veBTC on it
    address dave = makeAddr("dave");
    // The Mezo multisig 0x6e80 that is team, governor, emergency council and owner on testnet
    address team = makeAddr("mezoTeam");
    // Whoever runs Mezo's weekly period updates and distribute calls
    address mezoBot = makeAddr("mezoBot");

    function setUp() public virtual {
        // Mezo is deployed a week before the epoch under test, so its splitters have a past period
        vm.warp(E0 - WEEK + 2 hours);
        vm.etch(BTC, address(new Btc()).code);
        _etchVeLibraries();
        sys = IMezoSystem(deployCode("coverage/src/MezoSystem.sol:MezoSystem"));
        bo = IBorrowerOperations(sys.borrowerOperations());
        tm = ITroveManager(sys.troveManager());
        musd = IERC20(sys.musd());
        router = IRouter(sys.router());
        hints = sys.hintHelpers();
        factory = sys.poolFactory();

        address impl = deployCode(
            "MUSDSavingsRate.sol:MUSDSavingsRate",
            abi.encode(address(0xdEaD))
        );
        savings = address(
            new ERC1967Proxy(impl, abi.encodeCall(ISavingsAdmin.initialize, (address(musd))))
        );
        ISavingsAdmin(savings).setPCV(sys.pcv());
        sys.start(PRICE, savings);
        _seed();

        _deployEarn();
        vault = _newVault(7 days);
        queue = vault.queue();
        sleeve = vault.sleeve();
        vault.setBorrowingEnabled(true);
        _stakeAndVote();

        // The epoch flips, Mezo updates both periods and distributes, as testnet did for E0
        vm.warp(E0 + 1 minutes);
        _mezoWeek(true);
        vm.warp(NOW);
    }

    // The six veBTC libraries sit at their testnet addresses, foundry.toml links veBTC to them
    function _etchVeLibraries() internal {
        string[6] memory names = ["Balance", "Delegation", "Escrow", "Grant", "ManagedNFT", "NFT"];
        address[6] memory at = [
            0x9c13415B184810B0E43D5Cf7b94052DD0743E54C,
            0xf7664152fF5885830C4609280410392Dc93C7F9f,
            0xe68CC8Cd0F92bbe926e7aa93825CD2E3BADC7F27,
            0xd6bcCC4beBcA1C742E13d3cD23ED723b02a2927B,
            0xb949778ad86A086Ba9C93CA53F5f314C49cbB76d,
            0xC6182dA862739B89a5D74e884A759463294B930C
        ];
        for (uint256 i; i < 6; i++) {
            address lib = deployCode(
                string.concat(EARN, "VeBTC/contracts/ve/", names[i], ".sol:", names[i])
            );
            vm.etch(at[i], lib.code);
        }
    }

    // The whale keeps the vault trove from ever being the last one and seeds the pool
    function _seed() internal virtual {
        vm.deal(whale, 1000 ether);
        vm.prank(whale);
        bo.openTrove{value: 100 ether}(2_000_000e18, address(0), address(0));
        pool = IPoolAdmin(factory).createPool(BTC, address(musd), false);
        _addLiquidity(10 ether);
    }

    // Mezo Earn wired the way testnet reads, with BTC as the emission token in place of MEZO
    function _deployEarn() internal {
        forwarder = deployCode(
            string.concat(EARN, "MezoForwarder/contracts/forwarder/MezoForwarder.sol:MezoForwarder")
        );
        address vrf = deployCode(
            string.concat(
                EARN,
                "VotingRewardsFactory/contracts/factories/",
                "VotingRewardsFactory.sol:VotingRewardsFactory"
            )
        );
        gaugeFactory = deployCode(
            string.concat(EARN, "GaugeFactory/contracts/factories/GaugeFactory.sol:GaugeFactory")
        );
        address mrf = deployCode(
            string.concat(
                EARN,
                "ManagedRewardsFactory/contracts/factories/",
                "ManagedRewardsFactory.sol:ManagedRewardsFactory"
            )
        );
        registry = deployCode(
            string.concat(
                EARN, "FactoryRegistry/contracts/factories/FactoryRegistry.sol:FactoryRegistry"
            ),
            abi.encode(factory, vrf, gaugeFactory, mrf)
        );

        ve = IEarnVe(
            _proxy(
                deployCode(string.concat(EARN, "VeBTC/contracts/VeBTC.sol:VeBTC")),
                abi.encodeWithSignature(
                    "initialize(address,address,uint256)", BTC, registry, MAX_LOCK
                )
            )
        );
        ve.initializeV2();
        voter = IEarnVoter(_newVoter());

        distributor = IEarnDistributor(
            deployCode(
                string.concat(
                    EARN, "RewardsDistributor/contracts/RewardsDistributor.sol:RewardsDistributor"
                ),
                abi.encode(address(ve))
            )
        );
        chainFee = ISplitterLike(
            deployCode(
                string.concat(
                    EARN, "ChainFeeSplitter/contracts/ChainFeeSplitter.sol:ChainFeeSplitter"
                ),
                abi.encode(address(ve), address(distributor))
            )
        );
        distributor.setDepositor(address(chainFee));
        ve.setVoterAndDistributor(address(voter), address(distributor));

        veMezo = _proxy(
            deployCode(string.concat(EARN, "VeMEZO/contracts/VeMEZO.sol:VeMEZO")),
            abi.encodeWithSignature("initialize(address,address)", MEZO, registry)
        );
        IEarnVe(veMezo).initializeV2();
        booster = _proxy(
            deployCode(
                string.concat(EARN, "BoostVoter/contracts/BoostVoter.sol:BoostVoter"),
                abi.encode(forwarder)
            ),
            abi.encodeWithSignature(
                "initialize(address,address,address)", veMezo, address(ve), registry
            )
        );
        ve.setBooster(booster);
        thirdParty = _proxy(
            deployCode(
                string.concat(
                    EARN, "ThirdPartyVoter/contracts/ThirdPartyVoter.sol:ThirdPartyVoter"
                ),
                abi.encode(forwarder)
            ),
            abi.encodeWithSignature("initialize(address,address,address)", veMezo, registry, BTC)
        );
        // Testnet passes veMEZO, veBTC here makes the splitter's token BTC
        eco = ISplitterLike(
            deployCode(
                string.concat(
                    EARN,
                    "MEZOEcosystemSplitter/contracts/",
                    "MEZOEcosystemSplitter.sol:MEZOEcosystemSplitter"
                ),
                abi.encode(address(ve), address(voter), thirdParty, uint256(90))
            )
        );
        voter.configureSplitterAndTokens(_list(address(musd)), address(eco));
        INonStakingLike(thirdParty).setSplitter(address(eco));

        gauge = voter.createVaultGauge(gaugeFactory, savings);
        fees = IEarnReward(voter.gaugeToFees(gauge));
        bribe = IEarnReward(voter.gaugeToBribe(gauge));

        ve.setTeam(team);
        IEarnVe(veMezo).setTeam(team);
        voter.setGovernor(team);
        voter.setEmergencyCouncil(team);
        INonStakingLike(booster).setSplitter(team);
        INonStakingLike(booster).setGovernor(team);
        INonStakingLike(thirdParty).setGovernor(team);
        IOwnableLike(registry).transferOwnership(team);
    }

    // A Pools Voter behind its own proxy, BTC is the emission token here
    function _newVoter() internal returns (address) {
        return _proxy(
            deployCode(
                string.concat(EARN, "Voter/contracts/Voter.sol:Voter"), abi.encode(forwarder)
            ),
            abi.encodeWithSignature(
                "initialize(address,address,address)", address(ve), registry, BTC
            )
        );
    }

    function _proxy(address implementation, bytes memory init) internal returns (address) {
        return deployCode(PROXY, abi.encode(implementation, team, init));
    }

    // The whale stakes sMUSD in the gauge and dave votes for it with a permanent lock
    function _stakeAndVote() internal {
        vm.startPrank(whale);
        musd.approve(savings, STAKED);
        ISavings(savings).deposit(STAKED);
        ISavingsAdmin(savings).approve(gauge, STAKED);
        IGaugeLike(gauge).deposit(STAKED);
        vm.stopPrank();

        vm.deal(dave, 1 ether);
        vm.startPrank(dave);
        btc.approve(address(ve), 1 ether);
        daveLock = ve.createLock(1 ether, MAX_LOCK);
        ve.lockPermanent(daveLock);
        voter.vote(daveLock, _list(savings), _one());
        vm.stopPrank();
    }

    // One week of Mezo activity at the epoch flip, the rebate period update can be held back
    function _mezoWeek(bool rebates) internal {
        vm.deal(address(chainFee), address(chainFee).balance + CHAIN_FEES);
        vm.deal(address(eco), address(eco).balance + EMISSIONS);
        _yield(WEEKLY_YIELD);
        vm.startPrank(mezoBot);
        if (rebates) chainFee.updatePeriod();
        voter.distribute(_list(gauge));
        vm.stopPrank();
    }

    // The weekly period update the RewardsDistributor waits for before any claim
    function _mezoRebates() internal {
        vm.prank(mezoBot);
        chainFee.updatePeriod();
    }

    function _newVault(uint256 period) internal returns (Vault v) {
        v = new Vault(
            btc,
            bo,
            IHintHelpers(hints),
            ISavings(savings),
            router,
            factory,
            keeper,
            guardian,
            period,
            IVoter(address(voter)),
            "Feasy BTC",
            "fBTC"
        );
    }

    // Adds liquidity at the oracle price
    function _addLiquidity(uint256 btcAmount) internal {
        uint256 musdAmount = btcAmount * _price() / 1e18;
        vm.startPrank(whale);
        btc.approve(address(router), btcAmount);
        musd.approve(address(router), musdAmount);
        IRouterLiquidity(address(router))
            .addLiquidity(
                BTC, address(musd), false, btcAmount, musdAmount, 0, 0, whale, block.timestamp
            );
        vm.stopPrank();
    }

    function _price() internal view returns (uint256) {
        return IPriceFeedView(sys.priceFeed()).fetchPrice();
    }

    function _setRate(uint16 rate) internal {
        IRateTester(sys.interestRateManager()).setInterestRateForTesting(rate);
    }

    function _depositBTC(address user, uint256 amount) internal returns (uint256 shares) {
        vm.deal(user, user.balance + amount);
        vm.prank(user);
        shares = vault.depositBTC{value: amount}(user);
    }

    // Pays sMUSD holders, the gauge and the vault among them, a protocol yield
    function _yield(uint256 amount) internal {
        vm.startPrank(whale);
        musd.approve(savings, amount);
        ISavingsAdmin(savings).receiveProtocolYield(amount);
        vm.stopPrank();
    }

    function _roll(address caller) internal returns (uint256 used) {
        vm.prank(caller);
        uint256 before = gasleft();
        vault.roll();
        used = before - gasleft();
    }

    function _epoch(uint256 k) internal pure returns (uint256) {
        return E0 + k * WEEK;
    }

    // Live rungs as (id, amount, end), in slot order
    function _rungs()
        internal
        view
        returns (uint256[] memory ids, uint256[] memory amounts, uint256[] memory ends)
    {
        uint256 n;
        for (uint256 i; i < 4; i++) {
            (uint256 id,,) = sleeve.rungs(i);
            if (id != 0) n++;
        }
        ids = new uint256[](n);
        amounts = new uint256[](n);
        ends = new uint256[](n);
        uint256 j;
        for (uint256 i; i < 4; i++) {
            (uint256 id, uint128 amount, uint64 end) = sleeve.rungs(i);
            if (id == 0) continue;
            ids[j] = id;
            amounts[j] = amount;
            ends[j] = end;
            j++;
        }
    }

    // The rung that ends at end, or zero
    function _rungAt(uint256 end) internal view returns (uint256 id, uint256 amount) {
        (uint256 rid, uint128 ramount, uint64 rend) = sleeve.rungs(end / WEEK % 4);
        if (rend == end) return (rid, ramount);
    }

    function _stuckIds(Vm.Log[] memory logs) internal view returns (uint256 n, uint256 last) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(sleeve) && logs[i].topics[0] == RUNG_STUCK) {
                n++;
                last = uint256(logs[i].topics[1]);
            }
        }
    }

    // Precompile calls of one transaction as Mezo counts them, BTC token calls plus two per price
    function _precompiles(VmSafe.AccountAccess[] memory accesses)
        internal
        view
        returns (uint256 btcCalls, uint256 oracleCalls)
    {
        address oracle = sys.aggregator();
        for (uint256 i; i < accesses.length; i++) {
            VmSafe.AccountAccessKind kind = accesses[i].kind;
            bool call = kind == VmSafe.AccountAccessKind.Call;
            if (!call && kind != VmSafe.AccountAccessKind.StaticCall) continue;
            if (accesses[i].account == BTC) btcCalls++;
            if (accesses[i].account == oracle) oracleCalls++;
        }
    }

    function _list(address a) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = a;
    }

    function _one() internal pure returns (uint256[] memory weights) {
        weights = new uint256[](1);
        weights[0] = 1;
    }
}
