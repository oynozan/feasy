// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IEpochGovernor} from "./interfaces/IEpochGovernor.sol";
import {ISplitter} from "./interfaces/ISplitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

/// @title Splitter
/// @notice An abstract contract for tokens splitting between addresses defined
///         in the implementation contract. Amount of the split tokens depends on
///         the current position of the gauge needle that can be moved each epoch
///         by the Epoch Governor.
abstract contract Splitter is ISplitter {
    using SafeERC20 for IERC20;

    /// @notice Token for fee distribution.
    IERC20 public immutable token;

    /// @notice The maximum value of the gauge needle.
    uint256 public constant MAXIMUM_GAUGE_SCALE = 100;

    /// @notice The minimum value of the gauge needle.
    uint256 public constant MINIMUM_GAUGE_SCALE = 1;

    /// @notice Duration of epoch.
    uint256 public constant WEEK = 1 weeks;

    /// @notice Needle tick change per proposal.
    uint256 public constant TICK = 1;

    /// @notice Start time of currently active epoch.
    uint256 public activePeriod;

    /// @notice The current position of the gauge needle.
    uint256 public needle;

    /// @dev activePeriod => proposal existing, used to enforce one proposal per epoch.
    mapping(uint256 => bool) public proposals;

    /// @dev Emitted when the epoch period is updated.
    event PeriodUpdated(
        uint256 oldPeriod,
        uint256 newPeriod,
        uint256 firstRecipientAmount,
        uint256 secondRecipientAmount
    );

    /// @notice Constructor to set up the fee splitter.
    constructor(address _ve) {
        token = IERC20(IVotingEscrow(_ve).token());
    }

    /// @notice Moves the gauge needle by 1 tick per epoch.
    function nudge() external virtual {
        address _epochGovernor = this.epochGovernor();
        if (msg.sender != _epochGovernor) revert NotEpochGovernor();

        uint256 period = activePeriod;
        if (proposals[period]) revert AlreadyNudged();

        IEpochGovernor.ProposalState state = IEpochGovernor(_epochGovernor)
            .result();

        uint256 oldNeedle = needle;
        if (state != IEpochGovernor.ProposalState.Expired) {
            // move the needle up by 1 tick
            if (state == IEpochGovernor.ProposalState.Succeeded) {
                needle = oldNeedle + TICK > MAXIMUM_GAUGE_SCALE
                    ? MAXIMUM_GAUGE_SCALE
                    : needle + TICK;
            } else {
                // move the needle down by 1 tick
                needle = oldNeedle - TICK < MINIMUM_GAUGE_SCALE
                    ? MINIMUM_GAUGE_SCALE
                    : needle - TICK;
            }
        }

        proposals[period] = true;
        // Might happen that needle did not move due to abstained or expired proposal.
        emit Nudge(period, oldNeedle, needle);
    }

    /// @notice Updates the period of the current epoch. This function can be called
    ///         by anyone. Chain fees accumulate in this contract continuously and
    ///         can be distributed between the first and second recipient after
    ///         the end of the specified period. In other words, the release of
    ///         the accumulated fees must wait until the end of the period.
    /// @dev    Needle position is used to determine the distribution ratio between
    ///         the first and second recipient.
    ///         1...first recipient amount..|..second recipient amount..100 [%]
    ///                                     ^
    ///                                   needle

    function updatePeriod() external returns (uint256 period) {
        period = activePeriod;
        if (block.timestamp >= period + WEEK) {
            uint256 oldPeriod = period;
            period = (block.timestamp / WEEK) * WEEK;
            activePeriod = period;

            uint256 firstRecipientAmount;
            uint256 secondRecipientAmount;

            uint256 currentBalance = token.balanceOf(address(this));
            if (currentBalance > 0) {
                firstRecipientAmount =
                    (currentBalance * needle) /
                    MAXIMUM_GAUGE_SCALE;
                secondRecipientAmount = currentBalance - firstRecipientAmount;

                transferFirstRecipient(firstRecipientAmount);
                transferSecondRecipient(secondRecipientAmount);
            }

            emit PeriodUpdated(
                oldPeriod,
                period,
                firstRecipientAmount,
                secondRecipientAmount
            );
        }
    }

    /// @notice Returns the address of the epoch governor.
    ///         Must adhere to a 1 week epoch of a splitter.
    function epochGovernor() external view virtual returns (address);

    /// @notice Transfers amount to the first recipient.
    function transferFirstRecipient(uint256 amount) internal virtual;

    /// @notice Transfers amount to the second recipient.
    function transferSecondRecipient(uint256 amount) internal virtual;
}
