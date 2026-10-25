// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*
 * Mezo's own contracts, deployed and wired the way staging/script/DeployStaging.s.sol
 * puts them on Mezo testnet. MUSD (mezo-org/musd) runs with the repo's MockAggregator
 * and InterestRateManagerTester hooks next to the tigris v2 pool, factory and router.
 * The savings vault compiles with 0.8.33, so the test base deploys it.
 */

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
import {Pool} from "tigris/Pool.sol";
import {Router} from "tigris/Router.sol";
import {PoolFactory} from "tigris/factories/PoolFactory.sol";
import {FactoryRegistry} from "tigris/factories/FactoryRegistry.sol";
import {VotingRewardsFactory} from "tigris/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "tigris/factories/GaugeFactory.sol";
import {ManagedRewardsFactory} from "tigris/factories/ManagedRewardsFactory.sol";
import {MezoForwarder} from "tigris/forwarder/MezoForwarder.sol";

contract MezoSystem {
    uint256 constant GOVERNANCE_DELAY = 7200;

    address immutable creator;

    ActivePool public activePool;
    BorrowerOperations public borrowerOperations;
    BorrowerOperationsSignatures signatures;
    CollSurplusPool public collSurplusPool;
    DefaultPool public defaultPool;
    GasPool gasPool;
    GovernableVariables governableVariables;
    HintHelpers public hintHelpers;
    PCV public pcv;
    PriceFeed public priceFeed;
    SortedTroves public sortedTroves;
    StabilityPool public stabilityPool;
    TroveManager public troveManager;
    InterestRateManagerTester public interestRateManager;
    MockAggregator public aggregator;
    MUSD public musd;
    PoolFactory public poolFactory;
    Router public router;

    constructor() {
        creator = msg.sender;
        _deploy();
        _wire();
        _dex();
    }

    // The test acts as governance of every contract this one owns
    function exec(address target, bytes calldata data) external payable returns (bytes memory) {
        require(msg.sender == creator, "not creator");
        (bool ok, bytes memory out) = target.call{value: msg.value}(data);
        if (!ok) {
            assembly {
                revert(add(out, 32), mload(out))
            }
        }
        return out;
    }

    // Wires the savings vault in once the test deployed it, as DeployStaging._start does
    function start(uint256 price, address savings) external {
        require(msg.sender == creator, "not creator");
        aggregator.setPrice(price);
        pcv.initializeDebt();
        pcv.setFeeRecipient(savings);
        pcv.setFeeSplit(50);
    }

    function _deploy() internal {
        bytes memory init = abi.encodeCall(ActivePool.initialize, ());
        interestRateManager = InterestRateManagerTester(
            _proxy(
                address(new InterestRateManagerTester()),
                abi.encodeCall(InterestRateManager.initialize, ())
            )
        );
        borrowerOperations = BorrowerOperations(_proxy(address(new BorrowerOperations()), init));
        troveManager = TroveManager(_proxy(address(new TroveManager()), init));
        stabilityPool = StabilityPool(payable(_proxy(address(new StabilityPool()), init)));
        musd = new MUSD();
        aggregator = new MockAggregator(18);
        collSurplusPool = CollSurplusPool(payable(_proxy(address(new CollSurplusPool()), init)));
        activePool = ActivePool(payable(_proxy(address(new ActivePool()), init)));
        defaultPool = DefaultPool(payable(_proxy(address(new DefaultPool()), init)));
        pcv = PCV(
            payable(_proxy(address(new PCV()), abi.encodeCall(PCV.initialize, (GOVERNANCE_DELAY))))
        );
        pcv.initializeV2();
        sortedTroves = SortedTroves(_proxy(address(new SortedTroves()), init));
        gasPool = GasPool(_proxy(address(new GasPool()), init));
        priceFeed = PriceFeed(_proxy(address(new PriceFeed()), init));
        hintHelpers = HintHelpers(_proxy(address(new HintHelpers()), init));
        signatures =
            BorrowerOperationsSignatures(_proxy(address(new BorrowerOperationsSignatures()), init));
        governableVariables = GovernableVariables(
            _proxy(
                address(new GovernableVariables()),
                abi.encodeCall(GovernableVariables.initialize, (GOVERNANCE_DELAY))
            )
        );
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
            address(activePool),
            address(borrowerOperations),
            address(musd),
            address(pcv),
            address(troveManager)
        );
        stabilityPool.setAddresses(
            address(activePool),
            address(borrowerOperations),
            address(musd),
            address(priceFeed),
            address(sortedTroves),
            address(troveManager)
        );
        hintHelpers.setAddresses(
            address(borrowerOperations), address(sortedTroves), address(troveManager)
        );
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
        collSurplusPool.setAddresses(
            address(activePool), address(borrowerOperations), address(troveManager)
        );
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
        sortedTroves.setParams(
            type(uint256).max, address(borrowerOperations), address(troveManager)
        );
        musd.initialize(
            address(troveManager),
            address(stabilityPool),
            address(borrowerOperations),
            address(interestRateManager)
        );
    }

    function _dex() internal {
        poolFactory = new PoolFactory(address(new Pool()));
        FactoryRegistry registry = new FactoryRegistry(
            address(poolFactory),
            address(new VotingRewardsFactory()),
            address(new GaugeFactory()),
            address(new ManagedRewardsFactory())
        );
        router = new Router(address(new MezoForwarder()), address(registry), address(poolFactory));
    }

    function _proxy(address implementation, bytes memory init) internal returns (address) {
        return address(new ERC1967Proxy(implementation, init));
    }
}
