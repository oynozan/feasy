// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {ISplitter} from "./interfaces/ISplitter.sol";
import {IReward} from "./interfaces/IReward.sol";
import {INonStakingVoter} from "./interfaces/INonStakingVoter.sol";
import {IBaseVoter} from "./interfaces/IBaseVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";
import {IFactoryRegistry} from "./interfaces/factories/IFactoryRegistry.sol";
import {IGaugeFactory} from "./interfaces/factories/IGaugeFactory.sol";
import {IVotingRewardsFactory} from "./interfaces/factories/IVotingRewardsFactory.sol";

/// @title Non-staking voter
/// @notice Manage votes, emission distribution, and provides lifecycle hooks for non-staking gauges.
///         Simplified version of voter that works with non-staking gauge contracts.
/// @dev This contract abstracts away:
///      - Gauge creation. Child contract MUST implement a gauge creation logic
///        that MUST call the _createGauge function to deploy a new gauge.
///      - Gauge killing and reviving. Child contract MAY implement its own killing
///        and reviving logic, but MUST call _onGaugeKilled and _onGaugeRevived
///        hooks to ensure proper state transitions.
abstract contract NonStakingVoter is
    INonStakingVoter,
    Initializable,
    ERC2771ContextUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    /// @inheritdoc INonStakingVoter
    /// @dev We need to store the forwarder address because ERC2771ContextUpgradeable
    ///      doesn't expose it publicly, but we need to pass it to factories
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable forwarder;
    /// @inheritdoc IBaseVoter
    address public ve;
    /// @inheritdoc INonStakingVoter
    address public factoryRegistry;
    /// @notice Reward token received from the splitter and distributed to the gauges.
    /// @dev It can be set upon initialization but MUST NOT be changed once initialized.
    ///      This is because the immutable gauges are created with this reward token and
    ///      they only accept this specific token. Changing the reward token in the voter
    ///      would cause failures while calling distribute for gauges supporting the old
    ///      token and would break the entire rewards math in the voter.
    address public rewardToken;
    /// @notice Rewards are released over 7 days
    uint256 internal constant DURATION = 7 days;
    /// @inheritdoc INonStakingVoter
    address public splitter;
    /// @inheritdoc IBaseVoter
    address public governor;

    /// @inheritdoc INonStakingVoter
    uint256 public totalWeight;
    /// @inheritdoc INonStakingVoter
    uint256 public maxVotingNum;
    uint256 internal constant MIN_MAXVOTINGNUM = 10;

    /// @dev All gauges
    address[] public gauges;
    /// @inheritdoc INonStakingVoter
    mapping(address => address) public gaugeToBribe;
    /// @inheritdoc INonStakingVoter
    mapping(address => uint256) public weights;
    /// @inheritdoc INonStakingVoter
    mapping(uint256 => mapping(address => uint256)) public votes;
    /// @dev NFT => List of gauges voted for by NFT
    mapping(uint256 => address[]) public gaugeVote;
    /// @inheritdoc INonStakingVoter
    mapping(uint256 => uint256) public usedWeights;
    /// @inheritdoc INonStakingVoter
    mapping(uint256 => uint256) public lastVoted;
    /// @inheritdoc INonStakingVoter
    mapping(address => bool) public isGauge;
    /// @inheritdoc IBaseVoter
    mapping(address => bool) public isWhitelistedToken;
    /// @inheritdoc INonStakingVoter
    mapping(uint256 => bool) public isWhitelistedNFT;
    /// @inheritdoc INonStakingVoter
    mapping(address => bool) public isAlive;
    /// @dev Accumulated distributions per vote
    uint256 internal index;
    /// @dev Gauge => Accumulated gauge distributions
    mapping(address => uint256) internal supplyIndex;
    /// @inheritdoc INonStakingVoter
    mapping(address => uint256) public claimable;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;

    /// @notice Constructor to set the trusted forwarder for ERC2771.
    /// @param _forwarder The address of the trusted forwarder
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        if (_forwarder == address(0)) revert ZeroAddress();
        forwarder = _forwarder; // immutable so can set in constructor
        _disableInitializers();
    }

    function __NonStakingVoter_init(
        address _ve,
        address _factoryRegistry,
        address _rewardToken
    ) internal onlyInitializing {
        __ReentrancyGuard_init();

        if (_ve == address(0)) revert ZeroAddress();
        if (_factoryRegistry == address(0)) revert ZeroAddress();

        ve = _ve;
        factoryRegistry = _factoryRegistry;
        // Reward token is set upon initialization and cannot be changed later.
        // This token can be 0x0 though. This is a valid case for voters
        // not supporting reward emissions.
        rewardToken = _rewardToken;

        address _sender = _msgSender();
        splitter = _sender;
        governor = _sender;
        maxVotingNum = 30;
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

    /// @inheritdoc IBaseVoter
    function emergencyCouncil() external view virtual returns (address) {
        return governor;
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

    /// @notice Updates the splitter address.
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

    /// @inheritdoc INonStakingVoter
    function setGovernor(address _governor) external {
        if (_msgSender() != governor) revert NotGovernor();
        if (_governor == address(0)) revert ZeroAddress();
        governor = _governor;
    }

    /// @inheritdoc INonStakingVoter
    function setMaxVotingNum(uint256 _maxVotingNum) external {
        if (_msgSender() != governor) revert NotGovernor();
        if (_maxVotingNum < MIN_MAXVOTINGNUM)
            revert MaximumVotingNumberTooLow();
        if (_maxVotingNum == maxVotingNum) revert SameValue();
        maxVotingNum = _maxVotingNum;
    }

    /// @inheritdoc INonStakingVoter
    function reset(
        uint256 _tokenId
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId))
            revert NotApprovedOrOwner();
        _reset(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _gaugeVote = gaugeVote[_tokenId];
        uint256 _gaugeVoteCnt = _gaugeVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _gaugeVoteCnt; i++) {
            address _gauge = _gaugeVote[i];
            uint256 _votes = votes[_tokenId][_gauge];

            if (_votes != 0) {
                _updateFor(_gauge);
                weights[_gauge] -= _votes;
                delete votes[_tokenId][_gauge];
                IReward(gaugeToBribe[_gauge])._withdraw(_votes, _tokenId);
                _totalWeight += _votes;
                emit Abstained(
                    _msgSender(),
                    _gauge,
                    _tokenId,
                    _votes,
                    weights[_gauge],
                    block.timestamp
                );
            }
        }
        IVotingEscrow(ve).voting(_tokenId, false);
        totalWeight -= _totalWeight;
        usedWeights[_tokenId] = 0;
        delete gaugeVote[_tokenId];
    }

    /// @inheritdoc INonStakingVoter
    function poke(uint256 _tokenId) external nonReentrant {
        if (
            block.timestamp <=
            ProtocolTimeLibrary.epochVoteStart(block.timestamp)
        ) revert DistributeWindow();
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFT(_tokenId);
        _poke(_tokenId, _weight);
    }

    function _poke(uint256 _tokenId, uint256 _weight) internal {
        address[] memory _gaugeVote = gaugeVote[_tokenId];
        uint256 _gaugeCnt = _gaugeVote.length;

        // Count alive gauges
        uint256 _aliveCnt = 0;
        for (uint256 i = 0; i < _gaugeCnt; i++) {
            if (isAlive[_gaugeVote[i]]) {
                _aliveCnt++;
            }
        }

        // Build arrays with only alive gauges
        address[] memory _aliveGauges = new address[](_aliveCnt);
        uint256[] memory _aliveWeights = new uint256[](_aliveCnt);

        uint256 j = 0;
        for (uint256 i = 0; i < _gaugeCnt; i++) {
            if (isAlive[_gaugeVote[i]]) {
                _aliveGauges[j] = _gaugeVote[i];
                _aliveWeights[j] = votes[_tokenId][_gaugeVote[i]];
                j++;
            }
        }

        // Pass only alive gauges to _vote(). Weight that was allocated to killed
        // gauges is proportionally redistributed among the remaining live gauges.
        // If all gauges are dead, empty arrays cause _vote() to effectively reset.
        _vote(_tokenId, _weight, _aliveGauges, _aliveWeights);
    }

    function _vote(
        uint256 _tokenId,
        uint256 _weight,
        address[] memory _gaugeVote,
        uint256[] memory _weights
    ) internal {
        _reset(_tokenId);
        uint256 _gaugeCnt = _gaugeVote.length;
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _gaugeCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _gaugeCnt; i++) {
            address _gauge = _gaugeVote[i];
            if (!isGauge[_gauge]) revert GaugeDoesNotExist(_gauge);
            if (!isAlive[_gauge]) revert GaugeNotAlive(_gauge);

            uint256 _gaugeWeight = (_weights[i] * _weight) / _totalVoteWeight;
            if (votes[_tokenId][_gauge] != 0) revert NonZeroVotes();
            if (_gaugeWeight == 0) revert ZeroBalance();
            _updateFor(_gauge);

            gaugeVote[_tokenId].push(_gauge);

            weights[_gauge] += _gaugeWeight;
            votes[_tokenId][_gauge] += _gaugeWeight;
            IReward(gaugeToBribe[_gauge])._deposit(_gaugeWeight, _tokenId);
            _usedWeight += _gaugeWeight;
            _totalWeight += _gaugeWeight;
            emit Voted(
                _msgSender(),
                _gauge,
                _tokenId,
                _gaugeWeight,
                weights[_gauge],
                block.timestamp
            );
        }
        if (_usedWeight > 0) IVotingEscrow(ve).voting(_tokenId, true);
        totalWeight += _totalWeight;
        usedWeights[_tokenId] = _usedWeight;
    }

    /// @inheritdoc INonStakingVoter
    function vote(
        uint256 _tokenId,
        address[] calldata _gaugeVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        address _sender = _msgSender();
        if (!IVotingEscrow(ve).isApprovedOrOwner(_sender, _tokenId))
            revert NotApprovedOrOwner();
        if (_gaugeVote.length != _weights.length) revert UnequalLengths();
        if (_gaugeVote.length > maxVotingNum) revert TooManyGauges();
        if (IVotingEscrow(ve).deactivated(_tokenId))
            revert InactiveManagedNFT();
        uint256 _timestamp = block.timestamp;
        if (
            (_timestamp > ProtocolTimeLibrary.epochVoteEnd(_timestamp)) &&
            !isWhitelistedNFT[_tokenId]
        ) revert NotWhitelistedNFT();
        lastVoted[_tokenId] = _timestamp;
        uint256 _weight = IVotingEscrow(ve).votingPowerOfNFT(_tokenId);
        _vote(_tokenId, _weight, _gaugeVote, _weights);
    }

    /// @inheritdoc INonStakingVoter
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

    /// @inheritdoc INonStakingVoter
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

    /// @inheritdoc INonStakingVoter
    function whitelistToken(address _token, bool _bool) external {
        if (_msgSender() != governor) revert NotGovernor();
        _whitelistToken(_token, _bool);
    }

    function _whitelistToken(address _token, bool _bool) internal {
        isWhitelistedToken[_token] = _bool;
        emit WhitelistToken(_msgSender(), _token, _bool);
    }

    /// @inheritdoc INonStakingVoter
    function whitelistNFT(uint256 _tokenId, bool _bool) external {
        address _sender = _msgSender();
        if (_sender != governor) revert NotGovernor();
        isWhitelistedNFT[_tokenId] = _bool;
        emit WhitelistNFT(_sender, _tokenId, _bool);
    }

    /// @dev Function that MUST be called by child contract's gauge creation logic.
    function _createGauge(
        address _gaugeFactory,
        address _rewardsBeneficiary
    ) internal returns (address) {
        if (
            !IFactoryRegistry(factoryRegistry).isGaugeFactoryApproved(
                _gaugeFactory
            )
        ) revert GaugeFactoryNotApproved();

        address votingRewardsFactory = IFactoryRegistry(factoryRegistry)
            .gaugeFactoryToVotingRewardsFactory(_gaugeFactory);

        address gauge = IGaugeFactory(_gaugeFactory).createNonStakingGauge(
            forwarder,
            rewardToken,
            _rewardsBeneficiary
        );

        address bribeVotingReward = IVotingRewardsFactory(votingRewardsFactory)
            .createBribeReward(forwarder, new address[](0));

        gaugeToBribe[gauge] = bribeVotingReward;
        isGauge[gauge] = true;
        isAlive[gauge] = true;
        _updateFor(gauge);
        gauges.push(gauge);

        emit GaugeCreated(gauge, bribeVotingReward, _msgSender());

        return gauge;
    }

    /// @dev Hook that MUST be called upon gauge killing in the child contract.
    ///      Performs state changes that mark the gauge as killed.
    ///      The gauge will not receive any new emissions and cannot be voted for.
    ///      Gauge can still withdraw rewards.
    function _onGaugeKilled(address _gauge) internal {
        if (!isGauge[_gauge]) revert GaugeDoesNotExist(_gauge);
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

    /// @dev Hook that MUST be called upon gauge revival in the child contract.
    ///      Performs state changes that mark the gauge as revived.
    ///      The gauge can receive emissions and votes again.
    function _onGaugeRevived(address _gauge) internal {
        if (!isGauge[_gauge]) revert GaugeDoesNotExist(_gauge);
        if (isAlive[_gauge]) revert GaugeAlreadyRevived();
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    /// @inheritdoc INonStakingVoter
    function length() external view returns (uint256) {
        return gauges.length;
    }

    /// @inheritdoc INonStakingVoter
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

    /// @inheritdoc INonStakingVoter
    function updateFor(address[] memory _gauges) external {
        uint256 _length = _gauges.length;
        for (uint256 i = 0; i < _length; i++) {
            _updateFor(_gauges[i]);
        }
    }

    /// @inheritdoc INonStakingVoter
    function updateFor(uint256 start, uint256 end) external {
        for (uint256 i = start; i < end; i++) {
            _updateFor(gauges[i]);
        }
    }

    /// @inheritdoc INonStakingVoter
    function updateFor(address _gauge) external {
        _updateFor(_gauge);
    }

    function _updateFor(address _gauge) internal {
        uint256 _supplied = weights[_gauge];
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

    /// @inheritdoc INonStakingVoter
    function claimRewards(address[] memory _gauges) external {
        uint256 _length = _gauges.length;
        for (uint256 i = 0; i < _length; i++) {
            IGauge(_gauges[i]).getReward(_msgSender());
        }
    }

    /// @inheritdoc INonStakingVoter
    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), _tokenId))
            revert NotApprovedOrOwner();
        uint256 _length = _bribes.length;
        for (uint256 i = 0; i < _length; i++) {
            IReward(_bribes[i]).getReward(_tokenId, _tokens[i]);
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

    /// @inheritdoc INonStakingVoter
    function distribute(uint256 _start, uint256 _finish) external nonReentrant {
        ISplitter(splitter).updatePeriod();
        for (uint256 x = _start; x < _finish; x++) {
            _distribute(gauges[x]);
        }
    }

    /// @inheritdoc INonStakingVoter
    function distribute(address[] memory _gauges) external nonReentrant {
        ISplitter(splitter).updatePeriod();
        uint256 _length = _gauges.length;
        for (uint256 x = 0; x < _length; x++) {
            _distribute(_gauges[x]);
        }
    }

    /// @inheritdoc INonStakingVoter
    function addBribes(
        address _gauge,
        address[] memory _tokens,
        uint256[] memory _amounts
    ) external nonReentrant {
        _addBribes(_msgSender(), _gauge, _tokens, _amounts);
    }

    /// @notice Internal function to add voting bribes to a specific gauge.
    /// @param _sender The address of the sender adding bribes.
    /// @param _gauge The address of the gauge to add bribes to.
    /// @param _tokens The addresses of the bribe tokens.
    /// @param _amounts The amounts of the bribe tokens.
    /// @dev Requirements:
    ///      - The tokens array length must be greater than zero
    ///      - The tokens and amounts arrays must have the same length
    ///      - The gauge must exist and be alive
    ///      - The tokens must be whitelisted
    ///      - The sender must have enough balance of the tokens
    ///      - The sender must grant approval to the voter contract for the tokens
    function _addBribes(
        address _sender,
        address _gauge,
        address[] memory _tokens,
        uint256[] memory _amounts
    ) internal {
        if (_tokens.length == 0) revert ZeroLength();
        if (_tokens.length != _amounts.length) revert UnequalLengths();

        if (!isGauge[_gauge]) revert GaugeDoesNotExist(_gauge);
        if (!isAlive[_gauge]) revert GaugeNotAlive(_gauge);

        address bribeVotingReward = gaugeToBribe[_gauge];

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint256 amount = _amounts[i];

            if (!isWhitelistedToken[token]) revert NotWhitelistedToken();

            IERC20(token).safeTransferFrom(_sender, address(this), amount);
            IERC20(token).forceApprove(bribeVotingReward, amount);
            IReward(bribeVotingReward).notifyRewardAmount(token, amount);

            emit BribesAdded(_gauge, token, amount, _sender);
        }
    }
}
