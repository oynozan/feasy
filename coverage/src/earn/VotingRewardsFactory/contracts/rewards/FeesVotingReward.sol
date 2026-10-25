// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VotingReward} from "./VotingReward.sol";
import {IVoter} from "../interfaces/IVoter.sol";

/// @title Fees voting rewards
/// @notice Fees are voting rewards denominated in various tokens,
///         that can be allocated by the pools/vaults gauges. The gauges
///         fund the allocations by claiming the yield from their pools/vaults,
///         based on staked receipt tokens.
contract FeesVotingReward is VotingReward {
    constructor(
        address _forwarder,
        address _voter,
        address[] memory _rewards
    ) VotingReward(_forwarder, _voter, _rewards) {}

    /// @inheritdoc VotingReward
    function notifyRewardAmount(
        address token,
        uint256 amount
    ) external override nonReentrant {
        address sender = _msgSender();
        if (IVoter(voter).gaugeToFees(sender) != address(this))
            revert NotGauge();
        if (!isReward[token]) revert InvalidReward();

        _notifyRewardAmount(sender, token, amount);
    }
}
