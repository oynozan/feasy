// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {VotingEscrowState} from "./VotingEscrowState.sol";
import {NFT} from "./NFT.sol";
import {SafeCastLibrary} from "../libraries/SafeCastLibrary.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVotes} from "../governance/IVotes.sol";
import {BoostLibrary} from "../libraries/BoostLibrary.sol";

library Delegation {
    using SafeCastLibrary for int128;
    using NFT for VotingEscrowState.Storage;
    using VotingEscrowState for VotingEscrowState.Storage;

    struct SignatureData {
        uint256 delegator;
        uint256 delegatee;
        uint256 nonce;
        uint256 expiry;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string contractVersion,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256(
            "Delegation(uint256 delegator,uint256 delegatee,uint256 nonce,uint256 expiry)"
        );

    function delegate(
        VotingEscrowState.Storage storage self,
        uint256 delegator,
        uint256 delegatee
    ) external {
        if (!self._isApprovedOrOwner(self._msgSender(), delegator))
            revert IVotingEscrow.NotApprovedOrOwner();
        return _delegate(self, delegator, delegatee);
    }

    function delegateBySig(
        VotingEscrowState.Storage storage self,
        SignatureData calldata signatureData,
        string calldata contractName,
        string calldata contractVersion
    ) external {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (
            uint256(signatureData.s) >
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
        ) revert IVotingEscrow.InvalidSignatureS();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(contractName)),
                keccak256(bytes(contractVersion)),
                block.chainid,
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                signatureData.delegator,
                signatureData.delegatee,
                signatureData.nonce,
                signatureData.expiry
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(
            digest,
            signatureData.v,
            signatureData.r,
            signatureData.s
        );
        if (!self._isApprovedOrOwner(signatory, signatureData.delegator))
            revert IVotingEscrow.NotApprovedOrOwner();
        if (signatory == address(0)) revert IVotingEscrow.InvalidSignature();
        if (signatureData.nonce != self.nonces[signatory]++)
            revert IVotingEscrow.InvalidNonce();
        if (block.timestamp > signatureData.expiry)
            revert IVotingEscrow.SignatureExpired();
        return
            _delegate(self, signatureData.delegator, signatureData.delegatee);
    }

    /// @notice Record user delegation checkpoints. Used by DAO voting system.
    /// @dev Skips delegation if already delegated to `delegatee`.
    function _delegate(
        VotingEscrowState.Storage storage self,
        uint256 _delegator,
        uint256 _delegatee
    ) internal {
        IVotingEscrow.LockedBalance memory delegatorLocked = self._locked[
            _delegator
        ];
        if (!delegatorLocked.isPermanent)
            revert IVotingEscrow.NotPermanentLock();
        if (_delegatee != 0 && self._ownerOf(_delegatee) == address(0))
            revert IVotingEscrow.NonExistentToken();
        if (self.ownershipChange[_delegator] == block.number)
            revert IVotingEscrow.OwnershipChange();
        if (_delegatee == _delegator) _delegatee = 0;
        uint256 currentDelegate = self._delegates[_delegator];
        if (currentDelegate == _delegatee) return;

        // The delegated balance must include the boost factor
        // to ensure DAO voting leverages virtual voting power
        // just like other parts of the system.
        uint256 delegatedBalance = BoostLibrary.boostedAmount(
            delegatorLocked.amount.toUint256(),
            delegatorLocked.boost
        );
        _checkpointDelegator(
            self,
            _delegator,
            _delegatee,
            self._ownerOf(_delegator)
        );
        _checkpointDelegatee(self, _delegatee, delegatedBalance, true);

        emit IVotes.DelegateChanged(
            self._msgSender(),
            currentDelegate,
            _delegatee
        );
    }

    /// @notice Used by `_mint`, `_transferFrom`, `_burn` and `delegate`
    ///         to update delegator voting checkpoints.
    ///         Automatically dedelegates, then updates checkpoint.
    /// @dev This function depends on `_locked` and must be called prior to token state changes.
    ///      If you wish to dedelegate only, use `_delegate(tokenId, 0)` instead.
    /// @param _delegator The delegator to update checkpoints for
    /// @param _delegatee The new delegatee for the delegator. Cannot be equal to `_delegator` (use 0 instead).
    /// @param _owner The new (or current) owner for the delegator
    function _checkpointDelegator(
        VotingEscrowState.Storage storage self,
        uint256 _delegator,
        uint256 _delegatee,
        address _owner
    ) internal {
        IVotingEscrow.LockedBalance memory delegatorLocked = self._locked[
            _delegator
        ];
        // Since `_delegate` delegates the boost amount, here we need
        // to calculate the boosted delegated balance for proper undelegation.
        uint256 delegatedBalance = BoostLibrary.boostedAmount(
            delegatorLocked.amount.toUint256(),
            delegatorLocked.boost
        );
        uint48 numCheckpoint = self.numCheckpoints[_delegator];
        IVotingEscrow.Checkpoint storage cpOld = numCheckpoint > 0
            ? self._checkpoints[_delegator][numCheckpoint - 1]
            : self._checkpoints[_delegator][0];
        // Dedelegate from delegatee if delegated
        _checkpointDelegatee(self, cpOld.delegatee, delegatedBalance, false);
        IVotingEscrow.Checkpoint storage cp = self._checkpoints[_delegator][
            numCheckpoint
        ];
        cp.fromTimestamp = block.timestamp;
        cp.delegatedBalance = cpOld.delegatedBalance;
        cp.delegatee = _delegatee;
        cp.owner = _owner;

        if (_isCheckpointInNewBlock(self, _delegator)) {
            self.numCheckpoints[_delegator]++;
        } else {
            self._checkpoints[_delegator][numCheckpoint - 1] = cp;
            delete self._checkpoints[_delegator][numCheckpoint];
        }

        self._delegates[_delegator] = _delegatee;
    }

    /// @notice Update delegatee's `delegatedBalance` by `balance`.
    ///         Only updates if delegating to a new delegatee.
    /// @dev If used with `balance` == `_locked[_tokenId].amount`, then this is the same as
    ///      delegating or dedelegating from `_tokenId`
    ///      If used with `balance` < `_locked[_tokenId].amount`, then this is used to adjust
    ///      `delegatedBalance` when a user's balance is modified (e.g. `increaseAmount`, `merge` etc).
    ///      If `delegatee` is 0 (i.e. user is not delegating), then do nothing.
    /// @param _delegatee The delegatee's tokenId
    /// @param balance_ The delta in balance change
    /// @param _increase True if balance is increasing, false if decreasing
    function _checkpointDelegatee(
        VotingEscrowState.Storage storage self,
        uint256 _delegatee,
        uint256 balance_,
        bool _increase
    ) internal {
        if (_delegatee == 0) return;
        uint48 numCheckpoint = self.numCheckpoints[_delegatee];
        IVotingEscrow.Checkpoint storage cpOld = numCheckpoint > 0
            ? self._checkpoints[_delegatee][numCheckpoint - 1]
            : self._checkpoints[_delegatee][0];
        IVotingEscrow.Checkpoint storage cp = self._checkpoints[_delegatee][
            numCheckpoint
        ];
        cp.fromTimestamp = block.timestamp;
        cp.owner = cpOld.owner;
        // do not expect balance_ > cpOld.delegatedBalance when decrementing but just in case
        cp.delegatedBalance = _increase
            ? cpOld.delegatedBalance + balance_
            : (
                balance_ < cpOld.delegatedBalance
                    ? cpOld.delegatedBalance - balance_
                    : 0
            );
        cp.delegatee = cpOld.delegatee;

        if (_isCheckpointInNewBlock(self, _delegatee)) {
            self.numCheckpoints[_delegatee]++;
        } else {
            self._checkpoints[_delegatee][numCheckpoint - 1] = cp;
            delete self._checkpoints[_delegatee][numCheckpoint];
        }
    }

    function _isCheckpointInNewBlock(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) internal view returns (bool) {
        uint48 _nCheckPoints = self.numCheckpoints[_tokenId];

        if (
            _nCheckPoints > 0 &&
            self._checkpoints[_tokenId][_nCheckPoints - 1].fromTimestamp ==
            block.timestamp
        ) {
            return false;
        } else {
            return true;
        }
    }

    /// @notice Retrieves historical voting balance for a token id at a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    ///      The user must also own the token at the time in order to receive a voting balance.
    /// @param _account .
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return Total voting balance including delegations at a given timestamp.
    function getPastVotes(
        VotingEscrowState.Storage storage self,
        address _account,
        uint256 _tokenId,
        uint256 _timestamp
    ) external view returns (uint256) {
        uint48 _checkIndex = getPastVotesIndex(self, _tokenId, _timestamp);
        IVotingEscrow.Checkpoint memory lastCheckpoint = self._checkpoints[
            _tokenId
        ][_checkIndex];
        // If no point exists prior to the given timestamp, return 0
        if (lastCheckpoint.fromTimestamp > _timestamp) return 0;
        // Check ownership
        if (_account != lastCheckpoint.owner) return 0;
        uint256 votes = lastCheckpoint.delegatedBalance;
        return
            lastCheckpoint.delegatee == 0
                ? votes +
                    IVotingEscrow(address(this)).votingPowerOfNFTAt(
                        _tokenId,
                        _timestamp
                    )
                : votes;
    }

    /// @notice Binary search to get the voting checkpoint for a token id at or prior to a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return The index of the checkpoint.
    function getPastVotesIndex(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint48) {
        uint48 nCheckpoints = self.numCheckpoints[_tokenId];
        if (nCheckpoints == 0) return 0;
        // First check most recent balance
        if (
            self._checkpoints[_tokenId][nCheckpoints - 1].fromTimestamp <=
            _timestamp
        ) return (nCheckpoints - 1);
        // Next check implicit zero balance
        if (self._checkpoints[_tokenId][0].fromTimestamp > _timestamp) return 0;

        uint48 lower = 0;
        uint48 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint48 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.Checkpoint storage cp = self._checkpoints[_tokenId][
                center
            ];
            if (cp.fromTimestamp == _timestamp) {
                return center;
            } else if (cp.fromTimestamp < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }
}
