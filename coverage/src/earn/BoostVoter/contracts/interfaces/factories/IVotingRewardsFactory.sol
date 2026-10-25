// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IVotingRewardsFactory {
    /// @notice Creates a BribeVotingReward and a FeesVotingReward contract for a gauge
    /// @param _forwarder Address of trusted forwarder
    /// @param _rewards Addresses of pool tokens to be used as valid rewards tokens
    /// @return feesVotingReward Address of FeesVotingReward contract created
    /// @return bribeVotingReward Address of BribeVotingReward contract created
    function createRewards(
        address _forwarder,
        address[] memory _rewards
    ) external returns (address feesVotingReward, address bribeVotingReward);

    /// @notice Creates a BribeVotingReward contract for a gauge
    /// @param _forwarder Address of trusted forwarder
    /// @param _rewards Addresses of pool tokens to be used as valid rewards tokens
    /// @return bribeVotingReward Address of BribeVotingReward contract created
    function createBribeReward(
        address _forwarder,
        address[] memory _rewards
    ) external returns (address bribeVotingReward);
}
