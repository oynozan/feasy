// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.33;

import {VotingEscrow} from "./VotingEscrow.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract VeMEZO is VotingEscrow {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _mezo,
        address _factoryRegistry
    ) external initializer {
        uint256 _maxLockTime = 208 * 7 * 86400; // 208 weeks (~4 years, normalized)
        __VotingEscrow_initialize(_mezo, _factoryRegistry, _maxLockTime);
    }

    /// @dev Anyone can call it on a fresh deployment, which `initialize`
    ///      leaves at version 1. The call only writes zero, but it moves the
    ///      proxy to version 2, so the next upgrade must use `reinitializer(3)`.
    function initializeV2() external reinitializer(2) {
        __VotingEscrow_initializeV2();
    }

    function name() external pure returns (string memory) {
        return "veMEZO";
    }

    function symbol() external pure returns (string memory) {
        return "veMEZO";
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function toggleSplit(address, bool) external override {
        // VeMEZO does not support veNFT splits.
        revert IVotingEscrow.SplitsDisabled();
    }

    function split(
        uint256,
        uint256
    ) external override nonReentrant returns (uint256, uint256) {
        // VeMEZO does not support veNFT splits.
        revert IVotingEscrow.SplitsDisabled();
    }
}
