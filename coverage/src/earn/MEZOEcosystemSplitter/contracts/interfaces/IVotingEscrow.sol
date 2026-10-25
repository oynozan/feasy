// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC165, IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IVotes} from "../governance/IVotes.sol";

interface IVotingEscrow is IVotes, IERC4906, IERC6372, IERC721Metadata {
    /// @notice Structure containing foundational properties of a locked balance (veNFT).
    struct LockedBalance {
        /// @notice The physical amount of tokens locked.
        int128 amount;
        /// @notice The timestamp when the lock expires.
        uint256 end;
        /// @notice Flag indicating if the lock is permanent.
        ///         When true, all tokens in the veNFT are permanently locked.
        ///         Permanent locks apply to the entire amount - there is no way
        ///         to lock permanently just a portion of tokens from the veNFT.
        bool isPermanent;
        /// @notice The boost factor applied to the veNFT's voting power.
        ///         The boost factor is dynamic and changes over time.
        uint256 boost;
    }

    /// @notice Checkpoint structure holding a snapshot of the bias and slope,
    ///         specific to a single veNFT, at a certain timestamp.
    ///         Bias and slope are properties of the linear function describing
    ///         the veNFT's (decaying) voting power over time. The bias and slope
    ///         are derived from the LockedBalance properties. Each change to the
    ///         LockedBalance properties triggers an update of the bias and slope
    ///         and creation of a new checkpoint that captures the updated values.
    struct UserPoint {
        /// @notice Bias of the voting power linear function.
        ///         Describes the initial voting power of the veNFT at the checkpoint timestamp.
        int128 bias;
        /// @notice Slope of the voting power linear function.
        ///         Describes the per-second rate at which the voting power decays over time.
        int128 slope;
        /// @notice Timestamp of the checkpoint.
        uint256 ts;
        /// @notice Block number of the checkpoint.
        uint256 blk;
        /// @notice The amount of tokens locked permanently in this veNFT.
        ///         If the veNFT is not permanently locked, this value is 0.
        ///         If the veNFT is permanently locked, this value equals the full locked amount.
        uint256 permanent;
        /// @notice The `bias` property with boost factor applied.
        int128 virtualBias;
        /// @notice The `slope` property with boost factor applied.
        int128 virtualSlope;
        /// @notice The `permanent` property with boost factor applied.
        uint256 virtualPermanent;
    }

    /// @notice Global checkpoint structure holding a snapshot of the bias and slope,
    ///         specific to the aggregate of all veNFTs, at a certain timestamp.
    ///         Bias and slope are properties of the linear function describing
    ///         the (decaying) total voting power over time. The bias and slope
    ///         are an aggregate of all individual veNFTs' biases and slopes.
    ///         Each change to the LockedBalance properties of any veNFT triggers
    ///         an update of the global bias and slope and creation of a new global
    ///         checkpoint that captures the updated values.
    struct GlobalPoint {
        /// @notice Bias of the total voting power linear function.
        ///         Describes the initial total voting power at the global checkpoint timestamp.
        int128 bias;
        /// @notice Slope of the total voting power linear function.
        ///         Describes the per-second rate at which the total voting power decays over time.
        int128 slope;
        /// @notice Timestamp of the global checkpoint.
        uint256 ts;
        /// @notice Block number of the global checkpoint.
        uint256 blk;
        /// @notice The total amount of tokens locked permanently across all veNFTs.
        ///         When a veNFT is permanently locked, its entire locked amount is included here.
        uint256 permanentLockBalance;
        /// @notice The `bias` property with all veNFTs' boost factors applied.
        int128 virtualBias;
        /// @notice The `slope` property with all veNFTs' boost factors applied.
        int128 virtualSlope;
        /// @notice The `permanentLockBalance` property with all veNFTs' boost factors applied.
        uint256 virtualPermanentLockBalance;
    }

