// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVotingRewardsFactory} from "./interfaces/factories/IVotingRewardsFactory.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IStakingGaugeFactory} from "./interfaces/factories/IStakingGaugeFactory.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ISplitter} from "./interfaces/ISplitter.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IPoolFactory} from "./interfaces/factories/IPoolFactory.sol";
import {IReward} from "./interfaces/IReward.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IBaseVoter} from "./interfaces/IBaseVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IFactoryRegistry} from "./interfaces/factories/IFactoryRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";

/// @title Protocol Voter
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Manage votes, emission distribution, and gauge creation within the Protocol's ecosystem.
///         Also provides support for depositing and withdrawing from managed veNFTs.
contract Voter is
    IVoter,
    Initializable,
    ERC2771ContextUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    /// @inheritdoc IVoter
    /// @dev We need to store the forwarder address because ERC2771ContextUpgradeable
    ///      doesn't expose it publicly, but we need to pass it to factories
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable forwarder;
    /// @inheritdoc IBaseVoter
    address public ve;
    /// @inheritdoc IVoter
    address public factoryRegistry;
    /// @notice Base token of ve contract
    address internal rewardToken;
    /// @notice Rewards are released over 7 days
    uint256 internal constant DURATION = 7 days;
    /// @inheritdoc IVoter
    address public splitter;
    /// @inheritdoc IBaseVoter
    address public governor;
    /// @inheritdoc IBaseVoter
    address public emergencyCouncil;

    /// @inheritdoc IVoter
    uint256 public totalWeight;
    /// @inheritdoc IVoter
    uint256 public maxVotingNum;
    uint256 internal constant MIN_MAXVOTINGNUM = 10;

    /// @dev All pools viable for incentives
    address[] public pools;
    /// @inheritdoc IVoter
    mapping(address => address) public gauges;
    /// @inheritdoc IVoter
    mapping(address => address) public poolForGauge;
    /// @inheritdoc IVoter
    mapping(address => address) public gaugeToFees;
    /// @inheritdoc IVoter
    mapping(address => address) public gaugeToBribe;
    /// @inheritdoc IVoter
    mapping(address => uint256) public weights;
    /// @inheritdoc IVoter
    mapping(uint256 => mapping(address => uint256)) public votes;
    /// @dev NFT => List of pools voted for by NFT
    mapping(uint256 => address[]) public poolVote;
    /// @inheritdoc IVoter
    mapping(uint256 => uint256) public usedWeights;
    /// @inheritdoc IVoter
    mapping(uint256 => uint256) public lastVoted;
    /// @inheritdoc IVoter
    mapping(address => bool) public isGauge;
    /// @inheritdoc IBaseVoter
    mapping(address => bool) public isWhitelistedToken;
    /// @inheritdoc IVoter
    mapping(uint256 => bool) public isWhitelistedNFT;
    /// @inheritdoc IVoter
    mapping(address => bool) public isAlive;
    /// @dev Accumulated distributions per vote
    uint256 internal index;
    /// @dev Gauge => Accumulated gauge distributions
    mapping(address => uint256) internal supplyIndex;
    /// @inheritdoc IVoter
    mapping(address => uint256) public claimable;

    /// @notice Constructor to set the trusted forwarder for ERC2771.
    /// @param _forwarder The address of the trusted forwarder
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        if (_forwarder == address(0)) revert ZeroAddress();
        forwarder = _forwarder; // immutable so can set in constructor
        _disableInitializers();
    }

    function initialize(
        address _ve,
        address _factoryRegistry,
        address _rewardToken
    ) external initializer {
        __ReentrancyGuard_init();

        ve = _ve;
        factoryRegistry = _factoryRegistry;
        rewardToken = _rewardToken;
        address _sender = _msgSender();
        splitter = _sender;
        governor = _sender;
        emergencyCouncil = _sender;
        maxVotingNum = 30;
    }

    /// @notice Configure initial tokens and splitter. Should be called after
    ///         initialization.
    /// @dev It is kept separately from initialize as there is a circular
    ///      dependency between splitter and voter, and we want deployment and
    ///      initialization to happen in the same transaction.
    /// @param _tokens Array of tokens to whitelist
    /// @param _splitter Address of the splitter contract
    function configureSplitterAndTokens(
        address[] calldata _tokens,
        address _splitter
    ) external {
        if (_msgSender() != splitter) revert NotSplitter();
        if (_splitter == address(0)) revert ZeroAddress();

        splitter = _splitter;

        // Whitelist initial tokens
        uint256 _length = _tokens.length;
        for (uint256 i = 0; i < _length; i++) {
            _whitelistToken(_tokens[i], true);
        }
    }

    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure new epoch since last vote
        if (
            ProtocolTimeLibrary.epochStart(block.timestamp) <=
            lastVoted[_tokenId]
        ) revert AlreadyVotedOrDeposited();
        if (
            block.timestamp <=
            ProtocolTimeLibrary.epochVoteStart(block.timestamp)
        ) revert DistributeWindow();
        _;
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return ProtocolTimeLibrary.epochStart(_timestamp);
    }

    function epochNext(uint256 _timestamp) external pure returns (uint256) {
        return ProtocolTimeLibrary.epochNext(_timestamp);
    }

    function epochVoteStart(
        uint256 _timestamp
    ) external pure returns (uint256) {
        return ProtocolTimeLibrary.epochVoteStart(_timestamp);
    }

    function epochVoteEnd(uint256 _timestamp) external pure returns (uint256) {
        return ProtocolTimeLibrary.epochVoteEnd(_timestamp);
    }

    /// @inheritdoc IVoter
    function setGovernor(address _governor) public {
        if (_msgSender() != governor) revert NotGovernor();
        if (_governor == address(0)) revert ZeroAddress();
        governor = _governor;
    }

    /// @inheritdoc IVoter
    function setEmergencyCouncil(address _council) public {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (_council == address(0)) revert ZeroAddress();
        emergencyCouncil = _council;
    }

    /// @inheritdoc IVoter
    function setSplitter(address _splitter) external {
        if (_msgSender() != governor) revert NotGovernor();
        // Disallow setting the splitter to zero address.
        // This ensures proper execution of the contract
        // logic that returns unclaimed rewards for killed gauges
        // back to the splitter.
        if (_splitter == address(0)) revert ZeroAddress();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }

    /// @inheritdoc IVoter
    function setMaxVotingNum(uint256 _maxVotingNum) external {
        if (_msgSender() != governor) revert NotGovernor();
        if (_maxVotingNum < MIN_MAXVOTINGNUM)
            revert MaximumVotingNumberTooLow();
        if (_maxVotingNum == maxVotingNum) revert SameValue();
        maxVotingNum = _maxVotingNum;
    }

    /// @inheritdoc IVoter
    function reset(
        uint256 _tokenId
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId))
            revert NotApprovedOrOwner();
        _reset(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                delete votes[_tokenId][_pool];
                IReward(gaugeToFees[gauges[_pool]])._withdraw(_votes, _tokenId);
                IReward(gaugeToBribe[gauges[_pool]])._withdraw(
                    _votes,
                    _tokenId
                );
                _totalWeight += _votes;
                emit Abstained(
                    _msgSender(),
                    _pool,
                    _tokenId,
                    _votes,
                    weights[_pool],
                    block.timestamp
                );
            }
        }
        IVotingEscrow(ve).voting(_tokenId, false);
        totalWeight -= _totalWeight;
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }

    /// @inheritdoc IVoter
    function poke(uint256 _tokenId) external nonReentrant {
        if (
            block.timestamp <=
            ProtocolTimeLibrary.epochVoteStart(block.timestamp)
        ) revert DistributeWindow();
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFT(_tokenId);
        _poke(_tokenId, _weight);
    }

    function _poke(uint256 _tokenId, uint256 _weight) internal {
        address[] memory _poolVote = poolVote[_tokenId];
        uint256 _poolCnt = _poolVote.length;

        // Count pools with alive gauges
        uint256 _aliveCnt = 0;
        for (uint256 i = 0; i < _poolCnt; i++) {
            if (isAlive[gauges[_poolVote[i]]]) {
                _aliveCnt++;
            }
        }

        // Build arrays with only pools that have alive gauges
        address[] memory _alivePools = new address[](_aliveCnt);
        uint256[] memory _aliveWeights = new uint256[](_aliveCnt);

        uint256 j = 0;
        for (uint256 i = 0; i < _poolCnt; i++) {
            if (isAlive[gauges[_poolVote[i]]]) {
                _alivePools[j] = _poolVote[i];
                _aliveWeights[j] = votes[_tokenId][_poolVote[i]];
                j++;
            }
        }

        // Pass only pools with alive gauges to _vote(). Weight that was allocated
        // to killed gauges is proportionally redistributed among the remaining live gauges.
        // If all gauges are dead, empty arrays cause _vote() to effectively reset.
        _vote(_tokenId, _weight, _alivePools, _aliveWeights);
    }

    function _vote(
        uint256 _tokenId,
        uint256 _weight,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];
            if (_gauge == address(0)) revert GaugeDoesNotExist(_pool);
            if (!isAlive[_gauge]) revert GaugeNotAlive(_gauge);

            uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;
            if (votes[_tokenId][_pool] != 0) revert NonZeroVotes();
            if (_poolWeight == 0) revert ZeroBalance();
            _updateFor(_gauge);

            poolVote[_tokenId].push(_pool);

            weights[_pool] += _poolWeight;
            votes[_tokenId][_pool] += _poolWeight;
            IReward(gaugeToFees[_gauge])._deposit(_poolWeight, _tokenId);
            IReward(gaugeToBribe[_gauge])._deposit(_poolWeight, _tokenId);
            _usedWeight += _poolWeight;
            _totalWeight += _poolWeight;
            emit Voted(
                _msgSender(),
                _pool,
                _tokenId,
                _poolWeight,
                weights[_pool],
                block.timestamp
            );
        }
        if (_usedWeight > 0) IVotingEscrow(ve).voting(_tokenId, true);
        totalWeight += _totalWeight;
        usedWeights[_tokenId] = _usedWeight;
    }

    /// @inheritdoc IVoter
    function vote(
        uint256 _tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        address _sender = _msgSender();
        if (!IVotingEscrow(ve).isApprovedOrOwner(_sender, _tokenId))
            revert NotApprovedOrOwner();
        if (_poolVote.length != _weights.length) revert UnequalLengths();
        if (_poolVote.length > maxVotingNum) revert TooManyPools();
        if (IVotingEscrow(ve).deactivated(_tokenId))
            revert InactiveManagedNFT();
        uint256 _timestamp = block.timestamp;
        if (
            (_timestamp > ProtocolTimeLibrary.epochVoteEnd(_timestamp)) &&
            !isWhitelistedNFT[_tokenId]
        ) revert NotWhitelistedNFT();
        lastVoted[_tokenId] = _timestamp;
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFT(_tokenId);
        _vote(_tokenId, _weight, _poolVote, _weights);
    }

    /// @inheritdoc IVoter
    function depositManaged(
        uint256 _tokenId,
        uint256 _mTokenId
    ) external nonReentrant onlyNewEpoch(_tokenId) {
        address _sender = _msgSender();
        if (!IVotingEscrow(ve).isApprovedOrOwner(_sender, _tokenId))
            revert NotApprovedOrOwner();
        if (IVotingEscrow(ve).deactivated(_mTokenId))
            revert InactiveManagedNFT();
        uint256 _timestamp = block.timestamp;
        if (_timestamp > ProtocolTimeLibrary.epochVoteEnd(_timestamp))
            revert SpecialVotingWindow();
        lastVoted[_tokenId] = _timestamp;
        IVotingEscrow(ve).depositManaged(_tokenId, _mTokenId);
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFTAt(
            _mTokenId,
            block.timestamp
        );
        _poke(_mTokenId, _weight);
    }

    /// @inheritdoc IVoter
    function withdrawManaged(
        uint256 _tokenId
    ) external nonReentrant onlyNewEpoch(_tokenId) {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId))
            revert NotApprovedOrOwner();
        uint256 _mTokenId = IVotingEscrow(ve).idToManaged(_tokenId);
        IVotingEscrow(ve).withdrawManaged(_tokenId);
        // If the NORMAL veNFT was the last tokenId locked into _mTokenId, reset vote as there is
        // no longer voting power available to the _mTokenId.  Otherwise, updating voting power to accurately
        // reflect the withdrawn voting power.
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFTAt(
            _mTokenId,
            block.timestamp
        );
        if (_weight == 0) {
            _reset(_mTokenId);
            // clear out lastVoted to allow re-voting in the current epoch
            delete lastVoted[_mTokenId];
        } else {
            _poke(_mTokenId, _weight);
        }
    }

    /// @inheritdoc IVoter
    function whitelistToken(address _token, bool _bool) external {
        if (_msgSender() != governor) revert NotGovernor();
        _whitelistToken(_token, _bool);
    }

    function _whitelistToken(address _token, bool _bool) internal {
        isWhitelistedToken[_token] = _bool;
        emit WhitelistToken(_msgSender(), _token, _bool);
    }

    /// @inheritdoc IVoter
    function whitelistNFT(uint256 _tokenId, bool _bool) external {
        address _sender = _msgSender();
        if (_sender != governor) revert NotGovernor();
        isWhitelistedNFT[_tokenId] = _bool;
        emit WhitelistNFT(_sender, _tokenId, _bool);
    }

    /// @inheritdoc IVoter
    function createPoolGauge(
        address _poolFactory,
        address _pool
    ) external nonReentrant returns (address) {
        address sender = _msgSender();
        if (
            !IFactoryRegistry(factoryRegistry).isPoolFactoryApproved(
                _poolFactory
            )
        ) revert FactoryPathNotApproved();

        bool isPool = IPoolFactory(_poolFactory).isPool(_pool);
        if (!isPool) revert NotAPool();

        address token0 = IPool(_pool).token0();
        address token1 = IPool(_pool).token1();

        // Allow governor to bypass whitelist check
        if (sender != governor) {
            if (!isWhitelistedToken[token0] || !isWhitelistedToken[token1])
                revert NotWhitelistedToken();
        }

        address[] memory rewards = new address[](2);
        rewards[0] = token0;
        rewards[1] = token1;

        (, address gaugeFactory) = IFactoryRegistry(factoryRegistry)
            .factoriesToPoolFactory(_poolFactory);

        return
            _createGauge(
                IStakingGaugeFactory.StakingGaugeType.Pool,
                _poolFactory,
                gaugeFactory,
                _pool,
                rewards,
                sender
            );
    }

    /// @inheritdoc IVoter
    function createVaultGauge(
        address _gaugeFactory,
        address _vault
    ) external nonReentrant returns (address) {
        address sender = _msgSender();
        if (sender != governor) {
            revert NotGovernor();
        }
        address feeToken = IVault(_vault).yieldToken();
        address[] memory rewards = new address[](1);
        rewards[0] = feeToken;

        return
            _createGauge(
                IStakingGaugeFactory.StakingGaugeType.Vault,
                address(0),
                _gaugeFactory,
                _vault,
                rewards,
                sender
            );
    }

    /// @inheritdoc IVoter
    function createNoFeesGauge(
        address _gaugeFactory,
        address _stakingToken
    ) external nonReentrant returns (address) {
        address sender = _msgSender();
        if (sender != governor) {
            revert NotGovernor();
        }
        address[] memory rewards = new address[](0);

        return
            _createGauge(
                IStakingGaugeFactory.StakingGaugeType.NoFees,
                address(0),
                _gaugeFactory,
                _stakingToken,
                rewards,
                sender
            );
    }

    /// @inheritdoc IVoter
    function killGauge(address _gauge) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (!isAlive[_gauge]) revert GaugeAlreadyKilled();
        // Return claimable back to splitter
        uint256 _claimable = claimable[_gauge];
        if (_claimable > 0) {
            IERC20(rewardToken).safeTransfer(splitter, _claimable);
            delete claimable[_gauge];
        }
        isAlive[_gauge] = false;
        emit GaugeKilled(_gauge);
    }

    /// @inheritdoc IVoter
    function reviveGauge(address _gauge) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (isAlive[_gauge]) revert GaugeAlreadyRevived();
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    /// @inheritdoc IVoter
    function length() external view returns (uint256) {
        return pools.length;
    }

    /// @inheritdoc IVoter
    function notifyRewardAmount(uint256 _amount) external {
        address sender = _msgSender();
        if (sender != splitter) revert NotSplitter();
        IERC20(rewardToken).safeTransferFrom(sender, address(this), _amount); // transfer the distribution in
        uint256 _ratio = (_amount * 1e18) / Math.max(totalWeight, 1); // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }
        emit NotifyReward(sender, rewardToken, _amount);
    }

    /// @inheritdoc IVoter
    function updateFor(address[] memory _gauges) external {
        uint256 _length = _gauges.length;
        for (uint256 i = 0; i < _length; i++) {
            _updateFor(_gauges[i]);
        }
    }

    /// @inheritdoc IVoter
    function updateFor(uint256 start, uint256 end) external {
        for (uint256 i = start; i < end; i++) {
            _updateFor(gauges[pools[i]]);
        }
    }

    /// @inheritdoc IVoter
    function updateFor(address _gauge) external {
        _updateFor(_gauge);
    }

    function _createGauge(
        IStakingGaugeFactory.StakingGaugeType _type,
        address _poolFactory,
        address _gaugeFactory,
        address _entity,
        address[] memory _rewards,
        address _sender
    ) internal returns (address gauge) {
        if (gauges[_entity] != address(0)) revert GaugeExists();
        if (
            !IFactoryRegistry(factoryRegistry).isGaugeFactoryApproved(
                _gaugeFactory
            )
        ) revert FactoryPathNotApproved();

        address votingRewardsFactory = IFactoryRegistry(factoryRegistry)
            .gaugeFactoryToVotingRewardsFactory(_gaugeFactory);

        (
            address _feeVotingReward,
            address _bribeVotingReward
        ) = IVotingRewardsFactory(votingRewardsFactory).createRewards(
                forwarder,
                _rewards
            );

        gauge = IStakingGaugeFactory(_gaugeFactory).createStakingGauge(
            _type,
            forwarder,
            _entity,
            _feeVotingReward,
            rewardToken
        );

        gaugeToFees[gauge] = _feeVotingReward;
        gaugeToBribe[gauge] = _bribeVotingReward;
        gauges[_entity] = gauge;
        poolForGauge[gauge] = _entity;
        isGauge[gauge] = true;
        isAlive[gauge] = true;
        _updateFor(gauge);
        pools.push(_entity);

        emit GaugeCreated(
            _poolFactory,
            votingRewardsFactory,
            _gaugeFactory,
            _entity,
            _bribeVotingReward,
            _feeVotingReward,
            gauge,
            _sender
        );
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        if (_supplied > 0) {
            uint256 _supplyIndex = supplyIndex[_gauge];
            uint256 _index = index; // get global index0 for accumulated distribution
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                uint256 _share = (_supplied * _delta) / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                } else {
                    IERC20(rewardToken).safeTransfer(splitter, _share); // send rewards back to Splitter so they're not stuck in Voter
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    /// @inheritdoc IVoter
    function claimRewards(address[] memory _gauges) external {
        uint256 _length = _gauges.length;
        for (uint256 i = 0; i < _length; i++) {
            IGauge(_gauges[i]).getReward(_msgSender());
        }
    }

    /// @inheritdoc IVoter
    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        _claimRewards(_bribes, _tokens, _tokenId);
    }

    /// @inheritdoc IVoter
    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        _claimRewards(_fees, _tokens, _tokenId);
    }

    /// @inheritdoc IVoter
    function claimFeesAndBribes(
        address[] memory _rewards,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        _claimRewards(_rewards, _tokens, _tokenId);
    }

    /// @dev Internal function to claim rewards for a given NFT.
    /// @param _rewards Array of Reward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as rewards.
    /// @param _tokenId Id of veNFT that you wish to claim rewards for.
    function _claimRewards(
        address[] memory _rewards,
        address[][] memory _tokens,
        uint256 _tokenId
    ) public {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId))
            revert NotApprovedOrOwner();
        uint256 _length = _rewards.length;
        for (uint256 i = 0; i < _length; i++) {
            IReward(_rewards[i]).getReward(_tokenId, _tokens[i]);
        }
    }

    function _distribute(address _gauge) internal {
        _updateFor(_gauge); // should set claimable to 0 if killed
        uint256 _claimable = claimable[_gauge];
        if (_claimable > IGauge(_gauge).left() && _claimable > DURATION) {
            claimable[_gauge] = 0;
            IERC20(rewardToken).safeApprove(_gauge, _claimable);
            IGauge(_gauge).notifyRewardAmount(_claimable);
            IERC20(rewardToken).safeApprove(_gauge, 0);
            emit DistributeReward(_msgSender(), _gauge, _claimable);
        }
    }

    /// @inheritdoc IVoter
    function distribute(uint256 _start, uint256 _finish) external nonReentrant {
        ISplitter(splitter).updatePeriod();
        for (uint256 x = _start; x < _finish; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    /// @inheritdoc IVoter
    function distribute(address[] memory _gauges) external nonReentrant {
        ISplitter(splitter).updatePeriod();
        uint256 _length = _gauges.length;
        for (uint256 x = 0; x < _length; x++) {
            _distribute(_gauges[x]);
        }
    }
}
