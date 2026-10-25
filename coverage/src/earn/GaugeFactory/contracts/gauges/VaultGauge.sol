// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StakingGauge} from "./StakingGauge.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IVaultGauge} from "../interfaces/IVaultGauge.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Vault Gauge
/// @notice Gauge associated with a vault. The vault generates yield claimable
///         by voters. Vault depositors who staked their vault receipt tokens in
///         the gauge receive gauge rewards.
contract VaultGauge is IVaultGauge, StakingGauge {
    using SafeERC20 for IERC20;

    /// @inheritdoc IVaultGauge
    uint256 public fees;

    constructor(
        address _forwarder,
        address _vault,
        address _feesVotingReward,
        address _rewardToken,
        address _voter
    )
        StakingGauge(
            _forwarder,
            _vault,
            _feesVotingReward,
            _rewardToken,
            _voter
        )
    {}

    function _claimFees() internal override {
        uint256 claimed = IVault(stakingToken).claimYield();

        if (claimed > 0) {
            uint256 _fees = fees + claimed;
            address feeToken = IVault(stakingToken).yieldToken();

            // At least 1 token unit per second of the epoch.
            if (_fees > DURATION) {
                fees = 0;
                IERC20(feeToken).safeApprove(feesVotingReward, _fees);
                IReward(feesVotingReward).notifyRewardAmount(feeToken, _fees);
            } else {
                fees = _fees;
            }

            emit ClaimFees(_msgSender(), claimed);
        }
    }
}