    /// @notice Checkpoint structure holding a voting power delegation at a certain timestamp.
    ///         Each checkpoint is specific to a single veNFT.
    struct Checkpoint {
        /// @notice Timestamp of the checkpoint.
        uint256 fromTimestamp;
        /// @notice Owner of the checkpoint's veNFT.
        address owner;
        /// @notice Balance delegated to the checkpoint's veNFT. As only permanently-locked veNFTs
        ///         can delegate, this balance represents a summarized voting power coming from
        ///         the delegating veNFTs. Delegated balance includes the boost factors of the delegators.
        uint256 delegatedBalance;
        /// @notice Another veNFT that the checkpoint's veNFT is delegating its own balance to.
        ///         Bear in mind, it's possible to delegate only own balance but not re-delegate
        ///         the delegated balance coming from delegating veNFTs. For example, if A
        ///         delegates to B, and B delegates to C, A has 0 VP, B has VP from A only,
        ///         and C has VP from B + their own VP.
        uint256 delegatee;
    }

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    /// @dev Different types of veNFTs:
    /// NORMAL  - typical veNFT
    /// LOCKED  - veNFT which is locked into a MANAGED veNFT
    /// MANAGED - veNFT which can accept the deposit of NORMAL veNFTs
    enum EscrowType {
        NORMAL,
        LOCKED,
        MANAGED
    }

