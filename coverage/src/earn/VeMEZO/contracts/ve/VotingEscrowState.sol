// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

library VotingEscrowState {
    using VotingEscrowState for Storage;

    struct Storage {
        /// @dev Forwarder address handed to the reward contracts of new
        ///      managed locks. Zero on every deployment: the initializer does
        ///      not set it and the second initializer clears it on proxies
        ///      that stored one. Kept for the storage layout.
        address trustedForwarder;
        /// @dev Address of FactoryRegistry.sol
        address factoryRegistry;
        /// @dev Address of token used to create a veNFT
        address token;
        /// @dev Address of RewardsDistributor.sol
        address distributor;
        /// @dev Address of Voter.sol
        address voter;
        /// @dev Address of Protocol Team multisig
        address team;
        /// @dev Address which can create managed NFTs
        address allowedManager;
        /// @dev Global point history at a given index (epoch -> unsigned global point)
        mapping(uint256 => IVotingEscrow.GlobalPoint) _pointHistory;
        /// @dev Mapping of interface id to bool about whether or not it's supported
        mapping(bytes4 => bool) supportedInterfaces;
        /// @dev Current count of token
        uint256 tokenId;
        /*///////////////////////////////////////////////////////////////
                                MANAGED NFT
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping of token id to escrow type
        ///      Takes advantage of the fact default value is EscrowType.NORMAL
        mapping(uint256 => IVotingEscrow.EscrowType) escrowType;
        /// @dev Mapping of token id to managed id
        mapping(uint256 => uint256) idToManaged;
        /// @dev Mapping of user token id to managed token id to weight of token id
        mapping(uint256 => mapping(uint256 => uint256)) weights;
        /// @dev Mapping of managed id to deactivated state
        mapping(uint256 => bool) deactivated;
        /// @dev Mapping from managed nft id to locked managed rewards
        ///      `token` denominated rewards (rebases/rewards) stored in locked
        ///      managed rewards contract to prevent co-mingling of assets
        mapping(uint256 => address) managedToLocked;
        /// @dev Mapping from managed nft id to free managed rewards contract
        ///      these rewards can be freely withdrawn by users
        mapping(uint256 => address) managedToFree;
        /*//////////////////////////////////////////////////////////////
                            ERC721 BALANCE/OWNER
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping from NFT ID to the address that owns it.
        mapping(uint256 => address) idToOwner;
        /// @dev Mapping from owner address to count of his tokens.
        mapping(address => uint256) ownerToNFTokenCount;
        /*//////////////////////////////////////////////////////////////
                                ERC721 APPROVAL
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping from NFT ID to approved address.
        mapping(uint256 => address) idToApprovals;
        /// @dev Mapping from owner address to mapping of operator addresses.
        mapping(address => mapping(address => bool)) ownerToOperators;
        mapping(uint256 => uint256) ownershipChange;
        /*//////////////////////////////////////////////////////////////
                            INTERNAL MINT/BURN
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping from owner address to mapping of index to tokenId
        mapping(address => mapping(uint256 => uint256)) ownerToNFTokenIdList;
        /// @dev Mapping from NFT ID to index of owner
        mapping(uint256 => uint256) tokenToOwnerIndex;
        /*//////////////////////////////////////////////////////////////
                                    ESCROW
        //////////////////////////////////////////////////////////////*/

        /// @dev Total count of epochs witnessed since contract creation
        uint256 epoch;
        /// @dev Total amount of token() deposited
        uint256 supply;
        mapping(uint256 => IVotingEscrow.LockedBalance) _locked;
        mapping(uint256 => IVotingEscrow.UserPoint[1000000000]) _userPointHistory;
        mapping(uint256 => uint256) userPointEpoch;
        /// @dev time -> signed slope change
        mapping(uint256 => int128) slopeChanges;
        /// @dev account -> can split
        mapping(address => bool) canSplit;
        /// @dev Aggregate permanent locked balances
        uint256 permanentLockBalance;
        /// @dev Maximum lock time of the veNFT in seconds.
        ///      This value SHOULD NOT be changed after deployment
        ///      as it affects the voting power of all existing veNFTs.
        ///      It is defined here and not as constant because
        ///      different veNFT implementations have different
        ///      max lock times.
        uint256 maxLockTime;
        /*///////////////////////////////////////////////////////////////
                                    DAO VOTING
        //////////////////////////////////////////////////////////////*/

        /// @dev A record of each accounts delegate
        mapping(uint256 => uint256) _delegates;
        /// @dev A record of delegated token checkpoints for each tokenId, by index
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) _checkpoints;
        /// @dev The number of checkpoints for each tokenId
        mapping(uint256 => uint48) numCheckpoints;
        /// @dev A record of states for signing / validating signatures
        mapping(address => uint256) nonces;
        /*///////////////////////////////////////////////////////////////
                                GAUGE VOTING
        //////////////////////////////////////////////////////////////*/

        /// @dev Information on whether a tokenId has already voted
        mapping(uint256 => bool) voted;
        /*///////////////////////////////////////////////////////////////
                                TOKEN GRANT
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping from tokenId to grant manager. The grant manager can
        ///      revoke a grant converted to veNFT.
        mapping(uint256 => address) grantManager;
        /// @dev Mapping from tokenId to the end date of the grant vesting
        ///      schedule. The end date is a UNIX timestamp.
        mapping(uint256 => uint256) vestingEnd;
        /*///////////////////////////////////////////////////////////////
                        BOOSTS AND VIRTUAL VOTING POWER
        //////////////////////////////////////////////////////////////*/

        /// @dev Same as `slopeChanges` property but with boost factors applied.
        mapping(uint256 => int128) virtualSlopeChanges;
        /// @dev Same as `permanentLockBalance` property but with boost factors applied.
        uint256 virtualPermanentLockBalance;
        /// @dev Address of the entity authorized to update the boost for a veNFT
        address booster;
        /*///////////////////////////////////////////////////////////////
                                SECONDARY VOTERS
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping from tokenId to array of voters the token has voted in.
        ///      This includes the primary voter and all secondary voters.
        mapping(uint256 => address[]) votedVoters;
        /// @dev Set of approved secondary voters.
        ///      This contract distinguishes between primary voter (held by `voter` property)
        ///      and secondary voters. The primary voter has additional responsibilities,
        ///      most importantly, it manages deposits and withdrawals for managed NFTs
        ///      (as the only controller of free and locked managed rewards).
        mapping(address => bool) secondaryVoters;
        /*///////////////////////////////////////////////////////////////
                                TOKEN GRANT
        //////////////////////////////////////////////////////////////*/

        /// @dev Mapping of addresses allowed to act as grant managers.
        ///      Only addresses marked as allowed can be set as grant manager
        ///      when creating grant-backed veNFTs.
        mapping(address => bool) isGrantManagerAllowed;
        /// @dev Mapping from tokenId to the start date of the grant vesting
        ///      schedule. The start date is a UNIX timestamp.
        mapping(uint256 => uint256) vestingStart;
        /// @dev Mapping from tokenId to the grant cliff end date. The cliff
        ///      starts at vestingStart. The cliff end date is a UNIX timestamp.
        mapping(uint256 => uint256) cliffEnd;
        /// @dev Mapping from tokenId to the cumulative rebase amount deposited
        ///      by the RewardsDistributor while the grant was still unvested.
        ///      This amount belongs entirely to the grantee and is excluded
        ///      from the vested/unvested calculation during grant revocation.
        mapping(uint256 => uint256) grantRebaseAmount;
        /*///////////////////////////////////////////////////////////////
                                STORAGE GAP
        //////////////////////////////////////////////////////////////*/

        // Reserved storage space in case we need to add more variables.
        // The convention from OpenZeppelin suggests the storage space should
        // add up to 50 slots. Here we want to have more slots as there are
        // planned upgrades of the VotingEscrow contract. If more entires are
        // added to the struct in the upcoming versions we need to reduce
        // the array size.
        // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
        uint256[44] __gap;
    }

    function setTeam(
        VotingEscrowState.Storage storage self,
        address _team
    ) internal {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        if (_team == address(0)) revert IVotingEscrow.ZeroAddress();
        self.team = _team;
    }

    function setVoterAndDistributor(
        VotingEscrowState.Storage storage self,
        address _voter,
        address _distributor
    ) internal {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        self.voter = _voter;
        self.distributor = _distributor;
    }

    function setVoting(
        VotingEscrowState.Storage storage self,
        uint256 _tokenId,
        bool _voted
    ) internal {
        address sender = self._msgSender();
        bool isVoter = sender == self.voter || self.secondaryVoters[sender];
        if (!isVoter) revert IVotingEscrow.NotVoter();

        address[] storage voters = self.votedVoters[_tokenId];

        if (_voted) {
            // Add sender to votedVoters array if not already present
            bool found = false;
            for (uint256 i = 0; i < voters.length; i++) {
                if (voters[i] == sender) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                voters.push(sender);
            }
        } else {
            // Remove sender from votedVoters array if present
            for (uint256 i = 0; i < voters.length; i++) {
                if (voters[i] == sender) {
                    // Move the last element to the position of the element to remove
                    voters[i] = voters[voters.length - 1];
                    voters.pop();
                    break;
                }
            }
        }

        self.voted[_tokenId] = voters.length > 0;
    }

    function setBooster(
        VotingEscrowState.Storage storage self,
        address _booster
    ) internal {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        if (_booster == address(0)) revert IVotingEscrow.ZeroAddress();
        self.booster = _booster;
        emit IVotingEscrow.SetBooster(_booster);
    }

    function setFactoryRegistry(
        VotingEscrowState.Storage storage self,
        address _factoryRegistry
    ) internal {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        if (_factoryRegistry == address(0)) revert IVotingEscrow.ZeroAddress();
        self.factoryRegistry = _factoryRegistry;
        emit IVotingEscrow.SetFactoryRegistry(_factoryRegistry);
    }

    function addSecondaryVoter(
        VotingEscrowState.Storage storage self,
        address _voter
    ) internal {
        if (self._msgSender() != self.team) revert IVotingEscrow.NotTeam();
        if (_voter == address(0)) revert IVotingEscrow.ZeroAddress();
        self.secondaryVoters[_voter] = true;
        emit IVotingEscrow.AddSecondaryVoter(_voter);
    }

    /// @dev The escrow does not support meta-transactions. The ve libraries
    ///      run under `delegatecall`, where `msg.data` is the library call
    ///      and not the forwarder calldata with the sender appended, so an
    ///      ERC-2771 sender read in a library frame returns a wrong address.
    ///      The storage parameter is unused; it keeps the `self._msgSender()`
    ///      call form.
    function _msgSender(Storage storage) internal view returns (address) {
        return msg.sender;
    }
}
