// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultStrategy} from "./MUSDSavingsRate.sol";

/// @title Idle Vault Strategy
/// @notice A simple vault strategy that holds tokens without generating yield.
///         This strategy serves as a default option when no active yield
///         strategy is desired or available.
contract IdleStrategy is IVaultStrategy {
    using SafeERC20 for IERC20;

    /// @notice The token this strategy manages
    IERC20 public immutable token;

    /// @notice The vault that controls this strategy
    address public immutable vault;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    /// @param _token The token this strategy will manage
    /// @param _vault The vault that will control this strategy
    constructor(address _token, address _vault) {
        token = IERC20(_token);
        vault = _vault;
    }

    /// @inheritdoc IVaultStrategy
    function allocate(uint256 amount) external override onlyVault {
        emit Allocate(amount);
        token.safeTransferFrom(vault, address(this), amount);
    }

    /// @inheritdoc IVaultStrategy
    function deallocate(uint256 amount) external override onlyVault {
        emit Deallocate(amount);
        // The strategy generates no yield so the entire balance is the
        // principal. We do not need to worry about yield vs principal
        // bookkeeping for withdrawals.
        token.safeTransfer(vault, amount);
    }

    /// @inheritdoc IVaultStrategy
    function claimYield() external pure override returns (uint256 amount) {
        return 0;
    }

    /// @inheritdoc IVaultStrategy
    function migrate(
        address newStrategy
    ) external override onlyVault returns (uint256 amount) {
        // The strategy generates no yield so the entire balance is the
        // principal. We do not need to worry about yield vs principal
        // bookkeeping for the migration.
        uint256 balance = token.balanceOf(address(this));
        emit Migrated(newStrategy, balance);

        if (balance > 0) {
            token.safeTransfer(newStrategy, balance);
        }

        return balance;
    }

    /// @inheritdoc IVaultStrategy
    function onMigrated(uint256 amount) external override onlyVault {
        // For idle strategy, no special bookkeeping needed since we don't
        // generate yield. The tokens have already been transferred to us.
        // This function exists to satisfy the interface and could be used
        // by more complex strategies for principal tracking.
    }
}