    error AlreadyVoted();
    error AmountTooBig();
    error ERC721ReceiverRejectedTokens();
    error ERC721TransferToNonERC721ReceiverImplementer();
    error InvalidNonce();
    error InvalidSignature();
    error InvalidSignatureS();
    error InvalidManagedNFTId();
    error LockDurationNotInFuture();
    error LockDurationTooLong();
    error LockExpired();
    error LockNotExpired();
    error NoLockFound();
    error NonExistentToken();
    error NotApprovedOrOwner();
    error NotDistributor();
    error NotEmergencyCouncilOrGovernor();
    error NotGovernor();
    error NotGovernorOrManager();
    error NotManagedNFT();
    error NotManagedOrNormalNFT();
    error NotLockedNFT();
    error NotNormalNFT();
    error NotPermanentLock();
    error NotOwner();
    error NotTeam();
    error NotVoter();
    error OwnershipChange();
    error PermanentLock();
    error SameAddress();
    error SameNFT();
    error SameState();
    error SplitNoOwner();
    error SplitNotAllowed();
    error SignatureExpired();
    error TooManyTokenIDs();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroBalance();
    error NotGrantManager();
    error IncorrectGrantVestingRange();
    error IncorrectGrantVestingCliff();
    error UnvestedGrantNFT();
    error NotGrantNFT();
    error GrantWithoutVestedAmount();
    error GrantFullyVested();
    error SplitsDisabled();
    error NotBooster();
    error NotAllowedGrantManager();

    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );
    event Withdraw(
        address indexed provider,
        uint256 indexed tokenId,
        uint256 value,
        uint256 ts
    );
    event LockPermanent(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 amount,
        uint256 _ts
    );
    event UnlockPermanent(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 amount,
        uint256 _ts
    );
    event Supply(uint256 prevSupply, uint256 supply);
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );
    event CreateManaged(
        address indexed _to,
        uint256 indexed _mTokenId,
        address indexed _from,
        address _lockedManagedReward,
        address _freeManagedReward
    );
    event DepositManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event WithdrawManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event SetAllowedManager(address indexed _allowedManager);
    event CreateGrant(
        uint256 indexed _tokenId,
        address _grantee,
        address _grantManager,
        uint256 _vestingStart,
        uint256 _vestingEnd,
        uint256 _cliffEnd
    );
    event SetGrantManager(address indexed _grantManager);
    event RevokeGrant(
        uint256 indexed _tokenId,
        address indexed _grantManager,
        uint256 _revokedAmount,
        uint256 _remainingAmount
    );
    event SetGrantManagerAllowed(address indexed _grantManager, bool _allowed);
    /// @notice Emitted when the boost factor is updated for a veNFT.
    /// @param _tokenId The ID of the veNFT whose boost was updated.
    /// @param _boost The new boost factor value.
    event UpdateBoost(uint256 indexed _tokenId, uint256 _boost);
    event SetBooster(address indexed _booster);
    event SetFactoryRegistry(address indexed _factoryRegistry);
    event AddSecondaryVoter(address indexed _voter);

    // State variables
    /// @notice Address of Meta-tx Forwarder
    function forwarder() external view returns (address);

    /// @notice Address of FactoryRegistry.sol
    function factoryRegistry() external view returns (address);

    /// @notice Address of token used to create a veNFT
    function token() external view returns (address);

    /// @notice Address of RewardsDistributor.sol
    function distributor() external view returns (address);

    /// @notice Address of Voter.sol
    function voter() external view returns (address);

    /// @notice Address of Protocol Team multisig
    function team() external view returns (address);

    /// @dev address which can create managed NFTs
    function allowedManager() external view returns (address);

    /// @dev Returns true if `_account` is allowed to act as a grant manager.
    function isGrantManagerAllowed(
        address _account
    ) external view returns (bool);

    /// @dev Current count of token
    function tokenId() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping of token id to escrow type
    ///      Takes advantage of the fact default value is EscrowType.NORMAL
    function escrowType(uint256 tokenId) external view returns (EscrowType);

    /// @dev Mapping of token id to managed id
    function idToManaged(
        uint256 tokenId
    ) external view returns (uint256 managedTokenId);

    /// @dev Mapping of user token id to managed token id to weight of token id
    function weights(
        uint256 tokenId,
        uint256 managedTokenId
    ) external view returns (uint256 weight);

    /// @dev Mapping of managed id to deactivated state
    function deactivated(uint256 tokenId) external view returns (bool inactive);

    /// @dev Mapping from managed nft id to locked managed rewards
    ///      `token` denominated rewards (rebases/rewards) stored in locked managed rewards contract
    ///      to prevent co-mingling of assets
    function managedToLocked(uint256 tokenId) external view returns (address);

    /// @dev Mapping from managed nft id to free managed rewards contract
    ///      these rewards can be freely withdrawn by users
    function managedToFree(uint256 tokenId) external view returns (address);

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Create managed NFT (a permanent lock) for use within ecosystem.
    /// @dev Throws if address already owns a managed NFT.
    /// @return _mTokenId managed token id.
    function createManagedLockFor(
        address _to
    ) external returns (uint256 _mTokenId);

    /// @notice Delegates balance to managed nft
    ///         Note that NFTs deposited into a managed NFT will be re-locked
    ///         to the maximum lock time on withdrawal.
    ///         Permanent locks that are deposited will automatically unlock.
    /// @dev Managed nft will remain max-locked as long as there is at least one
    ///      deposit or withdrawal per week.
    ///      Throws if deposit nft is managed.
    ///      Throws if recipient nft is not managed.
    ///      Throws if deposit nft is already locked.
    ///      Throws if not called by voter.
    /// @param _tokenId tokenId of NFT being deposited
    /// @param _mTokenId tokenId of managed NFT that will receive the deposit
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external;

    /// @notice Retrieves locked rewards and withdraws balance from managed nft.
    ///         Note that the NFT withdrawn is re-locked to the maximum lock time.
    /// @dev Throws if NFT not locked.
    ///      Throws if not called by voter.
    /// @param _tokenId tokenId of NFT being deposited.
    function withdrawManaged(uint256 _tokenId) external;

    /// @notice Permit one address to call createManagedLockFor() that is not Voter.governor()
    function setAllowedManager(address _allowedManager) external;

    /// @notice Add or remove `_grantManager` from the set of addresses allowed
    ///         to act as grant managers. Only callable by the team.
    /// @param _grantManager Address to update.
    /// @param _allowed True to add to allowlist, false to remove.
    function setGrantManagerAllowed(
        address _grantManager,
        bool _allowed
    ) external;

    /// @notice Set Managed NFT state. Inactive NFTs cannot be deposited into.
    /// @param _mTokenId managed nft state to set
    /// @param _state true => inactive, false => active
    function setManagedState(uint256 _mTokenId, bool _state) external;

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function version() external view returns (string memory);

    function decimals() external view returns (uint8);

    function setTeam(address _team) external;

    /// @notice Set the entity authorized to update the boost for a veNFT
    /// @param _booster The new booster address
    /// @dev Requirements:
    ///      - The caller must be the team
    ///      - The booster address must implement IVotingEscrowBooster
    function setBooster(address _booster) external;

    /// @notice Address of the entity authorized to update the boost for a veNFT
    function booster() external view returns (address);

    /// @notice Set the factory registry address
    /// @param _factoryRegistry The new factory registry address
    /// @dev Requirements:
    ///      - The caller must be the team
    ///      - The factory registry address must not be zero address
    function setFactoryRegistry(address _factoryRegistry) external;

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from owner address to mapping of index to tokenId
    function ownerToNFTokenIdList(
        address _owner,
        uint256 _index
    ) external view returns (uint256 _tokenId);

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @inheritdoc IERC721
    function balanceOf(address owner) external view returns (uint256 balance);

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function getApproved(
        uint256 _tokenId
    ) external view returns (address operator);

    /// @inheritdoc IERC721
    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);

    /// @notice Check whether spender is owner or an approved user for a given veNFT
    /// @param _spender .
    /// @param _tokenId .
    function isApprovedOrOwner(
        address _spender,
        uint256 _tokenId
    ) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external;

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 _interfaceID
    ) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Total count of epochs witnessed since contract creation
    function epoch() external view returns (uint256);

    /// @notice Total amount of token() deposited.
    /// @dev This is NOT the total voting power but total amount of physical tokens deposited.
    function supply() external view returns (uint256);

    /// @notice Summarized voting power of all permanently locked veNFTs.
    ///         For example, if there are 3 veNFTs with 100 tokens each,
    ///         and 2 of them are permanently locked, the permanentLockBalance
    ///         will be 200.
    function permanentLockBalance() external view returns (uint256);

    function userPointEpoch(
        uint256 _tokenId
    ) external view returns (uint256 _epoch);

    /// @notice time -> signed slope change
    function slopeChanges(uint256 _timestamp) external view returns (int128);

    /// @notice account -> can split
    function canSplit(address _account) external view returns (bool);

    /// @notice Global point history at a given index
    function pointHistory(
        uint256 _loc
    ) external view returns (GlobalPoint memory);

    /// @notice Get the LockedBalance (amount, end) of a _tokenId
    /// @param _tokenId .
    /// @return LockedBalance of _tokenId
    function locked(
        uint256 _tokenId
    ) external view returns (LockedBalance memory);

    /// @notice User -> UserPoint[userEpoch]
    function userPointHistory(
        uint256 _tokenId,
        uint256 _loc
    ) external view returns (UserPoint memory);

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Record global data to checkpoint
    function checkpoint() external;

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function depositFor(uint256 _tokenId, uint256 _value) external;

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @return TokenId of created veNFT
    function createLock(
        uint256 _value,
        uint256 _lockDuration
    ) external returns (uint256);

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    /// @return TokenId of created veNFT
    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to
    ) external returns (uint256);

    /// @notice Deposit `_value` additional tokens for `_tokenId` without
    ///         modifying the unlock time.
    /// @dev Reverts if called for a veNFT representing a grant and the grant
    ///      has not fully vested yet.
    /// @param _value Amount of tokens to deposit and add to the lock
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    /// @notice Extend the unlock time for `_tokenId`
    ///         Cannot extend lock time of permanent locks
    /// @param _lockDuration New number of seconds until tokens unlock
    function increaseUnlockTime(
        uint256 _tokenId,
        uint256 _lockDuration
    ) external;

    /// @notice Withdraw all tokens for `_tokenId`
    /// @dev Only possible if the lock is both expired and not permanent
    ///      This will burn the veNFT. Any rebases or rewards that are unclaimed
    ///      will no longer be claimable. Claim all rebases and rewards prior to calling this.
    function withdraw(uint256 _tokenId) external;

    /// @notice Merges `_from` into `_to`.
    /// @dev Cannot merge `_from` locks that are permanent or have already voted this epoch.
    ///      Cannot merge `_to` locks that have already expired.
    ///      Cannot merge if either `_from` or `_to` is veNFT created for
    ///      a grant that has not fully vested yet.
    ///      This will burn the veNFT. Any rebases or rewards that are unclaimed
    ///      will no longer be claimable. Claim all rebases and rewards prior to calling this.
    /// @param _from VeNFT to merge from.
    /// @param _to VeNFT to merge into.
    function merge(uint256 _from, uint256 _to) external;

    /// @notice Splits veNFT into two new veNFTS - one with oldLocked.amount - `_amount`, and the second with `_amount`
    /// @dev    This burns the tokenId of the target veNFT
    ///         Callable by approved or owner
    ///         If this is called by approved, approved will not have permissions to manipulate the newly created veNFTs
    ///         Returns the two new split veNFTs to owner
    ///         If `from` is permanent, will automatically dedelegate.
    ///         This will burn the veNFT. Any rebases or rewards that are unclaimed
    ///         will no longer be claimable. Claim all rebases and rewards prior to calling this.
    /// @param _from VeNFT to split.
    /// @param _amount Amount to split from veNFT.
    /// @return _tokenId1 Return tokenId of veNFT with oldLocked.amount - `_amount`.
    /// @return _tokenId2 Return tokenId of veNFT with `_amount`.
    function split(
        uint256 _from,
        uint256 _amount
    ) external returns (uint256 _tokenId1, uint256 _tokenId2);

    /// @notice Toggle split for a specific address.
    /// @dev Toggle split for address(0) to enable or disable for all.
    /// @param _account Address to toggle split permissions
    /// @param _bool True to allow, false to disallow
    function toggleSplit(address _account, bool _bool) external;

    /// @notice Permanently lock a veNFT. Voting power will be equal to
    ///         `LockedBalance.amount` with no decay. Required to delegate.
    /// @dev Only callable by unlocked normal veNFTs.
    /// @param _tokenId tokenId to lock.
    function lockPermanent(uint256 _tokenId) external;

    /// @notice Unlock a permanently locked veNFT. Voting power will decay.
    ///         Will automatically dedelegate if delegated.
    /// @dev Only callable by permanently locked veNFTs.
    ///      Cannot unlock if already voted this epoch.
    /// @param _tokenId tokenId to unlock.
    function unlockPermanent(uint256 _tokenId) external;

    /*///////////////////////////////////////////////////////////////
                             VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the virtual (boosted) voting power for _tokenId at the
    ///         current timestamp.
    /// @dev Returns 0 if called in the same block as a transfer.
    /// @param _tokenId veNFT ID to query the voting power for
    /// @return Current voting power for _tokenId
    function votingPowerOfNFT(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the unboosted voting power for _tokenId at the current
    ///         timestamp. Unboosted voting power is the voting power without
    ///         the boost factor applied.
    /// @dev Similar to `votingPowerOfNFT(uint256 _tokenId)` but without the
    ///      boost factor applied. Returns 0 if called in the same block as
    ///      transfer.
    /// @param _tokenId veNFT ID to query unboosted voting power for
    /// @return Unboosted voting power for _tokenId at the current timestamp
    function unboostedVotingPowerOfNFT(
        uint256 _tokenId
    ) external view returns (uint256);

    /// @notice Get the virtual (boosted) voting power for _tokenId at a given
    ///         timestamp
    /// @param _tokenId veNFT ID to query the voting power for
    /// @param _t Timestamp to query voting power
    /// @return Voting power for _tokenId at timestamp _t
    function votingPowerOfNFTAt(
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256);

    /// @notice Get the unboosted voting power for _tokenId at a given timestamp.
    ///         Unboosted voting power is the voting power without the boost
    ///         factor applied.
    /// @dev Similar to `votingPowerOfNFTAt(uint256 _tokenId, uint256 _t)` but
    ///      without the boost factor applied.
    /// @param _tokenId veNFT ID to query unboosted voting power for
    /// @param _t Timestamp to query unboosted voting power
    /// @return Unboosted voting power for _tokenId at timestamp _t
    function unboostedVotingPowerOfNFTAt(
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256);

    /// @notice Calculate total virtual (boosted) voting power at the current
    ///         timestamp
    /// @return Total voting power at current timestamp
    function totalVotingPower() external view returns (uint256);

    /// @notice Calculate unboosted total voting power at the current timestamp.
    ///         Unboosted total voting power is the total voting power without
    ///         the boost factors applied.
    /// @dev Similar to `totalVotingPower()` but without the boost factors applied.
    /// @return Unboosted total voting power at current timestamp
    function unboostedTotalVotingPower() external view returns (uint256);

    /// @notice Calculate total virtual (boosted) voting power at a given
    ///         timestamp.
    /// @param _t Timestamp to query total voting power
    /// @return Total voting power at given timestamp
    function totalVotingPowerAt(uint256 _t) external view returns (uint256);

    /// @notice Calculate unboosted total voting power at a given timestamp.
    ///         Unboosted total voting power is the total voting power without
    ///         the boost factors applied.
    /// @dev Similar to `totalVotingPowerAt(uint256 _t)` but without the boost
    ///      factors applied.
    /// @param _t Timestamp to query unboosted total voting power.
    /// @return Unboosted total voting power at given timestamp.
    function unboostedTotalVotingPowerAt(
        uint256 _t
    ) external view returns (uint256);

    /// @notice Summarized virtual (boosted) voting power of all permanently
    ///         locked veNFTs. For example, if there are 3 veNFTs with 100
    ///         tokens and 2x boost each, and 2 of them are permanently locked,
    ///         the virtualPermanentLockBalance will be 400.
    /// @dev Same as `permanentLockBalance()` but with the boost factors applied.
    function virtualPermanentLockBalance() external view returns (uint256);

    /// @notice time -> signed virtual slope change (with boost applied)
    function virtualSlopeChanges(
        uint256 _timestamp
    ) external view returns (int128);

    /*///////////////////////////////////////////////////////////////
                               VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

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
    function updateBoost(uint256 _tokenId, uint256 _boost) external;

    /// @notice See if a queried _tokenId has actively voted in
    ///         the primary voter or any of the secondary voters.
    /// @param _tokenId .
    /// @return True if voted, else false
    function voted(uint256 _tokenId) external view returns (bool);

    /// @notice Get the list of voters that a token has voted in, regardless of the epoch.
    /// @param _tokenId The token ID to query
    /// @return Array of voter addresses that the token has voted in
    function votedVoters(
        uint256 _tokenId
    ) external view returns (address[] memory);

    /// @notice Get the number of voters that a token has voted in
    /// @param _tokenId The token ID to query
    /// @return The number of voters that the token has voted in
    function votedVotersLength(
        uint256 _tokenId
    ) external view returns (uint256);

    /// @notice Check if an address is a secondary voter
    /// @param _voter The address to check
    /// @return True if the address is a secondary voter, else false
    function isSecondaryVoter(address _voter) external view returns (bool);

    /// @notice Add an address to the secondary voters set.
    /// @param _voter The address to add
    /// @dev This contract distinguishes between primary voter (returned by `voter()`) and secondary voters.
    ///      The primary voter has additional responsibilities, most importantly, it manages deposits and
    ///      withdrawals for managed NFTs (as the only controller of free and locked managed rewards).
    /// @dev WARNING: Once added, a secondary voter CANNOT be removed.
    /// @dev Requirements:
    ///      - The caller must be the team
    ///      - The voter address must not be zero address
    function addSecondaryVoter(address _voter) external;

    /// @notice Set the global state voter and distributor
    /// @dev The caller must be the team
    /// @dev WARNING: Setting this on a live instance is a critical change
    ///      affecting the entire system. MAKE SURE YOU KNOW WHAT YOU ARE DOING!
    function setVoterAndDistributor(
        address _voter,
        address _distributor
    ) external;

    /// @notice Set `voted` for _tokenId to true or false
    /// @dev Only callable by voter
    /// @param _tokenId .
    /// @param _voted .
    function voting(uint256 _tokenId, bool _voted) external;

    /*///////////////////////////////////////////////////////////////
                            DAO VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The number of checkpoints for each tokenId
    function numCheckpoints(uint256 tokenId) external view returns (uint48);

    /// @notice A record of states for signing / validating signatures
    function nonces(address account) external view returns (uint256);

    /// @inheritdoc IVotes
    function delegates(uint256 delegator) external view returns (uint256);

    /// @notice A record of delegated token checkpoints for each account, by index
    /// @param tokenId .
    /// @param index .
    /// @return Checkpoint
    function checkpoints(
        uint256 tokenId,
        uint48 index
    ) external view returns (Checkpoint memory);

    /// @inheritdoc IVotes
    function getPastVotes(
        address account,
        uint256 tokenId,
        uint256 timestamp
    ) external view returns (uint256);

    /// @inheritdoc IVotes
    function getPastTotalSupply(
        uint256 timestamp
    ) external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotes
    function delegate(uint256 delegator, uint256 delegatee) external;

    /// @inheritdoc IVotes
    function delegateBySig(
        uint256 delegator,
        uint256 delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /*//////////////////////////////////////////////////////////////
                              ERC6372 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6372
    function clock() external view returns (uint48);

    /// @inheritdoc IERC6372
    function CLOCK_MODE() external view returns (string memory);

    /*///////////////////////////////////////////////////////////////
                                TOKEN GRANT
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit `_value` of tokens as a grant and lock until `_vestingEnd`
    ///         with the provided `_grantManager`. The vesting range must be
    ///         correct, i.e. _vestingStart < _vestingEnd. The function can only
    ///         be executed when the current block time is before `_vestingEnd`.
    ///         The specified _grantManager must be on the list of allowed
    ///         grant managers.
    /// @param _value Amount to deposit
    /// @param _grantee The grantee's address
    /// @param _grantManager The grant manager who can revoke the grant
    /// @param _vestingStart The timestamp representing the start of the vesting
    ///        schedule. This value might be different than the start of the
    ///        actual lock. The reason for this is that there might be a delay
    ///        between creating the grant in the third party service and
    ///        converting to a lock by executing this function.
    /// @param _vestingEnd The timestamp representing the end of the vesting
    ///        schedule. The lock will be rounded up to nearest week but the
    ///        original vesting end is recorded in the contract.
    /// @param _cliffEnd The timestamp representing the end of the cliff. The
    ///        cliff starts at _vestingStart. If there is no cliff, this value
    ///        should be set to value equal _vestingStart.
    /// @return TokenId of created veNFT
    function createGrantLockFor(
        uint256 _value,
        address _grantee,
        address _grantManager,
        uint256 _vestingStart,
        uint256 _vestingEnd,
        uint256 _cliffEnd
    ) external returns (uint256);

    /// @notice Allows the existing grant manager to set a new grant manager
    ///         address.
    /// @param _tokenId tokenId of the veNFT
    /// @param _newGrantManager The new grant manager address
    function setGrantManager(
        uint256 _tokenId,
        address _newGrantManager
    ) external;

    /// @notice Allows the grant manager to revoke a grant. If there are vested
    ///         tokens, they remain in the veNFT and the unvested portion is
    ///         transferred to the grant manager. If there are no vested tokens
    ///         (vesting has not started yet or we are before the cliff), all
    ///         tokens except 1 smallest unit are transferred to the grant
    ///         manager and the veNFT is kept as a 1-unit dust position owned by
    ///         the grant manager.
    /// @dev    Reverts if the veNFT was not created as a grant or if vesting
    ///         has already ended. Leaving 1-unit dust veNFT instead of burning
    ///         allows for avoiding burning veNFTs before the lock end. Note
    ///         that the veNFT may still have active votes on multiple voters
    ///         that would otherwise have had to be reset to zero before burning.
    /// @param _tokenId tokenId of the veNFT
    function revokeGrant(uint256 _tokenId) external;

    /// @notice Returns the grant manager address for the given veNFT
    /// @param _tokenId tokenId of the veNFT
    function grantManager(uint256 _tokenId) external view returns (address);

    /// @notice Returns the vesting schedule start for the given veNFT.
    ///         Zero if the veNFT was not created as a grant.
    /// @param _tokenId tokenId of the veNFT
    function vestingStart(uint256 _tokenId) external view returns (uint256);

    /// @notice Returns the vesting schedule end for the given veNFT.
    ///         Zero if the veNFT was not created as a grant.
    /// @param _tokenId tokenId of the veNFT
    function vestingEnd(uint256 _tokenId) external view returns (uint256);

    /// @notice Returns the cliff end for the given veNFT.
    ///         Zero if the veNFT was not created as a grant.
    /// @param _tokenId tokenId of the veNFT
    function cliffEnd(uint256 _tokenId) external view returns (uint256);
}
