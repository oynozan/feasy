// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IVotingEscrowBooster
/// @notice Interface for a contract managing boosts for veNFTs.
interface IVotingEscrowBooster {
    /// @notice Pokes the boost for a boostable veNFT. This
    ///         action forces the booster to recompute the boost factor
    ///         for the boostable veNFT and propagate the new
    ///         value to the veNFT contract.
    ///
    ///         The owner of the boostable veNFT has interest to
    ///         poke the boost anytime the boost factor
    ///         computed by the booster is higher than the
    ///         current value known by the veNFT contract.
    ///         This maximizes the voting power of the boostable veNFT.
    ///
    ///         On the other hand, other parties have interest to poke
    ///         the boost to minimize the voting power of the boostable veNFT
    ///         in case the boost factor computed by the booster is lower than
    ///         the current value known by the veNFT contract.
    /// @param boostableTokenId The ID of the boostable veNFT.
    function pokeBoost(uint256 boostableTokenId) external;

    /// @notice Pokes the boosts for a list of boostable veNFTs.
    ///         See pokeBoost for more details.
    /// @param boostableTokenIds The IDs of the boostable veNFTs.
    function pokeBoosts(uint256[] memory boostableTokenIds) external;

    /// @notice Gets the current boost factor for a boostable veNFT.
    /// @param boostableTokenId The ID of the boostable veNFT.
    /// @return The current boost factor for the boostable veNFT.
    function getBoost(uint256 boostableTokenId) external view returns (uint256);

    /// @notice Notifies the booster that a boostable veNFT has been burned.
    /// @param boostableTokenId The ID of the boostable veNFT.
    function notifyBoostableBurned(uint256 boostableTokenId) external;
}
