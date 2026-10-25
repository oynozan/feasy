// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IPoolGauge} from "../interfaces/IPoolGauge.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IPool} from "../interfaces/IPool.sol";
import {StakingGauge} from "./StakingGauge.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Pool Gauge
/// @author veldorome.finance, @figs999, @pegahcarter
/// @notice Gauge associated with a pool. The pool generates trading fees
///         claimable by voters. LPs who staked their pool receipt tokens in the
///         gauge receive gauge rewards.
contract PoolGauge is IPoolGauge, StakingGauge {
    using SafeERC20 for IERC20;

    /// @inheritdoc IPoolGauge
    uint256 public fees0;

    /// @inheritdoc IPoolGauge
    uint256 public fees1;

    constructor(
        address _forwarder,
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        address _voter
    )
        StakingGauge(_forwarder, _pool, _feesVotingReward, _rewardToken, _voter)
    {}

    function _claimFees() internal override {
        (uint256 claimed0, uint256 claimed1) = IPool(stakingToken).claimFees();
        if (claimed0 > 0 || claimed1 > 0) {
            uint256 _fees0 = fees0 + claimed0;
            uint256 _fees1 = fees1 + claimed1;
            (address _token0, address _token1) = IPool(stakingToken).tokens();
            if (_fees0 > DURATION) {
                fees0 = 0;
                IERC20(_token0).safeApprove(feesVotingReward, _fees0);
                IReward(feesVotingReward).notifyRewardAmount(_token0, _fees0);
            } else {
                fees0 = _fees0;
            }
            if (_fees1 > DURATION) {
                fees1 = 0;
                IERC20(_token1).safeApprove(feesVotingReward, _fees1);
                IReward(feesVotingReward).notifyRewardAmount(_token1, _fees1);
            } else {
                fees1 = _fees1;
            }

            emit ClaimFees(_msgSender(), claimed0, claimed1);
        }
    }
}
