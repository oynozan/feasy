// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGaugeFactory} from "../interfaces/factories/IGaugeFactory.sol";
import {PoolGauge} from "../gauges/PoolGauge.sol";
import {VaultGauge} from "../gauges/VaultGauge.sol";
import {NoFeesGauge} from "../gauges/NoFeesGauge.sol";
import {NonStakingGauge} from "../gauges/NonStakingGauge.sol";

contract GaugeFactory is IGaugeFactory {
    function createStakingGauge(
        StakingGaugeType _type,
        address _forwarder,
        address _stakingToken,
        address _feesVotingReward,
        address _rewardToken
    ) external returns (address gauge) {
        if (_type == StakingGaugeType.Pool) {
            gauge = address(
                new PoolGauge(
                    _forwarder,
                    _stakingToken,
                    _feesVotingReward,
                    _rewardToken,
                    msg.sender
                )
            );
        } else if (_type == StakingGaugeType.Vault) {
            gauge = address(
                new VaultGauge(
                    _forwarder,
                    _stakingToken,
                    _feesVotingReward,
                    _rewardToken,
                    msg.sender
                )
            );
        } else if (_type == StakingGaugeType.NoFees) {
            gauge = address(
                new NoFeesGauge(
                    _forwarder,
                    _stakingToken,
                    _feesVotingReward,
                    _rewardToken,
                    msg.sender
                )
            );
        } else {
            revert InvalidGaugeType();
        }
    }

    function createNonStakingGauge(
        address _forwarder,
        address _rewardToken,
        address _rewardsBeneficiary
    ) external returns (address gauge) {
        gauge = address(
            new NonStakingGauge(
                _forwarder,
                _rewardToken,
                msg.sender,
                _rewardsBeneficiary
            )
        );
    }
}
