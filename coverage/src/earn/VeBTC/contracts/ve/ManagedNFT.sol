// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {VotingEscrowState} from "./VotingEscrowState.sol";
import {Escrow} from "./Escrow.sol";
import {NFT} from "./NFT.sol";
import {Delegation} from "./Delegation.sol";
import {Balance} from "./Balance.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IBaseVoter} from "../interfaces/IBaseVoter.sol";
import {IVotingEscrowBooster} from "../interfaces/IVotingEscrowBooster.sol";
import {IManagedRewardsFactory} from "../interfaces/factories/IManagedRewardsFactory.sol";
import {IFactoryRegistry} from "../interfaces/factories/IFactoryRegistry.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {BoostLibrary} from "../libraries/BoostLibrary.sol";

library ManagedNFT {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;
    using NFT for VotingEscrowState.Storage;
    using Escrow for VotingEscrowState.Storage;
    using Delegation for VotingEscrowState.Storage;
    using Balance for VotingEscrowState.Storage;
    using VotingEscrowState for VotingEscrowState.Storage;

    function createManagedLockFor(
        VotingEscrowState.Storage storage self,
        address _to
    ) external returns (uint256 _mTokenId) {
        address sender = self._msgSender();
        if (
            sender != self.allowedManager &&
            sender != IBaseVoter(self.voter).governor()
        ) revert IVotingEscrow.NotGovernorOrManager();

        _mTokenId = ++self.tokenId;
        self._mint(_to, _mTokenId);
        self._depositFor(
            _mTokenId,
            0,
            0,
            IVotingEscrow.LockedBalance(0, 0, true, 0),
            IVotingEscrow.DepositType.CREATE_LOCK_TYPE
        );

        self.escrowType[_mTokenId] = IVotingEscrow.EscrowType.MANAGED;

        (
            address _lockedManagedReward,
            address _freeManagedReward
        ) = IManagedRewardsFactory(
                IFactoryRegistry(self.factoryRegistry).managedRewardsFactory()
            ).createRewards(self.trustedForwarder, self.voter);
        self.managedToLocked[_mTokenId] = _lockedManagedReward;
        self.managedToFree[_mTokenId] = _freeManagedReward;

        emit IVotingEscrow.CreateManaged(
            _to,
            _mTokenId,
            sender,
            _lockedManagedReward,
            _freeManagedReward
        );
    }

    function depositManaged(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _mTokenId
    ) external {
        if (self._msgSender() != self.voter) revert IVotingEscrow.NotVoter();
        if (self.escrowType[_mTokenId] != IVotingEscrow.EscrowType.MANAGED)
            revert IVotingEscrow.NotManagedNFT();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.NORMAL)
            revert IVotingEscrow.NotNormalNFT();
        if (self._votingPowerOfNFTAt(_tokenId, block.timestamp) == 0)
            revert IVotingEscrow.ZeroBalance();
        if (self.voted[_tokenId]) revert IVotingEscrow.AlreadyVoted();

        // Check if the deposited NFT is an unvested grant. If so, the action is
        // not allowed as an unvested grant can be always revoked by the grant
        // manager and withdrawing it automatically from the managed NFT may be
        // tricky.
        if (self.vestingEnd[_tokenId] > block.timestamp) {
            revert IVotingEscrow.UnvestedGrantNFT();
        }

        // adjust user nft
        IVotingEscrow.LockedBalance memory oldLockedNormal = self._locked[
            _tokenId
        ];
        int128 _amount = oldLockedNormal.amount;
        if (oldLockedNormal.isPermanent) {
            self.permanentLockBalance -= _amount.toUint256();
            self.virtualPermanentLockBalance -= BoostLibrary
                .boostedAmount(oldLockedNormal)
                .toUint256();
            self._delegate(_tokenId, 0);
        }
        self._checkpoint(
            _tokenId,
            oldLockedNormal,
            IVotingEscrow.LockedBalance(0, 0, false, 0)
        );
        self._locked[_tokenId] = IVotingEscrow.LockedBalance(0, 0, false, 0);

        // adjust managed nft
        uint256 _weight = _amount.toUint256();
        IVotingEscrow.LockedBalance memory newLocked = self._locked[_mTokenId];
        self.permanentLockBalance += _weight;
        // Calculate the boosted weight that will be added to the virtual VP
        // of the managed NFT.
        uint256 boostedWeight = BoostLibrary.boostedAmount(
            _weight,
            newLocked.boost
        );
        // Since managed NFTs are permanent locks, the boosted weight must be added
        // to the total virtual permanent locks just like non-boosted weight is added
        // to the total actual permanent locks.
        self.virtualPermanentLockBalance += boostedWeight;
        newLocked.amount += _amount;
        // Boosted weight increases virtual VP of the managed NFT. If this managed NFT delegates its
        // VP for DAO voting, the boosted weight must be delegated to the delegatee of the managed NFT.
        self._checkpointDelegatee(
            self._delegates[_mTokenId],
            boostedWeight,
            true
        );
        self._checkpoint(_mTokenId, self._locked[_mTokenId], newLocked);
        self._locked[_mTokenId] = newLocked;

        self.weights[_tokenId][_mTokenId] = _weight;
        self.idToManaged[_tokenId] = _mTokenId;
        self.escrowType[_tokenId] = IVotingEscrow.EscrowType.LOCKED;

        address _lockedManagedReward = self.managedToLocked[_mTokenId];
        IReward(_lockedManagedReward)._deposit(_weight, _tokenId);
        address _freeManagedReward = self.managedToFree[_mTokenId];
        IReward(_freeManagedReward)._deposit(_weight, _tokenId);

        emit IVotingEscrow.DepositManaged(
            self._ownerOf(_tokenId),
            _tokenId,
            _mTokenId,
            _weight,
            block.timestamp
        );
        emit IERC4906.MetadataUpdate(_tokenId);

        self._updateBoostIfBoostable(_mTokenId);
    }

    function withdrawManaged(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) external {
        uint256 _mTokenId = self.idToManaged[_tokenId];
        if (self._msgSender() != self.voter) revert IVotingEscrow.NotVoter();
        if (_mTokenId == 0) revert IVotingEscrow.InvalidManagedNFTId();
        if (self.escrowType[_tokenId] != IVotingEscrow.EscrowType.LOCKED)
            revert IVotingEscrow.NotLockedNFT();

        // update accrued rewards
        address _lockedManagedReward = self.managedToLocked[_mTokenId];
        address _freeManagedReward = self.managedToFree[_mTokenId];
        uint256 _weight = self.weights[_tokenId][_mTokenId];
        uint256 _reward = IReward(_lockedManagedReward).earned(
            address(self.token),
            _tokenId
        );
        uint256 _total = _weight + _reward;
        uint256 _unlockTime = ((block.timestamp + self.maxLockTime) /
            Escrow.WEEK) * Escrow.WEEK;

        // claim locked rewards (rebases + compounded reward)
        address[] memory rewards = new address[](1);
        rewards[0] = address(self.token);
        IReward(_lockedManagedReward).getReward(_tokenId, rewards);

        _adjustUserNFT(self, _tokenId, _total, _unlockTime);
        _adjustManagedNFT(self, _mTokenId, _total);

        IReward(_lockedManagedReward)._withdraw(_weight, _tokenId);
        IReward(_freeManagedReward)._withdraw(_weight, _tokenId);

        delete self.idToManaged[_tokenId];
        delete self.weights[_tokenId][_mTokenId];
        delete self.escrowType[_tokenId];

        emit IVotingEscrow.WithdrawManaged(
            self._ownerOf(_tokenId),
            _tokenId,
            _mTokenId,
            _total,
            block.timestamp
        );
        emit IERC4906.MetadataUpdate(_tokenId);

        self._updateBoostIfBoostable(_mTokenId);
    }

    function _adjustUserNFT(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _total,
        uint256 _unlockTime
    ) internal {
        IVotingEscrow.LockedBalance memory newLockedNormal = IVotingEscrow
            .LockedBalance(_total.toInt128(), _unlockTime, false, 0);
        self._checkpoint(_tokenId, self._locked[_tokenId], newLockedNormal);
        self._locked[_tokenId] = newLockedNormal;
    }

    function _adjustManagedNFT(
        VotingEscrowState.Storage storage self,
        uint256 _mTokenId,
        uint256 _total
    ) internal {
        IVotingEscrow.LockedBalance memory newLockedManaged = self._locked[
            _mTokenId
        ];
        // do not expect _total > locked.amount / permanentLockBalance but just in case
        newLockedManaged.amount -= (
            _total.toInt128() < newLockedManaged.amount
                ? _total.toInt128()
                : newLockedManaged.amount
        );
        self.permanentLockBalance -= (
            _total < self.permanentLockBalance
                ? _total
                : self.permanentLockBalance
        );

        // Calculate the boosted total that will be subtracted from the virtual VP
        // of the managed NFT.
        uint256 boostedTotal = BoostLibrary.boostedAmount(
            _total,
            newLockedManaged.boost
        );
        self.virtualPermanentLockBalance -= (
            boostedTotal < self.virtualPermanentLockBalance
                ? boostedTotal
                : self.virtualPermanentLockBalance
        );

        // Boosted total decreases virtual VP of the managed NFT. If this managed NFT delegates its
        // VP for DAO voting, the boosted total must be undelegated from the delegatee of the managed NFT.
        self._checkpointDelegatee(
            self._delegates[_mTokenId],
            boostedTotal,
            false
        );
        self._checkpoint(_mTokenId, self._locked[_mTokenId], newLockedManaged);
        self._locked[_mTokenId] = newLockedManaged;
    }

    function setAllowedManager(
        VotingEscrowState.Storage storage self,
        address _allowedManager
    ) external {
        if (self._msgSender() != IBaseVoter(self.voter).governor())
            revert IVotingEscrow.NotGovernor();
        if (_allowedManager == self.allowedManager)
            revert IVotingEscrow.SameAddress();
        if (_allowedManager == address(0)) revert IVotingEscrow.ZeroAddress();
        self.allowedManager = _allowedManager;
        emit IVotingEscrow.SetAllowedManager(_allowedManager);
    }

    function setManagedState(
        VotingEscrowState.Storage storage self,
        uint256 _mTokenId,
        bool _state
    ) external {
        if (
            self._msgSender() != IBaseVoter(self.voter).emergencyCouncil() &&
            self._msgSender() != IBaseVoter(self.voter).governor()
        ) revert IVotingEscrow.NotEmergencyCouncilOrGovernor();
        if (self.escrowType[_mTokenId] != IVotingEscrow.EscrowType.MANAGED)
            revert IVotingEscrow.NotManagedNFT();
        if (self.deactivated[_mTokenId] == _state)
            revert IVotingEscrow.SameState();
        self.deactivated[_mTokenId] = _state;
    }
}
