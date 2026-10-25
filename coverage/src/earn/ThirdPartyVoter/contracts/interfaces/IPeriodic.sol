// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPeriodic
/// @notice Interface describing traits of contracts that need to execute periodic actions.
interface IPeriodic {
    /// @notice Processes periodic actions. Callable once per epoch.
    /// @return _period Start of current epoch.
    function updatePeriod() external returns (uint256 _period);

    /// @notice Timestamp of start of epoch that updatePeriod was last called in.
    function activePeriod() external view returns (uint256);
}
