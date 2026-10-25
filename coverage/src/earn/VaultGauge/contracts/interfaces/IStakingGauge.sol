// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGauge} from "./IGauge.sol";

interface IStakingGauge is IGauge {
    error NotAlive();
    error NotTeam();

    event Deposit(address indexed from, address indexed to, uint256 amount);
    event Withdraw(address indexed from, uint256 amount);

    /// @notice Address of the pool LP token which is deposited (staked) for rewards
    function stakingToken() external view returns (address);

    /// @notice Address of the FeesVotingReward contract linked to the gauge
    function feesVotingReward() external view returns (address);

    /// @notice Deposit LP tokens into gauge for msg.sender
    /// @param _amount .
    function deposit(uint256 _amount) external;

    /// @notice Deposit LP tokens into gauge for any user
    /// @param _amount .
    /// @param _recipient Recipient to give balance to
    function deposit(uint256 _amount, address _recipient) external;

    /// @notice Withdraw LP tokens for user
    /// @param _amount .
    function withdraw(uint256 _amount) external;

    /// @dev Notifies gauge of gauge rewards without distributing its fees.
    ///      Assumes gauge reward tokens is 18 decimals.
    ///      If not 18 decimals, rewardRate may have rounding issues.
    function notifyRewardWithoutClaim(uint256 amount) external;
}
