// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVotingEscrow} from "./IVotingEscrow.sol";

interface IRewardsDistributor {
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(
        uint256 indexed tokenId,
        uint256 indexed epochStart,
        uint256 indexed epochEnd,
        uint256 amount
    );

    error NotDepositor();
    error NotManagedOrNormalNFT();
    error UpdatePeriod();

    /// @notice 7 days in seconds
    function week() external pure returns (uint256);

    /// @notice Timestamp of contract creation
    function startTime() external view returns (uint256);

    /// @notice Timestamp of most recent claim of tokenId
    function timeCursorOf(uint256 tokenId) external view returns (uint256);

    /// @notice The last timestamp Splitter has called checkpointToken()
    function lastTokenTime() external view returns (uint256);

    /// @notice Interface of VotingEscrow.sol
    function ve() external view returns (IVotingEscrow);

    /// @notice Address of token used for distributions
    function token() external view returns (address);

    /// @notice Address of Splitter.sol
    ///         Authorized caller of checkpointToken()
    function depositor() external view returns (address);

    /// @notice Amount of token in contract when checkpointToken() was last called
    function tokenLastBalance() external view returns (uint256);

    /// @notice Called by Splitter to notify Distributor of rebases
    function checkpointToken() external;

    /// @notice Returns the amount of rebases claimable for a given token ID
    /// @dev Allows claiming of rebases up to 50 epochs old
    /// @param tokenId The token ID to check
    /// @return The amount of rebases claimable for the given token ID
    function claimable(uint256 tokenId) external view returns (uint256);

    /// @notice Claims rebases for a given token ID
    /// @dev Allows claiming of rebases up to 50 epochs old
    ///      `Splitter.updatePeriod()` must be called before claiming
    /// @param tokenId The token ID to claim for
    /// @return The amount of rebases claimed
    function claim(uint256 tokenId) external returns (uint256);

    /// @notice Claims rebases for a list of token IDs
    /// @dev    `Splitter.updatePeriod()` must be called before claiming
    /// @param tokenIds The token IDs to claim for
    /// @return Whether or not the claim succeeded
    function claimMany(uint256[] calldata tokenIds) external returns (bool);

    /// @notice Used to set splitter once on initialization
    /// @dev Callable once by Splitter only, Splitter is immutable
    function setDepositor(address _depositor) external;
}
