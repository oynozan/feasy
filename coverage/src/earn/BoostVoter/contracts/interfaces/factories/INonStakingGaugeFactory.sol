// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface INonStakingGaugeFactory {
    function createNonStakingGauge(
        address _forwarder,
        address _rewardToken,
        address _rewardsBeneficiary
    ) external returns (address);
}
