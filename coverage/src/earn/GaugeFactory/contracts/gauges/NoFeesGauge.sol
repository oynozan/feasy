// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StakingGauge} from "./StakingGauge.sol";

/// @title No Fees Gauge
/// @notice Gauge that distributes rewards (emissions) but does not distribute
///         any fees or yield to voters. Stakers receive gauge rewards but
///         voters get no fees or yield. Such gauge can be used by the governance
///         for any special partnerships or pure token incentivization campaigns.
contract NoFeesGauge is StakingGauge {
    constructor(
        address _forwarder,
        address _stakingToken,
        address _feesVotingReward,
        address _rewardToken,
        address _voter
    )
        StakingGauge(
            _forwarder,
            _stakingToken,
            _feesVotingReward,
            _rewardToken,
            _voter
        )
    {}

    function _claimFees() internal override {}
}
