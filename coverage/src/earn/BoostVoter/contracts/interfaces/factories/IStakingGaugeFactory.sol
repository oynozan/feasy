// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IStakingGaugeFactory {
    error InvalidGaugeType();

    enum StakingGaugeType {
        Pool,
        Vault,
        NoFees
    }

    /// @notice Creates a new staking gauge of the specified type for a given entity
    /// @param _type The type of staking gauge to create
    /// @param _forwarder The address of the forwarder contract
    /// @param _entity The address of the entity to create the gauge for
    ///        The _entity is specific to the _type and the factory implementation
    ///        is responsible to handle it accordingly. For example:
    ///        - For Pool type, _entity is the address of the pool
    ///        - For Vault type, _entity is the address of the vault
    ///        - For NoFees type, _entity is the address of the staking token
    /// @param _feesVotingReward The address of the fees voting reward contract
    /// @param _rewardToken The address of the reward token
    /// @return The address of the created gauge
    function createStakingGauge(
        StakingGaugeType _type,
        address _forwarder,
        address _entity,
        address _feesVotingReward,
        address _rewardToken
    ) external returns (address);
}
