// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.33;

import {VotingEscrow} from "./VotingEscrow.sol";

contract VeBTC is VotingEscrow {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _btc,
        address _factoryRegistry,
        uint256 _maxLockTime
    ) external initializer {
        __VotingEscrow_initialize(_btc, _factoryRegistry, _maxLockTime);
    }

    /// @dev Anyone can call it on a fresh deployment, which `initialize`
    ///      leaves at version 1. The call only writes zero, but it moves the
    ///      proxy to version 2, so the next upgrade must use `reinitializer(3)`.
    function initializeV2() external reinitializer(2) {
        __VotingEscrow_initializeV2();
    }

    function name() external pure returns (string memory) {
        return "veBTC";
    }

    function symbol() external pure returns (string memory) {
        return "veBTC";
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
