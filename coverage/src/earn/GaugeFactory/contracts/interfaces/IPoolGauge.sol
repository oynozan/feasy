// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IStakingGauge} from "./IStakingGauge.sol";

/// @notice Interface for a gauge associated with a pool. The pool generates
///         trading fees claimable by voters. LPs who staked their pool receipt
///         tokens in the gauge receive gauge rewards.
interface IPoolGauge is IStakingGauge {
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);

    /// @notice Cached amount of fees generated from the Pool linked to the
    ///         Gauge of token0
    function fees0() external view returns (uint256);

    /// @notice Cached amount of fees generated from the Pool linked to the
    ///         Gauge of token1
    function fees1() external view returns (uint256);
}
