// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IBaseVoter} from "../interfaces/IBaseVoter.sol";
import {VotingReward} from "./VotingReward.sol";

/// @title Bribe voting rewards
/// @notice Bribes are voting rewards denominated in voter-approved tokens,
///         that can be allocated by anyone.
contract BribeVotingReward is VotingReward {
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

        if (!isReward[token]) {
            if (!IBaseVoter(voter).isWhitelistedToken(token))
                revert NotWhitelisted();
            isReward[token] = true;
            rewards.push(token);
        }

        _notifyRewardAmount(sender, token, amount);
    }
}
