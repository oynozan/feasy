// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Splitter} from "./Splitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";

/// @title ChainFeeSplitter
/// @notice Contract allocating 100% of the chain fees to the associated distributor.
contract ChainFeeSplitter is Splitter {
    using SafeERC20 for IERC20;

    event EpochGovernorUpdated(
        address indexed oldEpochGovernor,
        address indexed newEpochGovernor
    );

    /// @notice Contract responsible for distributing chain fees among veNFT holders.
    IRewardsDistributor public immutable rewardsDistributor;

    /// @notice The address of the EpochGovernor contract.
    /// @dev Epoch governor plays no role in Chain Fee Splitter as the nudge
    ///      function is no-op, here to satisfy the interface.
    address public override epochGovernor;

    /// @notice Thrown when nudge is called.
    /// @dev Nudging is not allowed for the chain fee splitter as it is a no-op.
    error NudgeNotAllowed();

    /// @notice Constructor to set up the chain fee splitter.
    /// @param _ve The address of the VotingEscrow contract (i.e. the veNFT token contract).
    /// @param _rewardsDistributor The address of the rewards distributor.
    /// @dev For the purpose of the chain fee splitter
    ///      the needle is set to 100 to direct all assets to the rewards distributor.
    ///      The epoch governor is set to address(0) as nudging is a no-op.
    constructor(address _ve, address _rewardsDistributor) Splitter(_ve) {
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        epochGovernor = address(0);
        needle = 100;
        activePeriod = ((block.timestamp) / WEEK) * WEEK;
    }

    /// @notice Chain fee splitter does not adjust the needle
    ///         so epoch governor nudges have no effect.
    function nudge() external override {
        revert NudgeNotAllowed();
    }

    /// @notice Transfers amount to the rewards distributor.
    function transferFirstRecipient(uint256 amount) internal override {
        token.safeTransfer(address(rewardsDistributor), amount);
        // checkpoint token balance in rewards distributor
        rewardsDistributor.checkpointToken();
    }

    /// @notice No-op as all fees are destined for the rewards distributor in
    ///         the first recipient.
    function transferSecondRecipient(uint256 amount) internal override {}
}
