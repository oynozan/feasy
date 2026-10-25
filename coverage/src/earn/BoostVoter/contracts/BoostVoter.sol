// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import {NonStakingVoter} from "./NonStakingVoter.sol";
import {IFactoryRegistry} from "./interfaces/factories/IFactoryRegistry.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IReward} from "./interfaces/IReward.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BoostLibrary} from "./libraries/BoostLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVotingEscrowBooster} from "./interfaces/IVotingEscrowBooster.sol";

/// @title BoostVoter
/// @notice Contract allowing to vote with one type of veNFT (voting veNFT) on
///         another type of veNFT (boostable veNFT). Accrued voting weight boosts
///         the voting power of the boostable veNFT. Boostable veNFT holders may
///         allocate voting bribes to encourage voting veNFT holders to vote
contract BoostVoter is NonStakingVoter, IVotingEscrowBooster {
    using SafeERC20 for IERC20;

    /// @notice Address of the VotingEscrow that is boostable
    address public boostableVe;
    /// @notice Mapping from boostable token ID to its associated gauge address
    mapping(uint256 => address) public boostableTokenIdToGauge;

    event BoostGaugeCreated(
        uint256 indexed boostableTokenId,
        address indexed gauge
    );
    event BoostPoked(uint256 indexed boostableTokenId, uint256 boost);
    event BoostableTokenBurned(
        uint256 indexed boostableTokenId,
        address indexed gauge
    );

    error UnsupportedEscrowType(IVotingEscrow.EscrowType escrowType);
    error LockDoesNotExist();
    error LockExpired();
    error GaugeExistsForLock();
    error NotBoostableVe();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _forwarder) NonStakingVoter(_forwarder) {
        _disableInitializers();
    }

    /// @notice Initializes the BoostVoter contract
    /// @param _votingVe Address of the VotingEscrow that votes
    /// @param _boostableVe Address of the VotingEscrow that is boostable
    /// @param _factoryRegistry Address of the FactoryRegistry
    function initialize(
        address _votingVe,
        address _boostableVe,
        address _factoryRegistry
    ) external initializer {
        __NonStakingVoter_init(_votingVe, _factoryRegistry, address(0));

        if (_boostableVe == address(0)) revert ZeroAddress();

        boostableVe = _boostableVe;
    }

    /// @notice Creates a new NonStakingGauge for a boostable veNFT
    ///         voting veNFTs can vote for. Optionally adds
    ///         initial voting bribes.
    /// @param gaugeFactory The address of the gauge factory to use
    /// @param boostableTokenId The ID of the boostable veNFT
    /// @param tokens The addresses of the bribe tokens
    /// @param amounts The amounts of the bribe tokens
    /// @return The address of the newly created gauge
    /// @dev Requirements:
    ///      - The caller must be approved or owner of the boostable veNFT
    ///      - The boostable veNFT must be MANAGED or NORMAL escrow type
    ///      - The boostable veNFT must exist
    ///      - The boostable veNFT must not be expired (unless permanent)
    ///      - No gauge must not already exist for this boostable veNFT
    ///      - The gauge factory must be approved in the factory registry
    ///      - Optionally, if tokens is not empty:
    ///        - The tokens and amounts arrays must have the same length
    ///        - The tokens must be whitelisted
    ///        - The sender must have enough balance of the tokens
    ///        - The sender must grant approval to the BoostVoter contract for the tokens
    function createBoostGauge(
        address gaugeFactory,
        uint256 boostableTokenId,
        address[] memory tokens,
        uint256[] memory amounts
    ) external nonReentrant returns (address) {
        address sender = _msgSender();
        if (
            !IVotingEscrow(boostableVe).isApprovedOrOwner(
                sender,
                boostableTokenId
            )
        ) revert NotApprovedOrOwner();

        address gauge = _createBoostGauge(gaugeFactory, boostableTokenId);

        if (tokens.length > 0) {
            _addBribes(sender, gauge, tokens, amounts);
        }

        return gauge;
    }

    function _createBoostGauge(
        address gaugeFactory,
        uint256 boostableTokenId
    ) internal returns (address) {
        IVotingEscrow _boostableVe = IVotingEscrow(boostableVe);

        // Ensure the boostable lock is a MANAGED or NORMAL NFT.
        // We should not create gauges for LOCKED NFTs deposited into
        // a MANAGED NFT as they don't have voting power.
        IVotingEscrow.EscrowType _escrowType = _boostableVe.escrowType(
            boostableTokenId
        );
        if (
            _escrowType != IVotingEscrow.EscrowType.MANAGED &&
            _escrowType != IVotingEscrow.EscrowType.NORMAL
        ) revert UnsupportedEscrowType(_escrowType);

        // Ensure the boostable lock exists and is not expired.
        IVotingEscrow.LockedBalance memory locked = _boostableVe.locked(
            boostableTokenId
        );
        if (locked.amount <= 0) revert LockDoesNotExist();
        if (locked.end <= block.timestamp && !locked.isPermanent)
            revert LockExpired();

        if (boostableTokenIdToGauge[boostableTokenId] != address(0))
            revert GaugeExistsForLock();

        address gauge = _createGauge(
            gaugeFactory,
            _boostableVe.ownerOf(boostableTokenId)
        );

        // Create link between the boostable lock and the gauge.
        boostableTokenIdToGauge[boostableTokenId] = gauge;

        emit BoostGaugeCreated(boostableTokenId, gauge);

        return gauge;
    }

    /// @notice Pokes the boost for a boostable veNFT.
    /// @param boostableTokenId The ID of the boostable veNFT.
    function pokeBoost(uint256 boostableTokenId) external nonReentrant {
        _pokeBoost(boostableTokenId);
    }

    /// @notice Pokes the boosts for a list of boostable veNFTs.
    /// @param boostableTokenIds The IDs of the boostable veNFTs.
    function pokeBoosts(
        uint256[] memory boostableTokenIds
    ) external nonReentrant {
        for (uint256 i = 0; i < boostableTokenIds.length; i++) {
            _pokeBoost(boostableTokenIds[i]);
        }
    }

    /// @notice See pokeBoost.
    function _pokeBoost(uint256 boostableTokenId) internal {
        uint256 boost = _getBoost(boostableTokenId);
        emit BoostPoked(boostableTokenId, boost);
        IVotingEscrow(boostableVe).updateBoost(boostableTokenId, boost);
    }

    /// @notice Gets the current boost factor for a boostable veNFT.
    /// @param boostableTokenId The ID of the boostable veNFT.
    /// @return The current boost factor for the boostable veNFT, in BoostLibrary.PRECISION precision.
    function getBoost(
        uint256 boostableTokenId
    ) external view returns (uint256) {
        return _getBoost(boostableTokenId);
    }

    /// @notice See getBoost.
    function _getBoost(
        uint256 boostableTokenId
    ) internal view returns (uint256) {
        address gauge = boostableTokenIdToGauge[boostableTokenId];

        // `votingVeWeight` is 0 if the gauge does not exist.
        uint256 votingVeWeight = weights[gauge];
        // IMPORTANT NOTE: Weight of the voting veNFT inside the `vote` function is taken using the
        // `votingPowerOfNFT` call so it may include its boost, if the voting veNFT is boostable itself.
        // To account for this fact, here we take the total weight of the voting veNFTs using
        // the `totalVotingPower` call which includes potential boosts as well. This is different
        // comparing to the calls we made for boostable veNFT weights down the road.
        uint256 votingVeTotalWeight = IVotingEscrow(ve).totalVotingPower();
        uint256 votingVeRatio = 0;
        // If the denominator (votingVeTotalWeight) is 0, we are about to divide by 0 and revert.
        // Instead of that, we keep the votingVeRatio at 0 to make boostFraction 0 as well
        // and return the default 1x boost.
        if (votingVeTotalWeight > 0) {
            votingVeRatio =
                (votingVeWeight * BoostLibrary.PRECISION) /
                votingVeTotalWeight;
        }

        // Individual and total weights of the boostable veNFT must be taken without the boost factors
        // since this is the entity receiving the boost we calculate in this function.
        uint256 boostableVeTotalWeight = IVotingEscrow(boostableVe)
            .unboostedTotalVotingPower();
        uint256 boostableVeWeight = IVotingEscrow(boostableVe)
            .unboostedVotingPowerOfNFT(boostableTokenId);
        uint256 boostableVeRatio = 0;
        // If the denominator (boostableVeWeight) is 0, we are about to divide by 0 and revert.
        // Instead of that, we keep the boostableVeRatio at 0 to make boostFraction 0 as well
        // and return the default 1x boost.
        if (boostableVeWeight > 0) {
            boostableVeRatio =
                (boostableVeTotalWeight * BoostLibrary.PRECISION) /
                boostableVeWeight;
        }

        uint256 boostFraction = (4 * boostableVeRatio * votingVeRatio) /
            BoostLibrary.PRECISION;

        return
            Math.min(
                5 * BoostLibrary.PRECISION,
                BoostLibrary.PRECISION + boostFraction
            );
    }

    /// @notice Notifies the booster that a boostable veNFT has been burned.
    ///         Kills the gauge associated with the boostable veNFT as result.
    /// @param boostableTokenId The ID of the boostable veNFT.
    /// @dev Requirements:
    ///      - The caller must be the boostable veNFT
    /// @dev No-op if the boostable veNFT does not have a live gauge.
    function notifyBoostableBurned(uint256 boostableTokenId) external {
        if (_msgSender() != boostableVe) revert NotBoostableVe();

        address gauge = boostableTokenIdToGauge[boostableTokenId];
        // Short circuit if the burned boostable veNFT does not have a live gauge.
        // There is nothing to kill in this case. Proceeding with the kill would revert.
        // Note: This assumes killed gauges cannot be revived. If gauge revival is
        // added in the future, this logic may need to be updated.
        if (!isGauge[gauge] || !isAlive[gauge]) return;

        delete boostableTokenIdToGauge[boostableTokenId];
        _onGaugeKilled(gauge); // This will also delete the gauge from the state.

        emit BoostableTokenBurned(boostableTokenId, gauge);
    }
}
