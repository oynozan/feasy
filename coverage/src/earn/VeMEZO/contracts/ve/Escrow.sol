// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {VotingEscrowState} from "./VotingEscrowState.sol";
import {Delegation} from "./Delegation.sol";
import {NFT} from "./NFT.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVotingEscrowBooster} from "../interfaces/IVotingEscrowBooster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BoostLibrary} from "../libraries/BoostLibrary.sol";

library Escrow {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;
    using NFT for VotingEscrowState.Storage;
    using Delegation for VotingEscrowState.Storage;
    using VotingEscrowState for VotingEscrowState.Storage;

    /// @notice Helper structure holding new/old deltas for actual (non-boosted) and virtual (boosted) slopes.
    /// @dev Used to avoid stack too deep errors inside the _checkpoint function.
    struct DSlopes {
        int128 oldDslope;
        int128 newDslope;
        int128 oldVirtualDslope;
        int128 newVirtualDslope;
    }

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MULTIPLIER = 1 ether;

    function depositFor(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _value
    ) external {
        if (
            self.escrowType[_tokenId] == IVotingEscrow.EscrowType.MANAGED &&
            self._msgSender() != self.distributor
        ) revert IVotingEscrow.NotDistributor();
        _increaseAmountFor(
            self,
            _tokenId,
            _value,
            IVotingEscrow.DepositType.DEPOSIT_FOR_TYPE
        );
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _oldLocked Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.DepositType _depositType
    ) internal {
        uint256 supplyBefore = self.supply;
        self.supply = supplyBefore + _value;

        // Set newLocked to _oldLocked without mangling memory
        IVotingEscrow.LockedBalance memory newLocked;
        (
            newLocked.amount,
            newLocked.end,
            newLocked.isPermanent,
            newLocked.boost
        ) = (
            _oldLocked.amount,
            _oldLocked.end,
            _oldLocked.isPermanent,
            _oldLocked.boost
        );

        // Adding to existing lock, or if a lock is expired - creating a new one
        newLocked.amount += _value.toInt128();
        if (_unlockTime != 0) {
            newLocked.end = _unlockTime;
        }
        self._locked[_tokenId] = newLocked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // or if the lock is a permanent lock, then _oldLocked.end == 0
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // newLocked.end > block.timestamp (always)
        _checkpoint(self, _tokenId, _oldLocked, newLocked);

        address from = self._msgSender();
        if (_value != 0) {
            IERC20(self.token).safeTransferFrom(from, address(this), _value);
        }

        emit IVotingEscrow.Deposit(
            from,
            _tokenId,
            _depositType,
            _value,
            newLocked.end,
            block.timestamp
        );
        emit IVotingEscrow.Supply(supplyBefore, supplyBefore + _value);
    }

    /// @notice Updates the voting power boost for a veNFT
    /// @param _tokenId veNFT token ID
    /// @param _boost New boost value. This is a value in BoostLibrary.PRECISION precision.
    ///               0 is a valid value and means the same as 1x boost (or no boost).
    ///               A negative boost (< 1x) is also allowed. The caller is responsible
    ///               for ensuring the boost value makes sense in a broader context.
    /// @dev Requirements:
    ///      - The caller must be the booster
    ///      - The veNFT must exist
    ///      - The veNFT must be a normal or managed NFT
    ///      - The veNFT must be unexpired or permanent lock
    function updateBoost(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _boost
    ) external {
        if (self._msgSender() != self.booster) {
            revert IVotingEscrow.NotBooster();
        }

        _updateBoost(self, _tokenId, _boost);
    }

    /// @notice Fetches the most recent boost value for a veNFT and updates it
    ///         if the token is a boostable token. Does nothing otherwise.
    /// @param _tokenId veNFT token ID
    /// @dev Requirements:
    ///      - The veNFT must exist
    ///      - The veNFT must be a normal or managed NFT
    ///      - The veNFT must be unexpired or permanent lock
    function _updateBoostIfBoostable(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) internal {
        if (self.booster != address(0)) {
            IVotingEscrowBooster _booster = IVotingEscrowBooster(self.booster);
            _updateBoost(self, _tokenId, _booster.getBoost(_tokenId));
        }
    }

    /// @notice Updates the voting power boost for a veNFT. This is internal
    ///         function NOT performing the caller validation.
    /// @param _tokenId veNFT token ID
    /// @param _boost New boost value. This is a value in BoostLibrary.PRECISION precision.
    ///               0 is a valid value and means the same as 1x boost (or no boost).
    ///               A negative boost (< 1x) is also allowed. The caller is responsible
    ///               for ensuring the boost value makes sense in a broader context.
    /// @dev Requirements:
    ///      - The veNFT must exist
    ///      - The veNFT must be a normal or managed NFT
    ///      - The veNFT must be unexpired or permanent lock
    function _updateBoost(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _boost
    ) internal {
        IVotingEscrow.EscrowType _escrowType = self.escrowType[_tokenId];
        if (
            _escrowType != IVotingEscrow.EscrowType.NORMAL &&
            _escrowType != IVotingEscrow.EscrowType.MANAGED
        ) revert IVotingEscrow.NotManagedOrNormalNFT();

        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];

        // For managed NFTs, we allow updating the boost even if the amount is 0
        // as this is a valid state for a managed NFT (it exists but it holds nothing).
        if (
            oldLocked.amount <= 0 &&
            _escrowType != IVotingEscrow.EscrowType.MANAGED
        ) revert IVotingEscrow.NoLockFound();
        if (oldLocked.end <= block.timestamp && !oldLocked.isPermanent)
            revert IVotingEscrow.LockExpired();

        // Short circuit if the new boost is the same as the old boost.
        if (oldLocked.boost == _boost) return;

        uint256 oldBoostedAmount = BoostLibrary
            .boostedAmount(oldLocked)
            .toUint256();
        if (oldLocked.isPermanent) {
            // Cancel the effect of the old boost on the total virtual permanent locks.
            self.virtualPermanentLockBalance -= oldBoostedAmount;
        }
        // The boost is changing. If this veNFT delegates its virtual VP for DAO voting,
        // the old boosted amount must be undelegated from the delegatee of the veNFT.
        //
        // Note: Only permanent veNFT can delegate and have delegatees. However, we maintain
        // the existing convention of calling this function beyond the isPermanent block.
        // For non-permanent veNFTs, self.delegates will return 0 and the
        // self._checkpointDelegatee will be a no-op.
        uint256 delegateeTokenId = self._delegates[_tokenId];
        self._checkpointDelegatee(delegateeTokenId, oldBoostedAmount, false);

        // Update the boost for the veNFT. Keep other properties the same.
        IVotingEscrow.LockedBalance memory newLocked = IVotingEscrow
            .LockedBalance({
                amount: oldLocked.amount,
                end: oldLocked.end,
                isPermanent: oldLocked.isPermanent,
                boost: _boost
            });

        uint256 newBoostedAmount = BoostLibrary
            .boostedAmount(newLocked)
            .toUint256();
        if (newLocked.isPermanent) {
            // Add the effect of the new boost on the total virtual permanent locks.
            self.virtualPermanentLockBalance += newBoostedAmount;
        }
        // Delegate the new boosted amount to the delegatee of the veNFT, if any
        // (see the Note above the first self._checkpointDelegatee call in this function).
        self._checkpointDelegatee(delegateeTokenId, newBoostedAmount, true);

        // Reflect the boost update in the veNFT state.
        self._locked[_tokenId] = newLocked;

        // Update the checkpoint for the veNFT to propagate the boost change over the system.
        _checkpoint(self, _tokenId, oldLocked, newLocked);

        emit IVotingEscrow.UpdateBoost(_tokenId, _boost);
        emit IERC4906.MetadataUpdate(_tokenId);
    }

    /// @notice Record global and per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Previous locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        IVotingEscrow.UserPoint memory uOld;
        IVotingEscrow.UserPoint memory uNew;
        DSlopes memory ds;
        uint256 _epoch = self.epoch;

        if (_tokenId != 0) {
            // Get the actual (non-boosted) permanent lock balance.
            uNew.permanent = _newLocked.isPermanent
                ? _newLocked.amount.toUint256()
                : 0;
            // Get the virtual (boosted) permanent lock balance.
            uNew.virtualPermanent = _newLocked.isPermanent
                ? BoostLibrary.boostedAmount(_newLocked).toUint256()
                : 0;

            // Cache max lock time to not get it from storage multiple times.
            int128 maxLockTime = self.maxLockTime.toInt128();

            // Old state calculations.
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                // Calculate the actual (non-boosted) slope and bias.
                uOld.slope = _oldLocked.amount / maxLockTime;
                uOld.bias =
                    uOld.slope *
                    (_oldLocked.end - block.timestamp).toInt128();
                // Calculate the virtual (boosted) slope and bias.
                uOld.virtualSlope =
                    BoostLibrary.boostedAmount(_oldLocked) /
                    maxLockTime;
                uOld.virtualBias =
                    uOld.virtualSlope *
                    (_oldLocked.end - block.timestamp).toInt128();
            }
            // New state calculations.
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                // Calculate the actual (non-boosted) slope and bias.
                uNew.slope = _newLocked.amount / maxLockTime;
                uNew.bias =
                    uNew.slope *
                    (_newLocked.end - block.timestamp).toInt128();
                // Calculate the virtual (boosted) slope and bias.
                uNew.virtualSlope =
                    BoostLibrary.boostedAmount(_newLocked) /
                    maxLockTime;
                uNew.virtualBias =
                    uNew.virtualSlope *
                    (_newLocked.end - block.timestamp).toInt128();
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            //
            // Read for both the actual (non-boosted) and virtual (boosted) slope changes.
            ds.oldDslope = self.slopeChanges[_oldLocked.end];
            ds.oldVirtualDslope = self.virtualSlopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    ds.newDslope = ds.oldDslope;
                    ds.newVirtualDslope = ds.oldVirtualDslope;
                } else {
                    ds.newDslope = self.slopeChanges[_newLocked.end];
                    ds.newVirtualDslope = self.virtualSlopeChanges[
                        _newLocked.end
                    ];
                }
            }
        }

        IVotingEscrow.GlobalPoint memory lastPoint = IVotingEscrow.GlobalPoint({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number,
            permanentLockBalance: 0,
            virtualBias: 0,
            virtualSlope: 0,
            virtualPermanentLockBalance: 0
        });
        if (_epoch > 0) {
            lastPoint = self._pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        IVotingEscrow.GlobalPoint memory initialLastPoint = IVotingEscrow
            .GlobalPoint({
                bias: lastPoint.bias,
                slope: lastPoint.slope,
                ts: lastPoint.ts,
                blk: lastPoint.blk,
                permanentLockBalance: lastPoint.permanentLockBalance,
                virtualBias: lastPoint.virtualBias,
                virtualSlope: lastPoint.virtualSlope,
                virtualPermanentLockBalance: lastPoint
                    .virtualPermanentLockBalance
            });
        uint256 blockSlope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            blockSlope =
                (MULTIPLIER * (block.number - lastPoint.blk)) /
                (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        (_epoch, lastPoint) = _updateHistory(
            self,
            _epoch,
            lastPoint,
            lastCheckpoint,
            initialLastPoint,
            blockSlope
        );

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)

            // Update the global actual (non-boosted) slope, bias, and permanent lock balance.
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            lastPoint.permanentLockBalance = self.permanentLockBalance;

            // Update the global virtual (boosted) slope, bias, and permanent lock balance.
            lastPoint.virtualSlope += (uNew.virtualSlope - uOld.virtualSlope);
            lastPoint.virtualBias += (uNew.virtualBias - uOld.virtualBias);
            if (lastPoint.virtualSlope < 0) {
                lastPoint.virtualSlope = 0;
            }
            if (lastPoint.virtualBias < 0) {
                lastPoint.virtualBias = 0;
            }
            lastPoint.virtualPermanentLockBalance = self
                .virtualPermanentLockBalance;
        }

        // If timestamp of last global point is the same, overwrite the last global point
        // Else record the new global point into history
        // Exclude epoch 0 (note: _epoch is always >= 1, see above)
        // Two possible outcomes:
        // Missing global checkpoints in prior weeks. In this case, _epoch = epoch + x, where x > 1
        // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
        // No missing global checkpoints, but timestamp == block.timestamp. Overwrite last checkpoint.
        if (
            _epoch != 1 && self._pointHistory[_epoch - 1].ts == block.timestamp
        ) {
            // _epoch = epoch + 1, so we do not increment epoch
            self._pointHistory[_epoch - 1] = lastPoint;
        } else {
            // more than one global point may have been written, so we update epoch
            self.epoch = _epoch;
            self._pointHistory[_epoch] = lastPoint;
        }

        if (_tokenId != 0) {
            // Schedule the global slope changes (global slope is going down upon each unlock).
            //
            // Cancel the already scheduled global slope change for the old lock.
            if (_oldLocked.end > block.timestamp) {
                // Execute for both the actual (non-boosted) and virtual (boosted) global slopes.
                // The old global slope change was `something` minus old slope, so we add back
                // the old slope to cancel the effect.
                ds.oldDslope += uOld.slope;
                ds.oldVirtualDslope += uOld.virtualSlope;
                if (_newLocked.end == _oldLocked.end) {
                    // It was an amount change, not locktime extension.
                    ds.oldDslope -= uNew.slope;
                    ds.oldVirtualDslope -= uNew.virtualSlope;
                }
                self.slopeChanges[_oldLocked.end] = ds.oldDslope;
                self.virtualSlopeChanges[_oldLocked.end] = ds.oldVirtualDslope;
            }
            // Schedule the new global slope change for the new lock.
            if (_newLocked.end > block.timestamp) {
                // Execute for both the actual (non-boosted) and virtual (boosted) global slopes.
                // Update global slope if new lock is greater than old lock and is not permanent,
                // or if old lock is permanent (i.e. _oldLocked.end == 0).
                if ((_newLocked.end > _oldLocked.end)) {
                    // Old slope disappeared at this point.
                    ds.newDslope -= uNew.slope;
                    self.slopeChanges[_newLocked.end] = ds.newDslope;
                    ds.newVirtualDslope -= uNew.virtualSlope;
                    self.virtualSlopeChanges[_newLocked.end] = ds
                        .newVirtualDslope;
                }
                // Else: We recorded this case already in the previous block while dealing with the old lock.
            }
            // If timestamp of last user point is the same, overwrite the last user point
            // Else record the new user point into history
            // Exclude epoch 0
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            uint256 userEpoch = self.userPointEpoch[_tokenId];
            if (
                userEpoch != 0 &&
                self._userPointHistory[_tokenId][userEpoch].ts ==
                block.timestamp
            ) {
                self._userPointHistory[_tokenId][userEpoch] = uNew;
            } else {
                self.userPointEpoch[_tokenId] = ++userEpoch;
                self._userPointHistory[_tokenId][userEpoch] = uNew;
            }
        }
    }

    function _updateHistory(
        VotingEscrowState.Storage storage self,
        uint256 _epoch,
        IVotingEscrow.GlobalPoint memory lastPoint,
        uint256 lastCheckpoint,
        IVotingEscrow.GlobalPoint memory initialLastPoint,
        uint256 blockSlope
    ) internal returns (uint256, IVotingEscrow.GlobalPoint memory) {
        uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            t_i += WEEK; // Initial value of t_i is always larger than the ts of the last point
            int128 d_slope = 0;
            int128 d_virtualSlope = 0;
            if (t_i > block.timestamp) {
                t_i = block.timestamp;
            } else {
                d_slope = self.slopeChanges[t_i];
                d_virtualSlope = self.virtualSlopeChanges[t_i];
            }

            // Calculate the actual (non-boosted) slope and bias.
            lastPoint.bias -=
                lastPoint.slope *
                (t_i - lastCheckpoint).toInt128();
            lastPoint.slope += d_slope;
            if (lastPoint.bias < 0) {
                // This can happen
                lastPoint.bias = 0;
            }
            if (lastPoint.slope < 0) {
                // This cannot happen - just in case
                lastPoint.slope = 0;
            }
            // Calculate the virtual (boosted) slope and bias.
            lastPoint.virtualBias -=
                lastPoint.virtualSlope *
                (t_i - lastCheckpoint).toInt128();
            lastPoint.virtualSlope += d_virtualSlope;
            if (lastPoint.virtualBias < 0) {
                // This can happen
                lastPoint.virtualBias = 0;
            }
            if (lastPoint.virtualSlope < 0) {
                // This cannot happen - just in case
                lastPoint.virtualSlope = 0;
            }

            lastCheckpoint = t_i;
            lastPoint.ts = t_i;
            lastPoint.blk =
                initialLastPoint.blk +
                (blockSlope * (t_i - initialLastPoint.ts)) /
                MULTIPLIER;
            _epoch += 1;
            if (t_i == block.timestamp) {
                lastPoint.blk = block.number;
                break;
            } else {
                self._pointHistory[_epoch] = lastPoint;
            }
        }
        return (_epoch, lastPoint);
    }

    /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function _createLock(
        VotingEscrowState.Storage storage self,
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) external returns (uint256) {
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (_value == 0) revert IVotingEscrow.ZeroAmount();
        if (unlockTime <= block.timestamp)
            revert IVotingEscrow.LockDurationNotInFuture();
        if (unlockTime > block.timestamp + self.maxLockTime)
            revert IVotingEscrow.LockDurationTooLong();

        uint256 _tokenId = ++self.tokenId;
        self._mint(_to, _tokenId);

        _depositFor(
            self,
            _tokenId,
            _value,
            unlockTime,
            self._locked[_tokenId],
            IVotingEscrow.DepositType.CREATE_LOCK_TYPE
        );
        return _tokenId;
    }

    function increaseAmount(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _value
    ) external {
        if (!self._isApprovedOrOwner(self._msgSender(), _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        _increaseAmountFor(
            self,
            _tokenId,
            _value,
            IVotingEscrow.DepositType.INCREASE_LOCK_AMOUNT
        );
    }

    function _increaseAmountFor(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _value,
        IVotingEscrow.DepositType _depositType
    ) internal {
        IVotingEscrow.EscrowType _escrowType = self.escrowType[_tokenId];
        if (_escrowType == IVotingEscrow.EscrowType.LOCKED)
            revert IVotingEscrow.NotManagedOrNormalNFT();

        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];

        if (_value == 0) revert IVotingEscrow.ZeroAmount();
        if (oldLocked.amount <= 0) revert IVotingEscrow.NoLockFound();
        if (oldLocked.end <= block.timestamp && !oldLocked.isPermanent)
            revert IVotingEscrow.LockExpired();
        if (self.vestingEnd[_tokenId] > block.timestamp) {
            if (self._msgSender() == self.distributor) {
                // The distributor is depositing rebase rewards into an
                // unvested grant NFT. Track the rebase amount so it can
                // be excluded from the vested/unvested calculation during
                // grant revocation.
                self.grantRebaseAmount[_tokenId] += _value;
            } else {
                revert IVotingEscrow.UnvestedGrantNFT();
            }
        }

        // Determine the boosted value that will appear in the system as result
        // of _increaseAmountFor. We take the actual value added and we multiply
        // it by current boost of the veNFT.
        uint256 boostedValue = BoostLibrary.boostedAmount(
            _value,
            oldLocked.boost
        );

        if (oldLocked.isPermanent) {
            self.permanentLockBalance += _value;
            // Boosted value must be added to the total virtual permanent locks
            // just like non-boosted value is added to the total actual permanent locks
            // one line above.
            self.virtualPermanentLockBalance += boostedValue;
        }
        // Boosted value increases virtual VP of the veNFT. If this veNFT delegates its
        // VP for DAO voting, the boosted value must be delegated to the delegatee of the veNFT.
        self._checkpointDelegatee(
            self._delegates[_tokenId],
            boostedValue,
            true
        );
        _depositFor(self, _tokenId, _value, 0, oldLocked, _depositType);

        if (_escrowType == IVotingEscrow.EscrowType.MANAGED) {
            // increaseAmount called on managed tokens are treated as locked rewards
            address _lockedManagedReward = self.managedToLocked[_tokenId];
            address _token = self.token;
            IERC20(_token).safeApprove(_lockedManagedReward, _value);
            IReward(_lockedManagedReward).notifyRewardAmount(_token, _value);
            IERC20(_token).safeApprove(_lockedManagedReward, 0);
        }

        emit IERC4906.MetadataUpdate(_tokenId);

        _updateBoostIfBoostable(self, _tokenId);
    }

    function increaseUnlockTime(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _lockDuration
    ) external {
        if (!self._isApprovedOrOwner(self._msgSender(), _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();

        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];
        if (oldLocked.isPermanent) revert IVotingEscrow.PermanentLock();
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (oldLocked.end <= block.timestamp)
            revert IVotingEscrow.LockExpired();
        if (oldLocked.amount <= 0) revert IVotingEscrow.NoLockFound();
        if (unlockTime <= oldLocked.end)
            revert IVotingEscrow.LockDurationNotInFuture();
        if (unlockTime > block.timestamp + self.maxLockTime)
            revert IVotingEscrow.LockDurationTooLong();

        _depositFor(
            self,
            _tokenId,
            0,
            unlockTime,
            oldLocked,
            IVotingEscrow.DepositType.INCREASE_UNLOCK_TIME
        );

        emit IERC4906.MetadataUpdate(_tokenId);

        _updateBoostIfBoostable(self, _tokenId);
    }

    function withdraw(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external {
        address sender = self._msgSender();
        if (!self._isApprovedOrOwner(sender, _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (self.voted[_tokenId]) revert IVotingEscrow.AlreadyVoted();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();

        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];
        if (oldLocked.isPermanent) revert IVotingEscrow.PermanentLock();
        if (block.timestamp < oldLocked.end)
            revert IVotingEscrow.LockNotExpired();
        uint256 value = oldLocked.amount.toUint256();

        // Burn the NFT
        self._burn(_tokenId);
        self._locked[_tokenId] = IVotingEscrow.LockedBalance(0, 0, false, 0);
        uint256 supplyBefore = self.supply;
        self.supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // oldLocked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(
            self,
            _tokenId,
            oldLocked,
            IVotingEscrow.LockedBalance(0, 0, false, 0)
        );

        IERC20(self.token).safeTransfer(sender, value);

        emit IVotingEscrow.Withdraw(sender, _tokenId, value, block.timestamp);
        emit IVotingEscrow.Supply(supplyBefore, supplyBefore - value);

        // Deliberately not updating the boost as all the base voting power is
        // gone now.
    }

    function merge(
        VotingEscrowState.Storage storage self,
        uint256 _from,
        uint256 _to
    ) external {
        address sender = self._msgSender();
        if (self.voted[_from]) revert IVotingEscrow.AlreadyVoted();
        if (self.escrowType[_from] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        if (self.escrowType[_to] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        if (_from == _to) revert IVotingEscrow.SameNFT();
        if (!self._isApprovedOrOwner(sender, _from))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (!self._isApprovedOrOwner(sender, _to))
            revert IVotingEscrow.NotApprovedOrOwner();
        IVotingEscrow.LockedBalance memory oldLockedTo = self._locked[_to];
        if (oldLockedTo.end <= block.timestamp && !oldLockedTo.isPermanent)
            revert IVotingEscrow.LockExpired();
        if (
            self.vestingEnd[_from] > block.timestamp ||
            self.vestingEnd[_to] > block.timestamp
        ) {
            revert IVotingEscrow.UnvestedGrantNFT();
        }

        IVotingEscrow.LockedBalance memory oldLockedFrom = self._locked[_from];
        if (oldLockedFrom.isPermanent) revert IVotingEscrow.PermanentLock();
        uint256 end = oldLockedFrom.end >= oldLockedTo.end
            ? oldLockedFrom.end
            : oldLockedTo.end;

        self._burn(_from);
        self._locked[_from] = IVotingEscrow.LockedBalance(0, 0, false, 0);
        _checkpoint(
            self,
            _from,
            oldLockedFrom,
            IVotingEscrow.LockedBalance(0, 0, false, 0)
        );

        IVotingEscrow.LockedBalance memory newLockedTo;
        newLockedTo.amount = oldLockedTo.amount + oldLockedFrom.amount;
        newLockedTo.isPermanent = oldLockedTo.isPermanent;
        newLockedTo.boost = oldLockedTo.boost; // The `to` veNFT keeps its boost unchanged. The boost of `from` veNFT is lost.

        // The `from` amount is added to the `to` amount hence we need to calculate the
        // change in the virtual VP of the `to` veNFT. This change is boosted `from` amount
        // computed as actual `from` amount multiplied by the current boost of the `to` veNFT.
        uint256 boostedFromAmount = BoostLibrary.boostedAmount(
            oldLockedFrom.amount.toUint256(),
            newLockedTo.boost
        );

        if (newLockedTo.isPermanent) {
            self.permanentLockBalance += oldLockedFrom.amount.toUint256();
            // Boosted `from` amount must be added to the total virtual permanent locks
            // just like non-boosted `from` amount is added to the total actual permanent locks
            // one line above.
            self.virtualPermanentLockBalance += boostedFromAmount;
        } else {
            newLockedTo.end = end;
        }
        // Boosted `from` amount increases virtual VP of the `to` veNFT. If `to` veNFT delegates its
        // VP for DAO voting, the boosted `from` amount must be delegated to the delegatee of the `to` veNFT.
        self._checkpointDelegatee(
            self._delegates[_to],
            boostedFromAmount,
            true
        );
        _checkpoint(self, _to, oldLockedTo, newLockedTo);
        self._locked[_to] = newLockedTo;

        emit IVotingEscrow.Merge(
            sender,
            _from,
            _to,
            oldLockedFrom.amount.toUint256(),
            oldLockedTo.amount.toUint256(),
            newLockedTo.amount.toUint256(),
            newLockedTo.end,
            block.timestamp
        );
        emit IERC4906.MetadataUpdate(_to);
        _updateBoostIfBoostable(self, _to);
    }

    function split(
        VotingEscrowState.Storage storage self,
        uint256 _from,
        uint256 _amount
    ) external returns (uint256 _tokenId1, uint256 _tokenId2) {
        address sender = self._msgSender();
        address owner = self._ownerOf(_from);
        if (owner == address(0)) revert IVotingEscrow.SplitNoOwner();
        if (!self.canSplit[owner] && !self.canSplit[address(0)])
            revert IVotingEscrow.SplitNotAllowed();
        if (self.escrowType[_from] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        if (self.voted[_from]) revert IVotingEscrow.AlreadyVoted();
        if (!self._isApprovedOrOwner(sender, _from))
            revert IVotingEscrow.NotApprovedOrOwner();
        IVotingEscrow.LockedBalance memory newLocked = self._locked[_from];
        if (newLocked.end <= block.timestamp && !newLocked.isPermanent)
            revert IVotingEscrow.LockExpired();
        int128 _splitAmount = _amount.toInt128();
        if (_splitAmount == 0) revert IVotingEscrow.ZeroAmount();
        if (newLocked.amount <= _splitAmount)
            revert IVotingEscrow.AmountTooBig();
        if (self.vestingEnd[_from] > block.timestamp) {
            revert IVotingEscrow.UnvestedGrantNFT();
        }

        // Zero out and burn old veNFT
        self._burn(_from);
        self._locked[_from] = IVotingEscrow.LockedBalance(0, 0, false, 0);

        // If the parent veNFT was permanent lock, we must assume it could be boosted
        // and we must remove it's effect on the total virtual perm lock balance.
        // We must do it before the _checkpoint call that captures the last checkpoint for the
        // parent veNFT as _checkpoint uses self.virtualPermanentLockBalance to
        // update the global checkpoint.
        if (newLocked.isPermanent) {
            self.virtualPermanentLockBalance -= BoostLibrary
                .boostedAmount(newLocked)
                .toUint256();
        }

        // Capture the last checkpoint for the parent veNFT.
        _checkpoint(
            self,
            _from,
            newLocked,
            IVotingEscrow.LockedBalance(0, 0, false, 0)
        );

        // The boost for child veNFTs is lost upon split.
        newLocked.boost = 0;

        // Create new veNFT using old balance - amount
        newLocked.amount -= _splitAmount;
        _tokenId1 = _createSplitNFT(self, owner, newLocked);

        // Create new veNFT using amount
        newLocked.amount = _splitAmount;
        _tokenId2 = _createSplitNFT(self, owner, newLocked);

        emit IVotingEscrow.Split(
            _from,
            _tokenId1,
            _tokenId2,
            sender,
            self._locked[_tokenId1].amount.toUint256(),
            _splitAmount.toUint256(),
            newLocked.end,
            block.timestamp
        );

        // Deliberately not updating the boost as two new brand NFTs are created
        // with no boost.
    }

    function _createSplitNFT(
        VotingEscrowState.Storage storage self,
        address _to,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal returns (uint256 _tokenId) {
        _tokenId = ++self.tokenId;
        self._locked[_tokenId] = _newLocked;

        // If the child veNFT is a perm lock, we must add it's effect on the total virtual perm lock balance.
        // Note that the boost for the child veNFT is 0 as the boost of the parent veNFT is lost upon split
        if (_newLocked.isPermanent) {
            self.virtualPermanentLockBalance += BoostLibrary
                .boostedAmount(_newLocked)
                .toUint256();
        }

        _checkpoint(
            self,
            _tokenId,
            IVotingEscrow.LockedBalance(0, 0, false, 0),
            _newLocked
        );
        self._mint(_to, _tokenId);
    }

    function toggleSplit(
        VotingEscrowState.Storage storage self,
        address _account,
        bool _bool
    ) external {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        self.canSplit[_account] = _bool;
    }

    function lockPermanent(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external {
        address sender = self._msgSender();
        if (!self._isApprovedOrOwner(sender, _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        IVotingEscrow.LockedBalance memory _newLocked = self._locked[_tokenId];
        if (_newLocked.isPermanent) revert IVotingEscrow.PermanentLock();
        if (_newLocked.end <= block.timestamp)
            revert IVotingEscrow.LockExpired();
        if (_newLocked.amount <= 0) revert IVotingEscrow.NoLockFound();

        uint256 _amount = _newLocked.amount.toUint256();
        self.permanentLockBalance += _amount;
        self.virtualPermanentLockBalance += BoostLibrary.boostedAmount(
            _amount,
            _newLocked.boost
        );
        _newLocked.end = 0;
        _newLocked.isPermanent = true;
        _checkpoint(self, _tokenId, self._locked[_tokenId], _newLocked);
        self._locked[_tokenId] = _newLocked;

        emit IVotingEscrow.LockPermanent(
            sender,
            _tokenId,
            _amount,
            block.timestamp
        );
        emit IERC4906.MetadataUpdate(_tokenId);

        _updateBoostIfBoostable(self, _tokenId);
    }

    function unlockPermanent(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external {
        address sender = self._msgSender();
        if (!self._isApprovedOrOwner(sender, _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        if (self.voted[_tokenId]) revert IVotingEscrow.AlreadyVoted();
        IVotingEscrow.LockedBalance memory _newLocked = self._locked[_tokenId];
        if (!_newLocked.isPermanent) revert IVotingEscrow.NotPermanentLock();

        uint256 _amount = _newLocked.amount.toUint256();
        self.permanentLockBalance -= _amount;
        self.virtualPermanentLockBalance -= BoostLibrary.boostedAmount(
            _amount,
            _newLocked.boost
        );
        _newLocked.end = ((block.timestamp + self.maxLockTime) / WEEK) * WEEK;
        _newLocked.isPermanent = false;
        self._delegate(_tokenId, 0);
        _checkpoint(self, _tokenId, self._locked[_tokenId], _newLocked);
        self._locked[_tokenId] = _newLocked;

        emit IVotingEscrow.UnlockPermanent(
            sender,
            _tokenId,
            _amount,
            block.timestamp
        );
        emit IERC4906.MetadataUpdate(_tokenId);

        // Deliberately not updating the boost as a voting power does not
        // drop beyond standard decay that starts now.
    }
}
