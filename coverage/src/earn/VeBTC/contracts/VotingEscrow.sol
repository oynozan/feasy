// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.33;

import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {VotingEscrowState} from "./ve/VotingEscrowState.sol";
import {ManagedNFT} from "./ve/ManagedNFT.sol";
import {NFT} from "./ve/NFT.sol";
import {Escrow} from "./ve/Escrow.sol";
import {Delegation} from "./ve/Delegation.sol";
import {Balance} from "./ve/Balance.sol";
import {Grant} from "./ve/Grant.sol";

/// @title Voting Escrow
/// @notice veNFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
/// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
/// @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
/// @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
/// @author velodrome.finance, @figs999, @pegahcarter
/// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).
abstract contract VotingEscrow is
    IVotingEscrow,
    Initializable,
    ReentrancyGuardUpgradeable
{
    using VotingEscrowState for VotingEscrowState.Storage;
    using NFT for VotingEscrowState.Storage;
    using ManagedNFT for VotingEscrowState.Storage;
    using Escrow for VotingEscrowState.Storage;
    using Delegation for VotingEscrowState.Storage;
    using Balance for VotingEscrowState.Storage;
    using Grant for VotingEscrowState.Storage;

    VotingEscrowState.Storage internal self;

    /// @dev ERC165 interface ID of ERC165
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ERC165 interface ID of ERC721
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    /// @dev ERC165 interface ID of ERC721Metadata
    bytes4 internal constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    /// @dev ERC165 interface ID of ERC4906
    bytes4 internal constant ERC4906_INTERFACE_ID = 0x49064906;

    /// @dev ERC165 interface ID of ERC6372
    bytes4 internal constant ERC6372_INTERFACE_ID = 0xda287a1d;

    /// @param _token token address
    /// @param _factoryRegistry Factory Registry address
    /// @param _maxLockTime Maximum lock time of the veNFT in seconds.
    function __VotingEscrow_initialize(
        address _token,
        address _factoryRegistry,
        uint256 _maxLockTime
    ) internal onlyInitializing {
        __ReentrancyGuard_init();

        self.token = _token;
        self.factoryRegistry = _factoryRegistry;
        self.team = self._msgSender();
        self.voter = self._msgSender();

        self._pointHistory[0].blk = block.number;
        self._pointHistory[0].ts = block.timestamp;

        self.supportedInterfaces[ERC165_INTERFACE_ID] = true;
        self.supportedInterfaces[ERC721_INTERFACE_ID] = true;
        self.supportedInterfaces[ERC721_METADATA_INTERFACE_ID] = true;
        self.supportedInterfaces[ERC4906_INTERFACE_ID] = true;
        self.supportedInterfaces[ERC6372_INTERFACE_ID] = true;

        self.maxLockTime = _maxLockTime;

        // mint-ish
        emit Transfer(address(0), address(this), self.tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), self.tokenId);
    }

    /// @dev Second initializer, for proxies that were deployed with a trusted
    ///      forwarder. Writes zero to the stored forwarder: the escrow does not
    ///      resolve a sender through it, and fresh deployments never set it.
    ///      Run it as the data of `upgradeAndCall`, so the write lands in the
    ///      upgrade transaction. New managed locks then get reward contracts
    ///      with no trusted forwarder, so `getReward` on them accepts direct
    ///      calls only.
    function __VotingEscrow_initializeV2() internal onlyInitializing {
        self.trustedForwarder = address(0);
    }

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function createManagedLockFor(
        address _to
    ) external nonReentrant returns (uint256 _mTokenId) {
        return self.createManagedLockFor(_to);
    }

    /// @inheritdoc IVotingEscrow
    function depositManaged(
        uint256 _tokenId,
        uint256 _mTokenId
    ) external nonReentrant {
        self.depositManaged(_tokenId, _mTokenId);
    }

    /// @inheritdoc IVotingEscrow
    function withdrawManaged(uint256 _tokenId) external nonReentrant {
        self.withdrawManaged(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function setAllowedManager(address _allowedManager) external {
        self.setAllowedManager(_allowedManager);
    }

    /// @inheritdoc IVotingEscrow
    function setManagedState(uint256 _mTokenId, bool _state) external {
        self.setManagedState(_mTokenId, _state);
    }

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    function setTeam(address _team) external {
        self.setTeam(_team);
    }

    /// @inheritdoc IVotingEscrow
    function tokenURI(uint256) external pure returns (string memory) {
        return "";
    }

    /// @inheritdoc IVotingEscrow
    function ownerOf(uint256 _tokenId) external view returns (address) {
        return self._ownerOf(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOf(address _owner) external view returns (uint256) {
        return self.ownerToNFTokenCount[_owner];
    }

    /// @inheritdoc IVotingEscrow
    function getApproved(uint256 _tokenId) external view returns (address) {
        return self.idToApprovals[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedForAll(
        address _owner,
        address _operator
    ) external view returns (bool) {
        return (self.ownerToOperators[_owner])[_operator];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedOrOwner(
        address _spender,
        uint256 _tokenId
    ) external view returns (bool) {
        return self._isApprovedOrOwner(_spender, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function booster() external view returns (address) {
        return self.booster;
    }

    /// @inheritdoc IVotingEscrow
    function setBooster(address _booster) external {
        self.setBooster(_booster);
    }

    /// @inheritdoc IVotingEscrow
    function setFactoryRegistry(address _factoryRegistry) external {
        self.setFactoryRegistry(_factoryRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function approve(address _approved, uint256 _tokenId) external {
        self.approve(_approved, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function setApprovalForAll(address _operator, bool _approved) external {
        self.setApprovalForAll(_operator, _approved);
    }

    /* TRANSFER FUNCTIONS */

    /// @inheritdoc IVotingEscrow
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        self._transferFrom(_from, _to, _tokenId, self._msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public {
        self.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function supportsInterface(
        bytes4 _interfaceID
    ) external view returns (bool) {
        return self.supportedInterfaces[_interfaceID];
    }

    /// @inheritdoc IVotingEscrow
    function locked(
        uint256 _tokenId
    ) external view returns (LockedBalance memory) {
        return self._locked[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function userPointHistory(
        uint256 _tokenId,
        uint256 _loc
    ) external view returns (UserPoint memory) {
        return self._userPointHistory[_tokenId][_loc];
    }

    /// @inheritdoc IVotingEscrow
    function pointHistory(
        uint256 _loc
    ) external view returns (GlobalPoint memory) {
        return self._pointHistory[_loc];
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function checkpoint() external nonReentrant {
        self._checkpoint(
            0,
            LockedBalance(0, 0, false, 0),
            LockedBalance(0, 0, false, 0)
        );
    }

    /// @inheritdoc IVotingEscrow
    function depositFor(
        uint256 _tokenId,
        uint256 _value
    ) external nonReentrant {
        self.depositFor(_tokenId, _value);
    }

    /// @inheritdoc IVotingEscrow
    function createLock(
        uint256 _value,
        uint256 _lockDuration
    ) external nonReentrant returns (uint256) {
        return self._createLock(_value, _lockDuration, self._msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) external nonReentrant returns (uint256) {
        return self._createLock(_value, _lockDuration, _to);
    }

    /// @inheritdoc IVotingEscrow
    function increaseAmount(
        uint256 _tokenId,
        uint256 _value
    ) external nonReentrant {
        self.increaseAmount(_tokenId, _value);
    }

    /// @inheritdoc IVotingEscrow
    function increaseUnlockTime(
        uint256 _tokenId,
        uint256 _lockDuration
    ) external nonReentrant {
        self.increaseUnlockTime(_tokenId, _lockDuration);
    }

    /// @inheritdoc IVotingEscrow
    function withdraw(uint256 _tokenId) external nonReentrant {
        self.withdraw(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function merge(uint256 _from, uint256 _to) external nonReentrant {
        self.merge(_from, _to);
    }

    /// @inheritdoc IVotingEscrow
    function split(
        uint256 _from,
        uint256 _amount
    )
        external
        virtual
        nonReentrant
        returns (uint256 _tokenId1, uint256 _tokenId2)
    {
        return self.split(_from, _amount);
    }

    /// @inheritdoc IVotingEscrow
    function toggleSplit(address _account, bool _bool) external virtual {
        self.toggleSplit(_account, _bool);
    }

    /// @inheritdoc IVotingEscrow
    function lockPermanent(uint256 _tokenId) external {
        self.lockPermanent(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function unlockPermanent(uint256 _tokenId) external {
        self.unlockPermanent(_tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                              VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function votingPowerOfNFT(uint256 _tokenId) public view returns (uint256) {
        return self._votingPowerOfNFT(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function unboostedVotingPowerOfNFT(
        uint256 _tokenId
    ) external view returns (uint256) {
        if (self.ownershipChange[_tokenId] == block.number) return 0;
        return self.unboostedVotingPowerOfNFTAt(_tokenId, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function votingPowerOfNFTAt(
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256) {
        return self._votingPowerOfNFTAt(_tokenId, _t);
    }

    /// @inheritdoc IVotingEscrow
    function unboostedVotingPowerOfNFTAt(
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256) {
        return self.unboostedVotingPowerOfNFTAt(_tokenId, _t);
    }

    /// @inheritdoc IVotingEscrow
    function totalVotingPower() external view returns (uint256) {
        return self.totalVotingPowerAt(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function unboostedTotalVotingPower() external view returns (uint256) {
        return self.unboostedTotalVotingPowerAt(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function totalVotingPowerAt(
        uint256 _timestamp
    ) external view returns (uint256) {
        return self.totalVotingPowerAt(_timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function unboostedTotalVotingPowerAt(
        uint256 _t
    ) external view returns (uint256) {
        return self.unboostedTotalVotingPowerAt(_t);
    }

    /// @inheritdoc IVotingEscrow
    function virtualPermanentLockBalance() external view returns (uint256) {
        return self.virtualPermanentLockBalance;
    }

    /// @inheritdoc IVotingEscrow
    function virtualSlopeChanges(
        uint256 _timestamp
    ) external view returns (int128) {
        return self.virtualSlopeChanges[_timestamp];
    }

    /*///////////////////////////////////////////////////////////////
                              VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function updateBoost(uint256 _tokenId, uint256 _boost) external {
        self.updateBoost(_tokenId, _boost);
    }

    /// @inheritdoc IVotingEscrow
    function addSecondaryVoter(address _voter) external {
        self.addSecondaryVoter(_voter);
    }

    /// @inheritdoc IVotingEscrow
    function setVoterAndDistributor(
        address _voter,
        address _distributor
    ) external {
        self.setVoterAndDistributor(_voter, _distributor);
    }

    /// @inheritdoc IVotingEscrow
    function voting(uint256 _tokenId, bool _voted) external {
        self.setVoting(_tokenId, _voted);
    }

    /// @inheritdoc IVotingEscrow
    function delegates(uint256 delegator) external view returns (uint256) {
        return self._delegates[delegator];
    }

    /// @inheritdoc IVotingEscrow
    function checkpoints(
        uint256 _tokenId,
        uint48 _index
    ) external view returns (Checkpoint memory) {
        return self._checkpoints[_tokenId][_index];
    }

    /// @inheritdoc IVotingEscrow
    function getPastVotes(
        address _account,
        uint256 _tokenId,
        uint256 _timestamp
    ) external view returns (uint256) {
        return self.getPastVotes(_account, _tokenId, _timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function getPastTotalSupply(
        uint256 _timestamp
    ) external view returns (uint256) {
        return self.totalVotingPowerAt(_timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function delegate(uint256 delegator, uint256 delegatee) external {
        return self.delegate(delegator, delegatee);
    }

    /// @inheritdoc IVotingEscrow
    function delegateBySig(
        uint256 delegator,
        uint256 delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        return
            self.delegateBySig(
                Delegation.SignatureData({
                    delegator: delegator,
                    delegatee: delegatee,
                    nonce: nonce,
                    expiry: expiry,
                    v: v,
                    r: r,
                    s: s
                }),
                this.name(),
                this.version()
            );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC6372 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    /*///////////////////////////////////////////////////////////////
                                TOKEN GRANT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function setGrantManagerAllowed(
        address _grantManager,
        bool _allowed
    ) external {
        self._setGrantManagerAllowed(_grantManager, _allowed);
    }

    /// @inheritdoc IVotingEscrow
    function isGrantManagerAllowed(
        address _account
    ) external view returns (bool) {
        return self.isGrantManagerAllowed[_account];
    }

    /// @inheritdoc IVotingEscrow
    function createGrantLockFor(
        uint256 _value,
        address _grantee,
        address _grantManager,
        uint256 _vestingStart,
        uint256 _vestingEnd,
        uint256 _cliffEnd
    ) external nonReentrant returns (uint256) {
        return
            self._createGrantLockFor(
                _value,
                _grantee,
                _grantManager,
                _vestingStart,
                _vestingEnd,
                _cliffEnd
            );
    }

    /// @inheritdoc IVotingEscrow
    function setGrantManager(
        uint256 _tokenId,
        address _newGrantManager
    ) external {
        return self._setGrantManager(_tokenId, _newGrantManager);
    }

    /// @inheritdoc IVotingEscrow
    function revokeGrant(uint256 _tokenId) external nonReentrant {
        return self._revokeGrant(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function allowedManager() external view returns (address) {
        return self.allowedManager;
    }

    /// @inheritdoc IVotingEscrow
    function canSplit(address _account) external view returns (bool) {
        return self.canSplit[_account];
    }

    /// @inheritdoc IVotingEscrow
    function deactivated(
        uint256 _tokenId
    ) external view returns (bool inactive) {
        return self.deactivated[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function distributor() external view returns (address) {
        return self.distributor;
    }

    /// @inheritdoc IVotingEscrow
    function epoch() external view returns (uint256) {
        return self.epoch;
    }

    /// @inheritdoc IVotingEscrow
    function escrowType(uint256 _tokenId) external view returns (EscrowType) {
        return self.escrowType[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function factoryRegistry() external view returns (address) {
        return self.factoryRegistry;
    }

    /// @inheritdoc IVotingEscrow
    function forwarder() external view returns (address) {
        return self.trustedForwarder;
    }

    /// @inheritdoc IVotingEscrow
    function idToManaged(uint256 _tokenId) external view returns (uint256) {
        return self.idToManaged[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function managedToFree(uint256 _tokenId) external view returns (address) {
        return self.managedToFree[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function managedToLocked(uint256 _tokenId) external view returns (address) {
        return self.managedToLocked[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function nonces(address _account) external view returns (uint256) {
        return self.nonces[_account];
    }

    /// @inheritdoc IVotingEscrow
    function numCheckpoints(uint256 _tokenId) external view returns (uint48) {
        return self.numCheckpoints[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function ownerToNFTokenIdList(
        address _owner,
        uint256 _index
    ) external view returns (uint256) {
        return self.ownerToNFTokenIdList[_owner][_index];
    }

    /// @inheritdoc IVotingEscrow
    function permanentLockBalance() external view returns (uint256) {
        return self.permanentLockBalance;
    }

    /// @inheritdoc IVotingEscrow
    function slopeChanges(uint256 _timestamp) external view returns (int128) {
        return self.slopeChanges[_timestamp];
    }

    /// @inheritdoc IVotingEscrow
    function supply() external view returns (uint256) {
        return self.supply;
    }

    /// @inheritdoc IVotingEscrow
    function team() external view returns (address) {
        return self.team;
    }

    /// @inheritdoc IVotingEscrow
    function token() external view returns (address) {
        return self.token;
    }

    /// @inheritdoc IVotingEscrow
    function tokenId() external view returns (uint256) {
        return self.tokenId;
    }

    /// @inheritdoc IVotingEscrow
    function userPointEpoch(uint256 _tokenId) external view returns (uint256) {
        return self.userPointEpoch[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function voted(uint256 _tokenId) external view returns (bool) {
        return self.voted[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function votedVoters(
        uint256 _tokenId
    ) external view returns (address[] memory) {
        return self.votedVoters[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function votedVotersLength(
        uint256 _tokenId
    ) external view returns (uint256) {
        return self.votedVoters[_tokenId].length;
    }

    /// @inheritdoc IVotingEscrow
    function isSecondaryVoter(address _voter) external view returns (bool) {
        return self.secondaryVoters[_voter];
    }

    /// @inheritdoc IVotingEscrow
    function voter() external view returns (address) {
        return self.voter;
    }

    /// @inheritdoc IVotingEscrow
    function weights(
        uint256 _tokenId,
        uint256 _managedTokenId
    ) external view returns (uint256) {
        return self.weights[_tokenId][_managedTokenId];
    }

    /// @inheritdoc IVotingEscrow
    function grantManager(uint256 _tokenId) external view returns (address) {
        return self.grantManager[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function vestingStart(uint256 _tokenId) external view returns (uint256) {
        return self.vestingStart[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function vestingEnd(uint256 _tokenId) external view returns (uint256) {
        return self.vestingEnd[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function cliffEnd(uint256 _tokenId) external view returns (uint256) {
        return self.cliffEnd[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function grantRebaseAmount(
        uint256 _tokenId
    ) external view returns (uint256) {
        return self.grantRebaseAmount[_tokenId];
    }

    /// @notice The EIP-712 typehash for the contract's domain
    function DOMAIN_TYPEHASH() external pure returns (bytes32) {
        return Delegation.DOMAIN_TYPEHASH;
    }

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    function DELEGATION_TYPEHASH() external pure returns (bytes32) {
        return Delegation.DELEGATION_TYPEHASH;
    }
}
