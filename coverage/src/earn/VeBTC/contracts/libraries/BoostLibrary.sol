// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {SafeCastLibrary} from "./SafeCastLibrary.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/// @title BoostLibrary
/// @notice Library for calculating boosted amounts.
library BoostLibrary {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    uint256 internal constant PRECISION = 1e18;

    /// @notice Calculates the boosted amount for a locked balance.
    /// @param lockedBalance The locked balance to calculate the boosted amount for.
    /// @return The boosted amount for the locked balance.
    function boostedAmount(
        IVotingEscrow.LockedBalance memory lockedBalance
    ) internal pure returns (int128) {
        return
            boostedAmount(lockedBalance.amount.toUint256(), lockedBalance.boost)
                .toInt128();
    }

    /// @notice Calculates the boosted amount for an amount and a boost factor.
    /// @param amount The amount to calculate the boosted amount for.
    /// @param boost The boost factor to calculate the boosted amount for.
    /// @return The boosted amount for the amount and the boost factor.
    function boostedAmount(
        uint256 amount,
        uint256 boost
    ) internal pure returns (uint256) {
        // If the boost is unknown, use the default 1x boost.
        if (boost == 0) return amount;
        return (amount * boost) / PRECISION;
    }
}
