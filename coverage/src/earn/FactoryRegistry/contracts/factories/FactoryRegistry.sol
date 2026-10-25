// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactoryRegistry} from "../interfaces/factories/IFactoryRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Protocol Factory Registry
/// @author Carter Carlson (@pegahcarter)
/// @notice Protocol Factory Registry to swap and create gauges
contract FactoryRegistry is IFactoryRegistry, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Factory to create free and locked rewards for a managed veNFT.
    address private _managedRewardsFactory;

    /// @dev The protocol will always have a usable poolFactory,
    ///      votingRewardsFactory, and gaugeFactory. The votingRewardsFactory
    ///      and gaugeFactory are defined to the poolFactory and the fallback
    ///      triple can never be removed.
    address public immutable fallbackPoolFactory;

    /// @dev Array of approved gauge factories.
    EnumerableSet.AddressSet private _gaugeFactories;

    /// @dev Mapping from gauge factory to its paired voting rewards factory.
    mapping(address => address) private _gaugeFactoryToVotingRewardsFactory;

    /// @dev Array of approved pool factories.
    EnumerableSet.AddressSet private _poolFactories;

    /// @dev Mapping from pool factory to its paired gauge factory.
    mapping(address => address) private _poolFactoryToGaugeFactory;

    constructor(
        address _fallbackPoolFactory,
        address _fallbackVotingRewardsFactory,
        address _fallbackGaugeFactory,
        address _newManagedRewardsFactory
    ) {
        fallbackPoolFactory = _fallbackPoolFactory;

        approveGaugeFactory(
            _fallbackGaugeFactory,
            _fallbackVotingRewardsFactory
        );
        approvePoolFactory(_fallbackPoolFactory, _fallbackGaugeFactory);

        setManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function approveGaugeFactory(
        address gaugeFactory,
        address votingRewardsFactory
    ) public onlyOwner {
        if (gaugeFactory == address(0) || votingRewardsFactory == address(0)) {
            revert ZeroAddress();
        }
        if (_gaugeFactories.contains(gaugeFactory)) {
            revert PathAlreadyApproved();
        }

        address existingVotingRewards = _gaugeFactoryToVotingRewardsFactory[
            gaugeFactory
        ];

        // If the gaugeFactory has not been approved before, can approve any votingRewards factory
        if (existingVotingRewards == address(0)) {
            _gaugeFactoryToVotingRewardsFactory[
                gaugeFactory
            ] = votingRewardsFactory;
        } else {
            // If the gaugeFactory has been approved before, can only approve the same
            // votingRewards factory to maintain state within Voter
            if (votingRewardsFactory != existingVotingRewards) {
                revert InvalidGaugeFactoryPair();
            }
        }

        _gaugeFactories.add(gaugeFactory);
        emit ApproveGaugeFactory(gaugeFactory, votingRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function approvePoolFactory(
        address poolFactory,
        address gaugeFactory
    ) public onlyOwner {
        if (poolFactory == address(0) || gaugeFactory == address(0)) {
            revert ZeroAddress();
        }
        if (_poolFactories.contains(poolFactory)) {
            revert PathAlreadyApproved();
        }
        if (!_gaugeFactories.contains(gaugeFactory)) {
            // Gauge factory needs to be approved first.
            revert PathNotApproved();
        }

        address existingGaugeFactory = _poolFactoryToGaugeFactory[poolFactory];

        // If the poolFactory has not been approved before, can assign any approved gauge factory
        if (existingGaugeFactory == address(0)) {
            _poolFactoryToGaugeFactory[poolFactory] = gaugeFactory;
        } else {
            // If the poolFactory has been approved before, can only assign the same
            // gauge factory to maintain state within Voter
            if (gaugeFactory != existingGaugeFactory) {
                revert InvalidPoolFactoryPair();
            }
        }

        _poolFactories.add(poolFactory);
        address votingRewardsFactory = _gaugeFactoryToVotingRewardsFactory[
            gaugeFactory
        ];
        emit ApprovePoolFactory(
            poolFactory,
            votingRewardsFactory,
            gaugeFactory
        );
    }

    /// @inheritdoc IFactoryRegistry
    function unapproveGaugeFactory(address gaugeFactory) external onlyOwner {
        if (!_gaugeFactories.contains(gaugeFactory)) {
            revert PathNotApproved();
        }
        if (gaugeFactory == _poolFactoryToGaugeFactory[fallbackPoolFactory]) {
            revert FallbackFactory();
        }

        _gaugeFactories.remove(gaugeFactory);
        address votingRewardsFactory = _gaugeFactoryToVotingRewardsFactory[
            gaugeFactory
        ];
        emit UnapproveGaugeFactory(gaugeFactory, votingRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function unapprovePoolFactory(address poolFactory) external onlyOwner {
        if (poolFactory == fallbackPoolFactory) revert FallbackFactory();
        if (!_poolFactories.contains(poolFactory)) revert PathNotApproved();

        _poolFactories.remove(poolFactory);
        address gaugeFactory = _poolFactoryToGaugeFactory[poolFactory];
        address votingRewardsFactory = _gaugeFactoryToVotingRewardsFactory[
            gaugeFactory
        ];
        emit UnapprovePoolFactory(
            poolFactory,
            votingRewardsFactory,
            gaugeFactory
        );
    }

    /// @inheritdoc IFactoryRegistry
    function setManagedRewardsFactory(
        address _newManagedRewardsFactory
    ) public onlyOwner {
        if (_newManagedRewardsFactory == _managedRewardsFactory)
            revert SameAddress();
        if (_newManagedRewardsFactory == address(0)) revert ZeroAddress();
        _managedRewardsFactory = _newManagedRewardsFactory;
        emit SetManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function managedRewardsFactory() external view returns (address) {
        return _managedRewardsFactory;
    }

    /// @inheritdoc IFactoryRegistry
    function factoriesToPoolFactory(
        address poolFactory
    ) public view returns (address votingRewardsFactory, address gaugeFactory) {
        gaugeFactory = _poolFactoryToGaugeFactory[poolFactory];
        votingRewardsFactory = _gaugeFactoryToVotingRewardsFactory[
            gaugeFactory
        ];
    }

    /// @inheritdoc IFactoryRegistry
    function gaugeFactoryToVotingRewardsFactory(
        address gaugeFactory
    ) external view returns (address) {
        return _gaugeFactoryToVotingRewardsFactory[gaugeFactory];
    }

    /// @inheritdoc IFactoryRegistry
    function isPoolFactoryApproved(
        address poolFactory
    ) external view returns (bool) {
        return _poolFactories.contains(poolFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function isGaugeFactoryApproved(
        address gaugeFactory
    ) external view returns (bool) {
        return _gaugeFactories.contains(gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function poolFactories() external view returns (address[] memory) {
        return _poolFactories.values();
    }

    /// @inheritdoc IFactoryRegistry
    function gaugeFactories() external view returns (address[] memory) {
        return _gaugeFactories.values();
    }

    /// @inheritdoc IFactoryRegistry
    function poolFactoriesLength() external view returns (uint256) {
        return _poolFactories.length();
    }

    /// @inheritdoc IFactoryRegistry
    function gaugeFactoriesLength() external view returns (uint256) {
        return _gaugeFactories.length();
    }
}
