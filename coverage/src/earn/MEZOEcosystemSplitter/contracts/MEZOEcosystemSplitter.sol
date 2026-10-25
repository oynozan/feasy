// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVoter} from "./interfaces/IVoter.sol";
import {INonStakingVoter} from "./interfaces/INonStakingVoter.sol";
import {IEpochGovernor} from "./interfaces/IEpochGovernor.sol";
import {IPeriodic} from "./interfaces/IPeriodic.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {Splitter} from "./Splitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MEZOEcosystemSplitter
/// @notice A MEZOEcosystemSplitter contract that changes the fee distribution between
///         pool voters and third party voters based on the gauge needle position.
contract MEZOEcosystemSplitter is Splitter {
    using SafeERC20 for IERC20;

    /// @notice The address of the EpochGovernor contract.
    address public override epochGovernor;

    /// @notice The address of the pools Voter contract.
    IVoter public immutable poolsVoter;

    /// @notice The address of the third party Voter contract.
    INonStakingVoter public immutable thirdPartyVoter;

    /// @notice The address of the upstream contract that funds this splitter.
    IPeriodic public upstream;

    /// @notice The address of the VotingEscrow contract.
    IVotingEscrow private immutable ve;

    /// @notice Thrown when a zero address is provided.
    error ZeroAddress();

    /// @notice Thrown when an invalid needle is provided.
    error InvalidNeedle();

    /// @notice Thrown when the epoch governor has already been initialized.
    error EpochGovernorAlreadyInitialized();

    /// @notice Thrown when the upstream contract has already been initialized.
    error UpstreamAlreadyInitialized();

    /// @notice Thrown when the caller is not authorized to initialize the epoch governor.
    error Unauthorized();

    /// @notice Constructor to set up the MEZO ecosystem splitter.
    /// @param _ve The address of the VotingEscrow contract (i.e. the veNFT token contract).
    /// @param _poolsVoter The address of the pool Voter contract.
    /// @param _thirdPartyVoter The address of the third party Voter contract.
    /// @param _needle The initial needle position. This is a percentage value directly
    ///                determining the portion of MEZO that goes to the pool voter contract.
    ///                The other portion of fees (100% - _needle) goes to the
    ///                third party voter contract.
    constructor(
        address _ve,
        address _poolsVoter,
        address _thirdPartyVoter,
        uint256 _needle
    ) Splitter(_ve) {
        if (
            _ve == address(0) ||
            _poolsVoter == address(0) ||
            _thirdPartyVoter == address(0)
        ) {
            revert ZeroAddress();
        }
        if (_needle < MINIMUM_GAUGE_SCALE || _needle > MAXIMUM_GAUGE_SCALE) {
            revert InvalidNeedle();
        }
        ve = IVotingEscrow(_ve);
        poolsVoter = IVoter(_poolsVoter);
        thirdPartyVoter = INonStakingVoter(_thirdPartyVoter);
        needle = _needle;
        activePeriod = ((block.timestamp) / WEEK) * WEEK;
    }

    /// @notice Initializes the epoch governor address.
    /// @param _epochGovernor The address of the EpochGovernor contract.
    /// @dev Can only be called once by ve.team().
    function initializeEpochGovernor(address _epochGovernor) external {
        if (msg.sender != ve.team()) revert Unauthorized();
        if (epochGovernor != address(0))
            revert EpochGovernorAlreadyInitialized();
        if (_epochGovernor == address(0)) revert ZeroAddress();
        epochGovernor = _epochGovernor;
    }

    /// @notice Initializes the upstream contract address.
    /// @param _upstream The address of the upstream contract.
    /// @dev Can only be called once by ve.team().
    function initializeUpstream(address _upstream) external {
        if (msg.sender != ve.team()) revert Unauthorized();
        if (address(upstream) != address(0))
            revert UpstreamAlreadyInitialized();
        if (_upstream == address(0)) revert ZeroAddress();
        upstream = IPeriodic(_upstream);
    }

    /// @dev Update upstream's period upon own period update.
    ///      This ensures the upstream always deposits any funds that are
    ///      meant to land on this splitter for active period distribution.
    ///      Such a chaining of updatePeriod calls ensures proper flow of funds
    ///      from top to bottom.
    function onUpdatePeriod() internal override {
        if (address(upstream) != address(0)) {
            upstream.updatePeriod();
        }
    }

    /// @notice Transfers amount to pools voter. Token is MEZO.
    function transferFirstRecipient(uint256 amount) internal override {
        if (amount == 0) return;
        token.safeApprove(address(poolsVoter), amount);
        poolsVoter.notifyRewardAmount(amount);
        token.safeApprove(address(poolsVoter), 0);
    }

    /// @notice Transfers amount to third party voter. Token is MEZO.
    function transferSecondRecipient(uint256 amount) internal override {
        if (amount == 0) return;
        token.safeApprove(address(thirdPartyVoter), amount);
        thirdPartyVoter.notifyRewardAmount(amount);
        token.safeApprove(address(thirdPartyVoter), 0);
    }
}
