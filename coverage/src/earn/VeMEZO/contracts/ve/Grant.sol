// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.33;

import {VotingEscrowState} from "./VotingEscrowState.sol";
import {Escrow} from "./Escrow.sol";
import {Delegation} from "./Delegation.sol";
import {NFT} from "./NFT.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {BoostLibrary} from "../libraries/BoostLibrary.sol";

library Grant {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;
    using Escrow for VotingEscrowState.Storage;
    using Delegation for VotingEscrowState.Storage;
    using NFT for VotingEscrowState.Storage;
    using VotingEscrowState for VotingEscrowState.Storage;

    function _setGrantManagerAllowed(
        VotingEscrowState.Storage storage self,
        address _grantManager,
        bool _allowed
    ) external {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        if (_grantManager == address(0)) revert IVotingEscrow.ZeroAddress();
        self.isGrantManagerAllowed[_grantManager] = _allowed;
        emit IVotingEscrow.SetGrantManagerAllowed(_grantManager, _allowed);
    }

    function _createGrantLockFor(
        VotingEscrowState.Storage storage self,
        uint256 _value,
        address _grantee,
        address _grantManager,
        uint256 _vestingStart,
        uint256 _vestingEnd,
        uint256 _cliffEnd
    ) external returns (uint256) {
        // Only addresses from the allowlist can act as grant managers when
        // creating new grant-backed veNFTs. This prevents arbitrary users from
        // creating self-managed grants that can be immediately revoked to
        // bypass normal lock constraints.
        if (!self.isGrantManagerAllowed[_grantManager]) {
            revert IVotingEscrow.NotAllowedGrantManager();
        }

        if (_vestingStart >= _vestingEnd) {
            revert IVotingEscrow.IncorrectGrantVestingRange();
        }

        if (_cliffEnd < _vestingStart || _cliffEnd > _vestingEnd) {
            revert IVotingEscrow.IncorrectGrantVestingCliff();
        }

        if (block.timestamp >= _vestingEnd) {
            revert IVotingEscrow.GrantFullyVested();
        }

        // Round up lock duration to weeks. Otherwise, it would get rounded down
        // in _createLock, and we could end up with lock time shorter than vesting.
        uint256 WEEK = 1 weeks;
        uint256 normalizedVestingEnd = ((_vestingEnd + WEEK - 1) / WEEK) * WEEK;
        uint256 lockDuration = normalizedVestingEnd - block.timestamp;

        uint256 tokenId = self._createLock(_value, lockDuration, _grantee);
        self.grantManager[tokenId] = _grantManager;
        self.vestingStart[tokenId] = _vestingStart;
        self.vestingEnd[tokenId] = _vestingEnd;
        self.cliffEnd[tokenId] = _cliffEnd;

        emit IVotingEscrow.CreateGrant(
            tokenId,
            _grantee,
            _grantManager,
            _vestingStart,
            _vestingEnd,
            _cliffEnd
        );

        return tokenId;
    }

    function _setGrantManager(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        address _newGrantManager
    ) external {
        if (self._msgSender() != self.grantManager[_tokenId]) {
            revert IVotingEscrow.NotGrantManager();
        }

        self.grantManager[_tokenId] = _newGrantManager;
        emit IVotingEscrow.SetGrantManager(_newGrantManager);
    }

    function _revokeGrant(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external {
        address sender = self._msgSender();
        if (sender != self.grantManager[_tokenId]) {
            revert IVotingEscrow.NotGrantManager();
        }

        uint256 vestingStart = self.vestingStart[_tokenId];
        uint256 vestingEnd = self.vestingEnd[_tokenId];

        if (vestingStart == 0 || vestingEnd == 0) {
            revert IVotingEscrow.NotGrantNFT();
        }

        if (block.timestamp >= vestingEnd) {
            revert IVotingEscrow.GrantFullyVested();
        }

        uint256 cliffEnd = self.cliffEnd[_tokenId];

        if (block.timestamp <= cliffEnd) {
            // There are no vested tokens. Either vesting has started but we are
            // before the cliff end date, or the vesting has not even started yet.
            // _createGrantLockFor validation ensures that vestingStart <= cliffEnd.
            _revokeWithoutVestedTokens(self, _tokenId, sender);
        } else {
            // We are after the cliff end date so some tokens have vested - we need
            // to calculate how many and leave the vested portion with the grantee.
            uint256 lockedAmount = self._locked[_tokenId].amount.toUint256();
            uint256 rebaseAmount = self.grantRebaseAmount[_tokenId];

            // Exclude the rebase amount from the grant vesting calculation.
            // Rebases belong entirely to the grantee regardless of vesting
            // progress.
            uint256 effectiveGrantAmount = lockedAmount - rebaseAmount;
            uint256 vestedAmount = (effectiveGrantAmount *
                (block.timestamp - vestingStart)) / (vestingEnd - vestingStart);
            uint256 unvestedAmount = effectiveGrantAmount - vestedAmount;

            // The grantee keeps the vested portion plus all rebases.
            uint256 granteeAmount = vestedAmount + rebaseAmount;

            _revokeWithVestedTokens(
                self,
                _tokenId,
                sender,
                granteeAmount,
                unvestedAmount
            );
        }

        self._updateBoostIfBoostable(_tokenId);
    }

    function _revokeWithVestedTokens(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        address grantManager,
        uint256 vestedAmount,
        uint256 unvestedAmount
    ) internal {
        _revokeGrantInternal(
            self,
            _tokenId,
            grantManager,
            unvestedAmount,
            vestedAmount
        );
    }

    function _revokeWithoutVestedTokens(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        address grantManager
    ) internal {
        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];
        uint256 lockedAmount = oldLocked.amount.toUint256();
        uint256 rebaseAmount = self.grantRebaseAmount[_tokenId];

        if (rebaseAmount > 0) {
            // The grantee has earned rebases before the cliff. They keep the
            // NFT with the rebase amount as the remaining locked balance.
            // The grant manager gets the original grant amount back.
            uint256 revokedAmount = lockedAmount - rebaseAmount;

            _revokeGrantInternal(
                self,
                _tokenId,
                grantManager,
                revokedAmount,
                rebaseAmount
            );
        } else {
            // Nothing has vested and no rebases earned. The entire locked
            // amount (minus 1 smallest unit) is returned to the grant manager.
            // The remaining 1-unit dust veNFT is transferred to the grant
            // manager so the veNFT identity persists for voting / delegation
            // accounting.
            uint256 remainingAmount = 1;
            uint256 revokedAmount = lockedAmount - remainingAmount;

            // Transfer the veNFT to the grant manager. Using the internal
            // `_transferFrom` lets us transfer without the current owner's
            // approval by treating the current owner as the sender. The
            // veNFT will be shrunk to 1 unit.
            address oldOwner = self._ownerOf(_tokenId);
            self._transferFrom(oldOwner, grantManager, _tokenId, oldOwner);

            _revokeGrantInternal(
                self,
                _tokenId,
                grantManager,
                revokedAmount,
                remainingAmount
            );
        }
    }

    function _revokeGrantInternal(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        address grantManager,
        uint256 revokedAmount,
        uint256 remainingAmount
    ) internal {
        IVotingEscrow.LockedBalance memory oldLocked = self._locked[_tokenId];

        // Handle accounting of global balances if the lock was permanent.
        if (oldLocked.isPermanent) {
            // Unboosted permanent lock balance
            self.permanentLockBalance -= revokedAmount;

            // Boosted permanent lock balance.
            uint256 boostedRevokedAmount = BoostLibrary.boostedAmount(
                revokedAmount,
                oldLocked.boost
            );
            self.virtualPermanentLockBalance -= boostedRevokedAmount;

            // Reduce delegatee's delegated balance by the boosted revoked
            // amount.
            uint256 delegateeTokenId = self._delegates[_tokenId];
            self._checkpointDelegatee(
                delegateeTokenId,
                boostedRevokedAmount,
                false
            );
        }

        IVotingEscrow.LockedBalance memory newLocked = IVotingEscrow
            .LockedBalance({
                amount: remainingAmount.toInt128(),
                end: oldLocked.end,
                isPermanent: oldLocked.isPermanent,
                boost: oldLocked.boost
            });

        // Update the total supply.
        uint256 supplyBefore = self.supply;
        self.supply = supplyBefore - revokedAmount;

        // Update checkpoint data.
        self._locked[_tokenId] = newLocked;
        self._checkpoint(_tokenId, oldLocked, newLocked);

        // Transfer the revoked amount of tokens to the grant manager.
        IERC20(self.token).safeTransfer(grantManager, revokedAmount);

        // Clear the grant flags so the remaining locked deposit is no longer
        // treated as a grant. This will also prevent the grant manager from
        // revoking again.
        self.vestingStart[_tokenId] = 0;
        self.vestingEnd[_tokenId] = 0;
        self.cliffEnd[_tokenId] = 0;
        self.grantManager[_tokenId] = address(0);
        self.grantRebaseAmount[_tokenId] = 0;

        emit IVotingEscrow.Supply(supplyBefore, supplyBefore - revokedAmount);
        emit IVotingEscrow.RevokeGrant(
            _tokenId,
            grantManager,
            revokedAmount,
            remainingAmount
        );
    }
}
