// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "vault/Vault.sol";
import {RedeemQueue} from "vault/RedeemQueue.sol";
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
    function stabilityPool() external view returns (address);
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
    function setBlockTime(uint256 time) external;
}

interface IRateTester {
    function setInterestRateForTesting(uint16 rate) external;
}

interface ILiquidations {
    function liquidate(address borrower) external;
    function redeemCollateral(
        uint256 amount,
        address firstHint,
        address upperHint,
        address lowerHint,
        uint256 partialNICR,
        uint256 maxIterations
    ) external;
}

interface IStabilityPool {
    function provideToSP(uint256 amount) external;
}

interface IPoolAdmin {
    function createPool(address tokenA, address tokenB, bool stable) external returns (address);
    function setPauseState(bool state) external;
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
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
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256, uint256);
}

interface ISavingsAdmin {
    function initialize(address musd) external;
    function setPCV(address pcv) external;
    function receiveProtocolYield(uint256 amount) external;
}

contract Base is Test {
    address constant BTC = 0x7b7C000000000000000000000000000000000000;
    uint256 constant PRICE = 100_000e18;
    uint256 constant GAS_COMP = 200e18;

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

    address whale = makeAddr("whale");
    address keeper = makeAddr("keeper");
    address guardian = makeAddr("guardian");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        vm.etch(BTC, address(new Btc()).code);
        sys = IMezoSystem(deployCode("MezoSystem.sol:MezoSystem"));
        bo = IBorrowerOperations(sys.borrowerOperations());
        tm = ITroveManager(sys.troveManager());
        musd = IERC20(sys.musd());
        router = IRouter(sys.router());
        hints = sys.hintHelpers();
        factory = sys.poolFactory();

        address impl =
            deployCode("MUSDSavingsRate.sol:MUSDSavingsRate", abi.encode(address(0xdEaD)));
        savings = address(
            new ERC1967Proxy(impl, abi.encodeCall(ISavingsAdmin.initialize, (address(musd))))
        );
        ISavingsAdmin(savings).setPCV(sys.pcv());
        sys.start(PRICE, savings);

        _seed();

        vault = _newVault(7 days);
        queue = vault.queue();
        vault.setBorrowingEnabled(true);
    }

    // The whale keeps the vault trove from ever being the last one and seeds the pool
    function _seed() internal virtual {
        vm.deal(whale, 1000 ether);
        vm.prank(whale);
        bo.openTrove{value: 100 ether}(2_000_000e18, address(0), address(0));
        pool = IPoolAdmin(factory).createPool(BTC, address(musd), false);
        _addLiquidity(10 ether);
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
            IVoter(address(0)),
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

    function _setPrice(uint256 price) internal {
        sys.exec(sys.aggregator(), abi.encodeCall(IAggregator.setPrice, (price)));
    }

    function _setRate(uint16 rate) internal {
        IRateTester(sys.interestRateManager()).setInterestRateForTesting(rate);
    }

    function _pause(bool paused) internal {
        sys.exec(sys.poolFactory(), abi.encodeCall(IPoolAdmin.setPauseState, (paused)));
    }

    function _depositBTC(address user, uint256 amount) internal returns (uint256 shares) {
        vm.deal(user, user.balance + amount);
        vm.prank(user);
        shares = vault.depositBTC{value: amount}(user);
    }

    // Pays sMUSD holders, the vault among them, a protocol yield
    function _yield(uint256 amount) internal {
        vm.startPrank(whale);
        musd.approve(savings, amount);
        ISavingsAdmin(savings).receiveProtocolYield(amount);
        vm.stopPrank();
    }

    function _ratio() internal view returns (uint256) {
        Vault.Trove memory t = vault.trove();
        return t.coll * _price() / t.debt;
    }

    // Opens a plain borrower trove at ratio, for a crowded sorted list or a weak system
    function _borrower(address user, uint256 coll, uint256 ratio) internal {
        uint256 debt = coll * _price() / ratio;
        uint256 amount = (debt - GAS_COMP) * 1e18 / (1e18 + bo.borrowingRate());
        vm.deal(user, user.balance + coll);
        vm.prank(user);
        bo.openTrove{value: coll}(amount, address(0), address(0));
    }

    // Redeems the vault's whole loan, which closes its trove and leaves surplus collateral
    function _redeemVault() internal {
        Vault.Trove memory t = vault.trove();
        vm.prank(whale);
        ILiquidations(address(tm))
            .redeemCollateral(t.debt - GAS_COMP, address(vault), address(0), address(0), 0, 1);
    }
}

interface IPriceFeedView {
    function fetchPrice() external view returns (uint256);
}
