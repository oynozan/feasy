// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IGaugeFactory {
    error InvalidGaugeType();

    enum StakingGaugeType {
        Pool,
        Vault,
        NoFees
    }

    function createStakingGauge(
        StakingGaugeType _type,
        address _forwarder,
        address _stakingToken,
        address _feesVotingReward,
        address _rewardToken
    ) external returns (address);

    function createNonStakingGauge(
        address _forwarder,
        address _rewardToken,
        address _rewardsBeneficiary
    ) external returns (address);
}
