// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {VotingEscrowState} from "./VotingEscrowState.sol";

library Balance {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    uint256 internal constant WEEK = 1 weeks;

    /// @notice Binary search to get the user point index for a token id at or prior to a given timestamp
    /// @dev If a user point does not exist prior to the timestamp, this will return 0.
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return User point index
    function getPastUserPointIndex(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = self.userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent balance
        if (self._userPointHistory[_tokenId][_userEpoch].ts <= _timestamp)
            return (_userEpoch);
        // Next check implicit zero balance
        if (self._userPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _userEpoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.UserPoint storage userPoint = self._userPointHistory[
                _tokenId
            ][center];
            if (userPoint.ts == _timestamp) {
                return center;
            } else if (userPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Binary search to get the global point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _timestamp .
    /// @return Global point index
    function getPastGlobalPointIndex(
        VotingEscrowState.Storage storage self,
        uint256 _timestamp
    ) internal view returns (uint256) {
        if (self.epoch == 0) return 0;
        // First check most recent balance
        if (self._pointHistory[self.epoch].ts <= _timestamp)
            return (self.epoch);
        // Next check implicit zero balance
        if (self._pointHistory[1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = self.epoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.GlobalPoint storage globalPoint = self._pointHistory[
                center
            ];
            if (globalPoint.ts == _timestamp) {
                return center;
            } else if (globalPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _votingPowerOfNFTAt(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _t
    ) internal view returns (uint256) {
        uint256 _epoch = getPastUserPointIndex(self, _tokenId, _t);
        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        IVotingEscrow.UserPoint memory lastPoint = self._userPointHistory[
            _tokenId
        ][_epoch];
        if (lastPoint.permanent != 0) {
            return lastPoint.virtualPermanent;
        } else {
            lastPoint.virtualBias -=
                lastPoint.virtualSlope *
                (_t - lastPoint.ts).toInt128();
            if (lastPoint.virtualBias < 0) {
                lastPoint.virtualBias = 0;
            }
            return lastPoint.virtualBias.toUint256();
        }
    }

    function _votingPowerOfNFT(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external view returns (uint256) {
        if (self.ownershipChange[_tokenId] == block.number) return 0;
        return _votingPowerOfNFTAt(self, _tokenId, block.timestamp);
    }

    /// @notice See VotingEscrow.unboostedVotingPowerOfNFTAt.
    function unboostedVotingPowerOfNFTAt(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256) {
        uint256 _epoch = getPastUserPointIndex(self, _tokenId, _t);
        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        IVotingEscrow.UserPoint memory lastPoint = self._userPointHistory[
            _tokenId
        ][_epoch];
        if (lastPoint.permanent != 0) {
            return lastPoint.permanent;
        } else {
            lastPoint.bias -= lastPoint.slope * (_t - lastPoint.ts).toInt128();
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return lastPoint.bias.toUint256();
        }
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function totalVotingPowerAt(
        VotingEscrowState.Storage storage self,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(self, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IVotingEscrow.GlobalPoint memory _point = self._pointHistory[epoch_];
        int128 bias = _point.virtualBias;
        int128 slope = _point.virtualSlope;
        uint256 ts = _point.ts;
        uint256 t_i = (ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = self.virtualSlopeChanges[t_i];
            }
            bias -= slope * (t_i - ts).toInt128();
            if (t_i == _t) {
                break;
            }
            slope += dSlope;
            ts = t_i;
        }

        if (bias < 0) {
            bias = 0;
        }
        return bias.toUint256() + _point.virtualPermanentLockBalance;
    }

    /// @notice See VotingEscrow.unboostedTotalVotingPowerAt.
    function unboostedTotalVotingPowerAt(
        VotingEscrowState.Storage storage self,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(self, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IVotingEscrow.GlobalPoint memory _point = self._pointHistory[epoch_];
        int128 bias = _point.bias;
        int128 slope = _point.slope;
        uint256 ts = _point.ts;
        uint256 t_i = (ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = self.slopeChanges[t_i];
            }
            bias -= slope * (t_i - ts).toInt128();
            if (t_i == _t) {
                break;
            }
            slope += dSlope;
            ts = t_i;
        }

        if (bias < 0) {
            bias = 0;
        }
        return bias.toUint256() + _point.permanentLockBalance;
    }
}
