// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*
 * Deploys a private copy of Mezo's MUSD system on Mezo testnet.
 *
 * The contracts are the live ones (mezo-org/musd at de1ec2af), behind proxies
 * and wired in the order of the repo's own deploy scripts. Two test hooks come
 * from the same repo, as on Mezo's matsnet_fuzz network: MockAggregator is the
 * price source and InterestRateManagerTester changes the rate without the
 * 7 day governance delay. The savings vault is the verified MUSDSavingsRate
 * source, and PCV sends it 50% of fees exactly like mainnet.
 */

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ActivePool} from "musd/ActivePool.sol";
import {BorrowerOperations} from "musd/BorrowerOperations.sol";
import {BorrowerOperationsSignatures} from "musd/BorrowerOperationsSignatures.sol";
import {CollSurplusPool} from "musd/CollSurplusPool.sol";
import {DefaultPool} from "musd/DefaultPool.sol";
import {GasPool} from "musd/GasPool.sol";
import {GovernableVariables} from "musd/GovernableVariables.sol";
import {HintHelpers} from "musd/HintHelpers.sol";
import {PCV} from "musd/PCV.sol";
import {PriceFeed} from "musd/PriceFeed.sol";
import {SortedTroves} from "musd/SortedTroves.sol";
import {StabilityPool} from "musd/StabilityPool.sol";
import {TroveManager} from "musd/TroveManager.sol";
import {InterestRateManager} from "musd/InterestRateManager.sol";
import {InterestRateManagerTester} from "musd/tests/InterestRateManagerTester.sol";
import {MockAggregator} from "musd/tests/MockAggregator.sol";
import {MUSD} from "musd/token/MUSD.sol";

interface ISavingsAdmin {
    function initialize(address musdToken) external;
    function setPCV(address pcv) external;
}

