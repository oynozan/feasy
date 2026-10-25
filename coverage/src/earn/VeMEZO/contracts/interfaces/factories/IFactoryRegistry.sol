// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IFactoryRegistry {
    error FallbackFactory();
    error InvalidPoolFactoryPair();
    error InvalidGaugeFactoryPair();
    error PathAlreadyApproved();
    error PathNotApproved();
    error SameAddress();
    error ZeroAddress();

    event ApprovePoolFactory(
        address indexed poolFactory,
        address indexed votingRewardsFactory,
        address indexed gaugeFactory
    );
    event UnapprovePoolFactory(
        address indexed poolFactory,
        address indexed votingRewardsFactory,
        address indexed gaugeFactory
    );
    event ApproveGaugeFactory(
        address indexed gaugeFactory,
        address indexed votingRewardsFactory
    );
    event UnapproveGaugeFactory(
        address indexed gaugeFactory,
        address indexed votingRewardsFactory
    );
    event SetManagedRewardsFactory(address indexed _newRewardsFactory);

    /// @notice Approve a gauge factory paired with a voting rewards factory.
    ///         This creates the fundamental pairing that can be used for both
    ///         pool and vault gauge creation.
    ///         Cannot approve address(0) factories.
    ///         Once a pairing is established, it cannot be changed.
    /// @dev Callable by onlyOwner
    /// @param gaugeFactory Address of the unified gauge factory (supports both pool and vault gauges)
    /// @param votingRewardsFactory Address of the voting rewards factory to pair with
    function approveGaugeFactory(
        address gaugeFactory,
        address votingRewardsFactory
    ) external;

    /// @notice Approve a pool factory to use a specific gauge factory + voting rewards factory pair.
    ///         The gauge factory + voting rewards factory pair must already be approved.
    ///         Router.sol is able to swap with any poolFactories currently approved.
    ///         Cannot approve address(0) factories.
    ///         Each poolFactory has one unique set and maintains state.
    ///         Once a pool factory is paired, it cannot be changed.
    /// @dev Callable by onlyOwner
    /// @param poolFactory Address of the pool factory
    /// @param gaugeFactory Address of the approved gauge factory to use for this pool factory
    function approvePoolFactory(
        address poolFactory,
        address gaugeFactory
    ) external;

    /// @notice Unapprove a gauge factory. Note it does not unapprove pool
    ///         factories linking to the gauge factory. As a result, Router.sol
    ///         will still be able to swap with those pools. If you want to
    ///         unapprove pool factory as well, an extra call to
    ///         unapprovePoolFactory is required.
    ///         Cannot unapprove a gauge factory that is not approved.
    ///         Cannot unapprove the gauge factory from the fallback path.
    /// @dev Callable by onlyOwner
    /// @param gaugeFactory Address of the gauge factory to unapprove
    function unapproveGaugeFactory(address gaugeFactory) external;

    /// @notice Unapprove a pool factory. Note it does not unapprove the
    ///         associated gauge factory. If you want to unapprove gauge factory
    ///         as well, an extra call to unapproveGaugeFactory is required.
    ///         While a poolFactory is unapproved, Router.sol cannot swap with
    ///         pools made from the corresponding factory.
    ///         Can only unapprove an approved path.
    ///         Cannot unapprove the fallback path (core v2 factories).
    /// @dev Callable by onlyOwner
    /// @param poolFactory Address of the pool factory to unapprove
    function unapprovePoolFactory(address poolFactory) external;

    /// @notice Factory to create free and locked rewards for a managed veNFT
    function managedRewardsFactory() external view returns (address);

    /// @notice Set the rewards factory address
    /// @dev Callable by onlyOwner
    /// @param _newManagedRewardsFactory address of new managedRewardsFactory
    function setManagedRewardsFactory(
        address _newManagedRewardsFactory
    ) external;

    /// @notice Get the gauge factory and voting rewards factory associated with
    ///         a pool factory.
    ///         Once set, this can never be modified.
    ///         Returns the correlated factories even after an approved
    ///         poolFactory is unapproved.
    /// @param poolFactory Address of the pool factory
    /// @return votingRewardsFactory Address of the paired voting rewards factory
    /// @return gaugeFactory Address of the paired gauge factory
    function factoriesToPoolFactory(
        address poolFactory
    )
        external
        view
        returns (address votingRewardsFactory, address gaugeFactory);

    /// @notice Get the voting rewards factory paired with a gauge factory.
    ///         Once set, this can never be modified.
    ///         Returns the correlated factory even after an approved
    ///         gaugeFactory is unapproved.
    /// @param gaugeFactory Address of the gauge factory
    /// @return votingRewardsFactory Address of the paired voting rewards factory
    function gaugeFactoryToVotingRewardsFactory(
        address gaugeFactory
    ) external view returns (address votingRewardsFactory);

    /// @notice Get all PoolFactories approved by the registry
    /// @dev The same PoolFactory address cannot be used twice
    /// @return Array of PoolFactory addresses
    function poolFactories() external view returns (address[] memory);

    /// @notice Get all GaugeFactories approved by the registry
    /// @dev The same GaugeFactory address cannot be used twice
    /// @return Array of GaugeFactory addresses
    function gaugeFactories() external view returns (address[] memory);

    /// @notice Check if a PoolFactory is approved within the factory registry.
    ///         Router uses this method to ensure a pool swapped from is approved.
    /// @param poolFactory Address of the pool factory
    /// @return True if PoolFactory is approved, else false
    function isPoolFactoryApproved(
        address poolFactory
    ) external view returns (bool);

    /// @notice Check if a gauge factory is approved within the factory registry.
    /// @param gaugeFactory Address of the gauge factory to check
    /// @return True if gauge factory is approved, else false
    function isGaugeFactoryApproved(
        address gaugeFactory
    ) external view returns (bool);

    /// @notice Get the length of the poolFactories array
    function poolFactoriesLength() external view returns (uint256);

    /// @notice Get the length of the gaugeFactories array
    function gaugeFactoriesLength() external view returns (uint256);
}
