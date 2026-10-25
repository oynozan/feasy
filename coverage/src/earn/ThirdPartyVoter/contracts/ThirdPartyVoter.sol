// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import {NonStakingVoter} from "./NonStakingVoter.sol";

/// @title ThirdPartyVoter
/// @notice Contract allowing veNFT holders to vote on third-party gauges.
///         Gauge creation and killing are restricted to the governor.
/// @dev Third-party gauges store metadata alongside the gauge address.
///      Killed gauges cannot be revived.
contract ThirdPartyVoter is NonStakingVoter {
    /// @notice Struct to store gauge address and associated metadata
    struct GaugeWithMetadata {
        address gauge;
        string metadata;
    }

    /// @notice Mapping from third-party address to gauge with metadata
    mapping(address => GaugeWithMetadata) public thirdPartyToGauge;

    event ThirdPartyGaugeCreated(
        address indexed thirdParty,
        address indexed gauge,
        string metadata
    );
    event ThirdPartyGaugeKilled(
        address indexed thirdParty,
        address indexed gauge
    );

    error GaugeExistsForThirdParty();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _forwarder) NonStakingVoter(_forwarder) {
        _disableInitializers();
    }

    /// @notice Initializes the ThirdPartyVoter contract
    /// @param _ve Address of the VotingEscrow
    /// @param _factoryRegistry Address of the FactoryRegistry
    /// @param _rewardToken Address of the reward token
    function initialize(
        address _ve,
        address _factoryRegistry,
        address _rewardToken
    ) external initializer {
        __NonStakingVoter_init(_ve, _factoryRegistry, _rewardToken);
    }

    /// @notice Creates a new NonStakingGauge for a third party that veNFT holders can vote for.
    ///         The gauge beneficiary (rewards recipient) is set to the third party address.
    /// @param gaugeFactory The address of the gauge factory to use
    /// @param thirdParty The address of the third party
    /// @param metadata Metadata string describing the third party or gauge purpose
    /// @return The address of the newly created gauge
    /// @dev Requirements:
    ///      - The caller must be the governor
    ///      - No gauge must already exist for this third party
    ///      - The gauge factory must be approved in the factory registry
    /// @dev The third-party can switch to another beneficiary after the gauge is created
    ///      by calling `switchRewardsBeneficiary` on the gauge.
    function createThirdPartyGauge(
        address gaugeFactory,
        address thirdParty,
        string calldata metadata
    ) external nonReentrant returns (address) {
        if (_msgSender() != governor) revert NotGovernor();

        if (thirdPartyToGauge[thirdParty].gauge != address(0))
            revert GaugeExistsForThirdParty();

        address gauge = _createGauge(gaugeFactory, thirdParty);

        thirdPartyToGauge[thirdParty] = GaugeWithMetadata(gauge, metadata);

        emit ThirdPartyGaugeCreated(thirdParty, gauge, metadata);

        return gauge;
    }

    /// @notice Kills the gauge associated with a third party.
    ///         The gauge will no longer receive emissions and cannot be voted for.
    /// @param thirdParty The address of the third party
    /// @dev Requirements:
    ///      - The caller must be the governor
    ///      - A gauge must exist for this third party
    ///      - The gauge must not already be killed
    /// @dev Killed gauges cannot be revived. Any claimable rewards are returned to the splitter.
    function killThirdPartyGauge(address thirdParty) external nonReentrant {
        if (_msgSender() != governor) revert NotGovernor();

        address gauge = thirdPartyToGauge[thirdParty].gauge;

        // The _onGaugeKilled call will revert if the gauge does not exist or is already killed.
        // No need to check for gauge existence or liveness explicitly.
        delete thirdPartyToGauge[thirdParty];
        _onGaugeKilled(gauge);

        emit ThirdPartyGaugeKilled(thirdParty, gauge);
    }
}