contract DeployStaging is Script {
    // A high BTC price lets small testnet balances back loans above the 1,800 MUSD minimum
    uint256 constant START_PRICE = 1_000_000e18;
    uint256 constant GOVERNANCE_DELAY = 7200;

    ActivePool activePool;
    BorrowerOperations borrowerOperations;
    BorrowerOperationsSignatures signatures;
    CollSurplusPool collSurplusPool;
    DefaultPool defaultPool;
    GasPool gasPool;
    GovernableVariables governableVariables;
    HintHelpers hintHelpers;
    PCV pcv;
    PriceFeed priceFeed;
    SortedTroves sortedTroves;
    StabilityPool stabilityPool;
    TroveManager troveManager;
    InterestRateManagerTester interestRateManager;
    MockAggregator aggregator;
    MUSD musd;
    address savings;

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        _deploy();
        _wire();
        _start();
        vm.stopBroadcast();
        _save();
    }

    function _deploy() internal {
        bytes memory init = abi.encodeCall(ActivePool.initialize, ());
        interestRateManager = InterestRateManagerTester(
            _proxy(address(new InterestRateManagerTester()), abi.encodeCall(InterestRateManager.initialize, ()))
        );
        borrowerOperations = BorrowerOperations(_proxy(address(new BorrowerOperations()), init));
        troveManager = TroveManager(_proxy(address(new TroveManager()), init));
        stabilityPool = StabilityPool(payable(_proxy(address(new StabilityPool()), init)));
        musd = new MUSD();
        aggregator = new MockAggregator(18);
        collSurplusPool = CollSurplusPool(payable(_proxy(address(new CollSurplusPool()), init)));
        activePool = ActivePool(payable(_proxy(address(new ActivePool()), init)));
        defaultPool = DefaultPool(payable(_proxy(address(new DefaultPool()), init)));
        pcv = PCV(payable(_proxy(address(new PCV()), abi.encodeCall(PCV.initialize, (GOVERNANCE_DELAY)))));
        pcv.initializeV2();
        sortedTroves = SortedTroves(_proxy(address(new SortedTroves()), init));
        gasPool = GasPool(_proxy(address(new GasPool()), init));
        priceFeed = PriceFeed(_proxy(address(new PriceFeed()), init));
        hintHelpers = HintHelpers(_proxy(address(new HintHelpers()), init));
        signatures = BorrowerOperationsSignatures(_proxy(address(new BorrowerOperationsSignatures()), init));
        governableVariables = GovernableVariables(
            _proxy(address(new GovernableVariables()), abi.encodeCall(GovernableVariables.initialize, (GOVERNANCE_DELAY)))
        );
        address savingsImpl =
            deployCode("src/savings/contracts/vaults/MUSDSavingsRate.sol:MUSDSavingsRate", abi.encode(address(0xdEaD)));
        savings = _proxy(savingsImpl, abi.encodeCall(ISavingsAdmin.initialize, (address(musd))));
    }

    function _wire() internal {
        signatures.setAddresses(
            address(activePool),
            address(borrowerOperations),
            address(collSurplusPool),
            address(defaultPool),
            address(interestRateManager),
            address(stabilityPool)
        );
        priceFeed.setOracle(address(aggregator));
        interestRateManager.setAddresses(
            address(activePool), address(borrowerOperations), address(musd), address(pcv), address(troveManager)
        );
        stabilityPool.setAddresses(
            address(activePool),
            address(borrowerOperations),
            address(musd),
            address(priceFeed),
            address(sortedTroves),
            address(troveManager)
        );
        hintHelpers.setAddresses(address(borrowerOperations), address(sortedTroves), address(troveManager));
        pcv.setAddresses(address(borrowerOperations), address(musd));
        defaultPool.setAddresses(address(activePool), address(troveManager));
        activePool.setAddresses(
            address(borrowerOperations),
            address(collSurplusPool),
            address(defaultPool),
            address(interestRateManager),
            address(stabilityPool),
            address(troveManager)
        );
        borrowerOperations.setAddresses(
            [
                address(activePool),
                address(signatures),
                address(collSurplusPool),
                address(defaultPool),
                address(gasPool),
                address(governableVariables),
                address(interestRateManager),
                address(musd),
                address(pcv),
                address(priceFeed),
                address(sortedTroves),
                address(stabilityPool),
                address(troveManager)
            ]
        );
        collSurplusPool.setAddresses(address(activePool), address(borrowerOperations), address(troveManager));
        troveManager.setAddresses(
            address(activePool),
            address(borrowerOperations),
            address(collSurplusPool),
            address(defaultPool),
            address(gasPool),
            address(interestRateManager),
            address(musd),
            address(pcv),
            address(priceFeed),
            address(sortedTroves),
            address(stabilityPool)
        );
        gasPool.setAddresses(address(musd), address(troveManager));
        sortedTroves.setParams(type(uint256).max, address(borrowerOperations), address(troveManager));
        musd.initialize(
            address(troveManager), address(stabilityPool), address(borrowerOperations), address(interestRateManager)
        );
    }

    function _start() internal {
        aggregator.setPrice(START_PRICE);
        pcv.initializeDebt();
        ISavingsAdmin(savings).setPCV(address(pcv));
        pcv.setFeeRecipient(savings);
        pcv.setFeeSplit(50);
    }

    function _proxy(address implementation, bytes memory init) internal returns (address) {
        return address(new ERC1967Proxy(implementation, init));
    }

    function _save() internal {
        string memory out = string.concat(
            "STAGING_BORROWER_OPS=", vm.toString(address(borrowerOperations)), "\n",
            "STAGING_TROVE_MANAGER=", vm.toString(address(troveManager)), "\n",
            "STAGING_HINT_HELPERS=", vm.toString(address(hintHelpers)), "\n",
            "STAGING_SORTED_TROVES=", vm.toString(address(sortedTroves)), "\n",
            "STAGING_PRICE_FEED=", vm.toString(address(priceFeed)), "\n",
            "STAGING_AGGREGATOR=", vm.toString(address(aggregator)), "\n",
            "STAGING_RATE_MANAGER=", vm.toString(address(interestRateManager)), "\n",
            "STAGING_MUSD=", vm.toString(address(musd)), "\n",
            "STAGING_PCV=", vm.toString(address(pcv)), "\n",
            "STAGING_STABILITY_POOL=", vm.toString(address(stabilityPool)), "\n",
            "STAGING_SMUSD=", vm.toString(savings), "\n"
        );
        vm.writeFile("../deployments/staging.env", out);
    }
}
