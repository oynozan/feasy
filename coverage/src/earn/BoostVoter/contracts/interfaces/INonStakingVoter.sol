// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IBaseVoter} from "./IBaseVoter.sol";

/// @title Non-staking voter
/// @notice Minimal interface describing a non-staking voter.
interface INonStakingVoter is IBaseVoter {
    error AlreadyVotedOrDeposited();
    error DistributeWindow();
    error GaugeAlreadyKilled();
    error GaugeAlreadyRevived();
    error GaugeExists();
    error GaugeDoesNotExist(address _gauge);
    error GaugeNotAlive(address _gauge);
    error InactiveManagedNFT();
    error MaximumVotingNumberTooLow();
    error NonZeroVotes();
    error NotApprovedOrOwner();
    error NotGovernor();
    error NotSplitter();
    error NotWhitelistedNFT();
    error NotWhitelistedToken();
    error SameValue();
    error SpecialVotingWindow();
    error TooManyGauges();
    error UnequalLengths();
    error ZeroBalance();
    error ZeroAddress();
    error ZeroLength();
    error GaugeFactoryNotApproved();

    event GaugeCreated(
        address indexed gauge,
        address indexed bribeVotingReward,
        address indexed creator
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(
        address indexed voter,
        address indexed gauge,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event Abstained(
        address indexed voter,
        address indexed gauge,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint256 amount
    );
    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint256 amount
    );
    event WhitelistToken(
        address indexed whitelister,
        address indexed token,
        bool indexed _bool
    );
    event WhitelistNFT(
        address indexed whitelister,
        uint256 indexed tokenId,
        bool indexed _bool
    );
    event SplitterSet(address indexed splitter);
    event BribesAdded(
        address indexed gauge,
        address indexed token,
        uint256 amount,
        address sender
    );

    /// @notice Store trusted forwarder address to pass into factories
    function forwarder() external view returns (address);

    /// @notice Factory registry for valid gauge and rewards factories
    function factoryRegistry() external view returns (address);

    /// @notice Address of a splitter contract
    function splitter() external view returns (address);

    /// @dev Total Voting Weights
    function totalWeight() external view returns (uint256);

    /// @dev Most number of gauges one voter can vote for at once
    function maxVotingNum() external view returns (uint256);

    // mappings
    /// @dev Gauge => Bribe Voting Reward
    function gaugeToBribe(address gauge) external view returns (address);

    /// @dev Gauge => Weights
    function weights(address gauge) external view returns (uint256);

    /// @dev NFT => Gauge => Votes
    function votes(
        uint256 tokenId,
        address gauge
    ) external view returns (uint256);

    /// @dev NFT => Total voting weight of NFT
    function usedWeights(uint256 tokenId) external view returns (uint256);

    /// @dev Nft => Timestamp of last vote (ensures single vote per epoch)
    function lastVoted(uint256 tokenId) external view returns (uint256);

    /// @dev Address => Gauge
    function isGauge(address) external view returns (bool);

    /// @dev TokenId => Whitelisted status
    function isWhitelistedNFT(uint256 tokenId) external view returns (bool);

    /// @dev Gauge => Liveness status
    function isAlive(address gauge) external view returns (bool);

    /// @dev Gauge => Amount claimable
    function claimable(address gauge) external view returns (uint256);

    /// @notice Number of gauges
    function length() external view returns (uint256);

    /// @notice Called by Splitter to distribute weekly emissions rewards for disbursement amongst gauges.
    /// @dev Assumes totalWeight != 0 (Will never be zero as long as users are voting).
    ///      Throws if not called by splitter.
    /// @param _amount Amount of rewards to distribute.
    function notifyRewardAmount(uint256 _amount) external;

    /// @dev Utility to distribute to gauges in range _start to _finish.
    /// @param _start   Starting index of gauges to distribute to.
    /// @param _finish  Ending index of gauges to distribute to.
    function distribute(uint256 _start, uint256 _finish) external;

    /// @dev Utility to distribute to gauges in array.
    /// @param _gauges Array of gauges to distribute to.
    function distribute(address[] memory _gauges) external;

    /// @notice Called by users to update voting balances in voting rewards contracts.
    /// @param _tokenId Id of veNFT whose balance you wish to update.
    function poke(uint256 _tokenId) external;

    /// @notice Called by users to vote for gauges. Votes distributed proportionally based on weights.
    ///         Can only vote or deposit into a managed NFT once per epoch.
    ///         Can only vote for gauges that have not been killed.
    /// @dev Weights are distributed proportional to the sum of the weights in the array.
    ///      Throws if length of _gaugeVote and _weights do not match.
    /// @param _tokenId     Id of veNFT you are voting with.
    /// @param _gaugeVote   Array of gauges you are voting for.
    /// @param _weights     Weights of gauges.
    function vote(
        uint256 _tokenId,
        address[] calldata _gaugeVote,
        uint256[] calldata _weights
    ) external;

    /// @notice Called by users to reset voting state. Required if you wish to make changes to
    ///         veNFT state (e.g. merge, split, deposit into managed etc).
    ///         Cannot reset in the same epoch that you voted in.
    ///         Can vote or deposit into a managed NFT again after reset.
    /// @param _tokenId Id of veNFT you are reseting.
    function reset(uint256 _tokenId) external;

    /// @notice Called by users to deposit into a managed NFT.
    ///         Can only vote or deposit into a managed NFT once per epoch.
    ///         Note that NFTs deposited into a managed NFT will be re-locked
    ///         to the maximum lock time on withdrawal.
    /// @dev Throws if not approved or owner.
    ///      Throws if managed NFT is inactive.
    ///      Throws if depositing within privileged window (one hour prior to epoch flip).
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external;

    /// @notice Called by users to withdraw from a managed NFT.
    ///         Cannot do it in the same epoch that you deposited into a managed NFT.
    ///         Can vote or deposit into a managed NFT again after withdrawing.
    ///         Note that the NFT withdrawn is re-locked to the maximum lock time.
    function withdrawManaged(uint256 _tokenId) external;

    /// @notice Claim emission rewards from gauges.
    /// @param _gauges Array of gauges to collect emission rewards from.
    function claimRewards(address[] memory _gauges) external;

    /// @notice Claim bribes for a given NFT.
    /// @dev Utility to help batch bribe claims.
    /// @param _bribes  Array of BribeVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as bribes.
    /// @param _tokenId Id of veNFT that you wish to claim bribes for.
    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external;

    /// @notice Set new governor.
    /// @dev Throws if not called by governor.
    /// @param _governor .
    function setGovernor(address _governor) external;

    /// @notice Set maximum number of gauges that can be voted for.
    /// @dev Throws if not called by governor.
    ///      Throws if _maxVotingNum is too low.
    ///      Throws if the values are the same.
    /// @param _maxVotingNum .
    function setMaxVotingNum(uint256 _maxVotingNum) external;

    /// @notice Whitelist (or unwhitelist) token for use in bribes.
    /// @dev Throws if not called by governor.
    /// @param _token .
    /// @param _bool .
    function whitelistToken(address _token, bool _bool) external;

    /// @notice Whitelist (or unwhitelist) token id for voting in last hour prior to epoch flip.
    /// @dev Throws if not called by governor.
    ///      Throws if already whitelisted.
    /// @param _tokenId .
    /// @param _bool .
    function whitelistNFT(uint256 _tokenId, bool _bool) external;

    /// @dev Update claims to emissions for an array of gauges.
    /// @param _gauges Array of gauges to update emissions for.
    function updateFor(address[] memory _gauges) external;

    /// @dev Update claims to emissions for gauges based on their index.
    /// @param _start   Starting index of gauges.
    /// @param _end     Ending index of gauges.
    function updateFor(uint256 _start, uint256 _end) external;

    /// @dev Update claims to emissions for single gauge
    /// @param _gauge .
    function updateFor(address _gauge) external;

    /// @notice Adds voting bribes to a specific gauge.
    /// @param _gauge The address of the gauge to add bribes to.
    /// @param _tokens The addresses of the bribe tokens.
    /// @param _amounts The amounts of the bribe tokens.
    function addBribes(
        address _gauge,
        address[] memory _tokens,
        uint256[] memory _amounts
    ) external;
}
