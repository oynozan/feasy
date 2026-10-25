// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {VotingEscrowState} from "./VotingEscrowState.sol";
import {Delegation} from "./Delegation.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IVotingEscrowBooster} from "../interfaces/IVotingEscrowBooster.sol";

library NFT {
    using Delegation for VotingEscrowState.Storage;
    using VotingEscrowState for VotingEscrowState.Storage;

    function approve(
        VotingEscrowState.Storage storage self,
        address _approved,
        uint256 _tokenId
    ) external {
        address sender = self._msgSender();
        address owner = _ownerOf(self, _tokenId);
        // Throws if `_tokenId` is not a valid NFT
        if (owner == address(0)) revert IVotingEscrow.ZeroAddress();
        // Throws if `_approved` is the current owner
        if (owner == _approved) revert IVotingEscrow.SameAddress();
        // Check requirements
        bool senderIsOwner = (_ownerOf(self, _tokenId) == sender);
        bool senderIsApprovedForAll = (self.ownerToOperators[owner])[sender];
        if (!senderIsOwner && !senderIsApprovedForAll)
            revert IVotingEscrow.NotApprovedOrOwner();
        // Set the approval
        self.idToApprovals[_tokenId] = _approved;
        emit IERC721.Approval(owner, _approved, _tokenId);
    }

    function setApprovalForAll(
        VotingEscrowState.Storage storage self,
        address _operator,
        bool _approved
    ) external {
        address sender = self._msgSender();
        // Throws if `_operator` is the `msg.sender`
        if (_operator == sender) revert IVotingEscrow.SameAddress();
        self.ownerToOperators[sender][_operator] = _approved;
        emit IERC721.ApprovalForAll(sender, _operator, _approved);
    }

    function safeTransferFrom(
        VotingEscrowState.Storage storage self,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external {
        address sender = self._msgSender();
        _transferFrom(self, _from, _to, _tokenId, sender);

        if (_isContract(_to)) {
            // Throws if transfer destination is a contract which does not implement 'onERC721Received'
            try
                IERC721Receiver(_to).onERC721Received(
                    sender,
                    _from,
                    _tokenId,
                    _data
                )
            returns (bytes4 response) {
                if (
                    response != IERC721Receiver(_to).onERC721Received.selector
                ) {
                    revert IVotingEscrow.ERC721ReceiverRejectedTokens();
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IVotingEscrow
                        .ERC721TransferToNonERC721ReceiverImplementer();
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    function _transferFrom(
        VotingEscrowState.Storage storage self,
        address _from,
        address _to,
        uint256 _tokenId,
        address _sender
    ) internal {
        if (self.escrowType[_tokenId] == IVotingEscrow.EscrowType.LOCKED)
            revert IVotingEscrow.NotManagedOrNormalNFT();
        // Check requirements
        if (!_isApprovedOrOwner(self, _sender, _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        // Clear approval. Throws if `_from` is not the current owner
        if (_ownerOf(self, _tokenId) != _from) revert IVotingEscrow.NotOwner();
        delete self.idToApprovals[_tokenId];
        // Remove NFT. Throws if `_tokenId` is not a valid NFT
        _removeTokenFrom(self, _from, _tokenId);
        // Update voting checkpoints
        self._checkpointDelegator(_tokenId, 0, _to);
        // Add NFT
        _addTokenTo(self, _to, _tokenId);
        // Set the block of ownership transfer (for Flash NFT protection)
        self.ownershipChange[_tokenId] = block.number;
        // Log the transfer
        emit IERC721.Transfer(_from, _to, _tokenId);
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @dev Add a NFT to a given address
    ///      Throws if `_tokenId` is owned by someone.
    function _addTokenTo(
        VotingEscrowState.Storage storage self,
        address _to,
        uint256 _tokenId
    ) internal {
        // Throws if `_tokenId` is owned by someone
        assert(_ownerOf(self, _tokenId) == address(0));
        // Change the owner
        self.idToOwner[_tokenId] = _to;
        // Update owner token index tracking
        _addTokenToOwnerList(self, _to, _tokenId);
        // Change count tracking
        self.ownerToNFTokenCount[_to] += 1;
    }

    /// @dev Function to mint tokens
    ///      Throws if `_to` is zero address.
    ///      Throws if `_tokenId` is owned by someone.
    /// @param _to The address that will receive the minted tokens.
    /// @param _tokenId The token id to mint.
    /// @return A boolean that indicates if the operation was successful.
    function _mint(
        VotingEscrowState.Storage storage self,
        address _to,
        uint256 _tokenId
    ) internal returns (bool) {
        // Throws if `_to` is zero address
        assert(_to != address(0));
        // Add NFT. Throws if `_tokenId` is owned by someone
        _addTokenTo(self, _to, _tokenId);
        // Update voting checkpoints
        self._checkpointDelegator(_tokenId, 0, _to);
        emit IERC721.Transfer(address(0), _to, _tokenId);
        return true;
    }

    /// @dev Add a NFT to an index mapping to a given address
    /// @param _to address of the receiver
    /// @param _tokenId uint ID Of the token to be added
    function _addTokenToOwnerList(
        VotingEscrowState.Storage storage self,
        address _to,
        uint256 _tokenId
    ) internal {
        uint256 currentCount = self.ownerToNFTokenCount[_to];

        self.ownerToNFTokenIdList[_to][currentCount] = _tokenId;
        self.tokenToOwnerIndex[_tokenId] = currentCount;
    }

    function _ownerOf(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) internal view returns (address) {
        return self.idToOwner[_tokenId];
    }

    function _isApprovedOrOwner(
        VotingEscrowState.Storage storage self,
        address _spender,
        uint256 _tokenId
    ) internal view returns (bool) {
        address owner = _ownerOf(self, _tokenId);
        bool spenderIsOwner = owner == _spender;
        bool spenderIsApproved = _spender == self.idToApprovals[_tokenId];
        bool spenderIsApprovedForAll = (self.ownerToOperators[owner])[_spender];
        return spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
    }

    /// @dev Must be called prior to updating `LockedBalance`
    function _burn(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId
    ) internal {
        address sender = self._msgSender();
        if (!_isApprovedOrOwner(self, sender, _tokenId))
            revert IVotingEscrow.NotApprovedOrOwner();
        address owner = _ownerOf(self, _tokenId);

        // Clear approval
        delete self.idToApprovals[_tokenId];
        // Update voting checkpoints
        self._checkpointDelegator(_tokenId, 0, address(0));
        // Remove token
        _removeTokenFrom(self, owner, _tokenId);
        emit IERC721.Transfer(owner, address(0), _tokenId);

        if (self.booster != address(0)) {
            IVotingEscrowBooster(self.booster).notifyBoostableBurned(_tokenId);
        }
    }

    /// @dev Remove a NFT from a given address
    ///      Throws if `_from` is not the current owner.
    function _removeTokenFrom(
        VotingEscrowState.Storage storage self,
        address _from,
        uint256 _tokenId
    ) internal {
        // Throws if `_from` is not the current owner
        assert(_ownerOf(self, _tokenId) == _from);
        // Change the owner
        self.idToOwner[_tokenId] = address(0);
        // Update owner token index tracking
        _removeTokenFromOwnerList(self, _from, _tokenId);
        // Change count tracking
        self.ownerToNFTokenCount[_from] -= 1;
    }

    /// @dev Remove a NFT from an index mapping to a given address
    /// @param _from address of the sender
    /// @param _tokenId uint ID Of the token to be removed
    function _removeTokenFromOwnerList(
        VotingEscrowState.Storage storage self,
        address _from,
        uint256 _tokenId
    ) internal {
        // Delete
        uint256 currentCount = self.ownerToNFTokenCount[_from] - 1;
        uint256 currentIndex = self.tokenToOwnerIndex[_tokenId];

        if (currentCount == currentIndex) {
            // update ownerToNFTokenIdList
            self.ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            self.tokenToOwnerIndex[_tokenId] = 0;
        } else {
            uint256 lastTokenId = self.ownerToNFTokenIdList[_from][
                currentCount
            ];

            // Add
            // update ownerToNFTokenIdList
            self.ownerToNFTokenIdList[_from][currentIndex] = lastTokenId;
            // update tokenToOwnerIndex
            self.tokenToOwnerIndex[lastTokenId] = currentIndex;

            // Delete
            // update ownerToNFTokenIdList
            self.ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            self.tokenToOwnerIndex[_tokenId] = 0;
        }
    }
}
