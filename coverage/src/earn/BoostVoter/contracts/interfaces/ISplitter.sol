// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IPeriodic} from "./IPeriodic.sol";

interface ISplitter is IPeriodic {
    error AlreadyNudged();
    error NotEpochGovernor();

    event Nudge(uint256 indexed _period, uint256 _oldRate, uint256 _newRate);

    /// @notice Allows epoch governor to modify the splitter by at most 1 basis
    ///         tick per epoch on a scale to a maximum of 100 or to a minimum of 1.
    /// @dev Throws if not epoch governor.
    ///      Throws if already nudged this epoch.
    ///      Throws if nudging above maximum rate.
    ///      Throws if nudging below minimum rate.
    ///      This contract is coupled to EpochGovernor as it requires three option
    ///      simple majority voting.
    function nudge() external;
}
