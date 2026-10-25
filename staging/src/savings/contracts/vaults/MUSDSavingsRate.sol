// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IdleStrategy} from "./IdleStrategy.sol";

/// @title Vault Strategy Interface
/// @notice The MUSDSavingsRate vault separates principal from yield by investing
///         the principal through a strategy. Vault strategies must implement this
///         interface and allow the MUSDSavingsRate vault to allocate and
///         deallocate funds instantly, while tracking and enabling yield claims
///         separately.
interface IVaultStrategy {
    /// @notice Emitted when funds are allocated to the strategy
    event Allocate(uint256 amount);

    /// @notice Emitted when funds are deallocated from the strategy
    event Deallocate(uint256 amount);

    /// @notice Emitted when strategy migrates funds to a new strategy
    event Migrated(address newStrategy, uint256 amount);

    /// @notice Allocate principal funds to the strategy.
    function allocate(uint256 amount) external;

    /// @notice Deallocate principal funds from the strategy and return them
    ///         to the vault. Must deallocate exactly the requested amount. Must not
    ///         deallocate more than was previously allocated. Deallocating yield
    ///         is not possible; only principal can be deallocated.
    function deallocate(uint256 amount) external;

    /// @notice Claim available yield and send it to the vault.
    /// @return amount The amount of yield claimed, or 0 if no yield is available
    function claimYield() external returns (uint256 amount);

    /// @notice Migrate all principal funds to the new strategy.
    ///         This function migrates only the principal. The yield should be
    ///         claimed by the vault separately and is not migrated.
    /// @param newStrategy The address of the strategy to migrate funds to
    /// @return amount The amount of principal funds migrated
    function migrate(address newStrategy) external returns (uint256 amount);

    /// @notice Called when funds are migrated from another strategy.
    ///         Allows the strategy to perform necessary bookkeeping for
    ///         received principal funds.
    /// @param amount The amount of principal funds received
    function onMigrated(uint256 amount) external;
}

/// @notice Protocol Controlled Value contract from MUSD. The contract receives
///         all interest and fees from MUSD and distributes them to MUSDSavingsRate.
interface IPCV {
    /// @notice Distributes MUSD fees accumulated in the contract. The MUSD
    ///         comes from the borrowing fee, interest on debt, and refinance
    ///         fee.
    function distributeMUSD() external;
}

/// @title MUSD Savings Rate Vault
/// @notice The MUSD Savings Rate vault works together with a vault staking gauge.
///         The vault accepts MUSD and mints sMUSD receipt tokens that can then be
///         staked into the gauge to earn rewards (emissions) from the gauge or
///         left unstaked to earn yield from the vault. The vault earns MUSD
///         protocol fees as well as fees from the associated strategy to which the
///         vault's principal is allocated.
/// @dev The default vault strategy is a no-yield strategy, so the only yield
///      comes from the MUSD protocol by default.
contract MUSDSavingsRate is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    IVault
{
    using SafeERC20 for IERC20;

    /// @notice Constructor to set the trusted forwarder for ERC2771.
    /// @param _forwarder The address of the trusted forwarder
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        if (_forwarder == address(0)) revert ZeroAddress();
        _disableInitializers();
    }

    /// @notice The MUSD token contract address
    IERC20 public musdToken;

    /// @notice The current investment strategy used by the vault
    IVaultStrategy public strategy;

    /// @notice Global yield index that tracks accumulated yield per sMUSD token.
    /// @dev Scaled by 1e18 for precision.
    uint256 public yieldIndex;

    /// @notice Each user's last recorded global yield index when they last claimed yield.
    mapping(address => uint256) public supplyYieldIndex;

    /// @notice Claimable yield amount for each user. This is recalculated when
    ///         claiming yield or during sMUSD token transfers.
    mapping(address => uint256) public claimableYield;

    /// @notice Yield amount buffered when the total sMUSD supply is zero.
    /// @dev This ensures yield is not lost when no sMUSD tokens exist.
    uint256 public pendingYield;

    /// @notice Protocol Controlled Value contract from MUSD. The contract
    ///         receives all interest and fees from MUSD and distributes them
    ///         to MUSDSavingsRate.
    IPCV public pcv;

    /// @notice The vault gauge address whose yield claims are subject to
    ///         {gaugeYieldClaimCap}. Any yield owed to this address in excess
    ///         of the cap remains claimable and can be withdrawn in subsequent
    ///         calls.
    /// @dev Set post-upgrade via {setVaultGauge}. When the zero address, no
    ///      cap is applied.
    address public vaultGauge;

    /// @notice Per-claim cap on the yield the configured {vaultGauge} can pull
    ///         from the vault. Excess accrued yield beyond the cap stays
    ///         recorded as claimable for the gauge and is paid out on
    ///         subsequent claims.
    /// @dev Set post-upgrade via {setGaugeYieldClaimCap}. When zero, no cap is
    ///      applied (the cap is effectively disabled).
    uint256 public gaugeYieldClaimCap;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event ProtocolYieldReceived(uint256 amount);
    event StrategyYieldReceived(uint256 amount);
    event YieldClaimed(address indexed user, uint256 amount);
    event StrategyUpdated(
        address indexed oldStrategy,
        address indexed newStrategy,
        uint256 migratedAmount
    );
    event PCVUpdated(address indexed oldPCV, address indexed newPCV);
    event PCVDistributeMUSDFailed(address pcv);
    event VaultGaugeUpdated(
        address indexed oldVaultGauge,
        address indexed newVaultGauge
    );
    event GaugeYieldClaimCapUpdated(uint256 oldCap, uint256 newCap);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error SameStrategy();
    error AmountTooSmall();

    /// @notice Initializes the contract with the MUSD token address.
    /// @dev Creates an IdleStrategy as the default strategy. This strategy produces
    ///      no yield, so initially the vault's only yield source is the MUSD protocol.
    /// @param _musdToken The address of the MUSD token contract
    function initialize(address _musdToken) public initializer {
        if (_musdToken == address(0)) revert ZeroAddress();

        __ERC20_init("MUSD Savings Rate", "sMUSD");
        __Ownable_init();
        __ReentrancyGuard_init();

        musdToken = IERC20(_musdToken);
        yieldIndex = 0;

        // Create default IdleStrategy
        IdleStrategy idleStrategy = new IdleStrategy(_musdToken, address(this));
        strategy = IVaultStrategy(address(idleStrategy));
    }

    /// @notice Deposits MUSD to receive sMUSD receipt tokens at a 1:1 ratio.
    /// @dev The MUSD amount must be approved before calling and cannot be zero.
    ///      Deposited funds are automatically allocated to the vault's strategy.
    /// @param amount The amount of MUSD to deposit
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        if (address(pcv) != address(0)) {
            try pcv.distributeMUSD() {} catch {
                emit PCVDistributeMUSDFailed(address(pcv));
            }
        }
        receiveYieldFromStrategy();

        musdToken.safeTransferFrom(_msgSender(), address(this), amount);
        _mint(_msgSender(), amount);

        // Allocate deposited funds to strategy
        musdToken.forceApprove(address(strategy), amount);
        strategy.allocate(amount);

        emit Deposit(_msgSender(), amount);
    }

    /// @notice Withdraws MUSD by burning sMUSD tokens and claims any outstanding
    ///         yield.
    /// @dev Automatically claims any available yield before withdrawal to ensure
    ///      users don't lose their yield when sMUSD tokens are burned. The amount
    ///      must be greater than zero and the user must have sufficient balance.
    /// @param amount The amount of sMUSD to burn for withdrawal
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(_msgSender()) < amount) revert InsufficientBalance();

        if (address(pcv) != address(0)) {
            try pcv.distributeMUSD() {} catch {
                emit PCVDistributeMUSDFailed(address(pcv));
            }
        }
        receiveYieldFromStrategy();

        _claimYield(_msgSender());

        strategy.deallocate(amount);
        _burn(_msgSender(), amount);
        musdToken.safeTransfer(_msgSender(), amount);

        emit Withdraw(_msgSender(), amount);
    }

    /// @notice Claims available yield for the caller.
    /// @dev Can be called by the user directly or by the vault gauge on their behalf.
    ///      Requires the caller to have a positive sMUSD balance.
    /// @return The amount of yield claimed
    function claimYield() external nonReentrant returns (uint256) {
        return _claimYield(_msgSender());
    }

    /// @dev Internal function to claim yield for a specific depositor.
    ///      When {depositor} is the configured {vaultGauge} and
    ///      {gaugeYieldClaimCap} is non-zero, the amount transferred out on a
    ///      single call is capped at {gaugeYieldClaimCap}. Any excess remains
    ///      credited to the gauge in {claimableYield} and can be pulled on
    ///      subsequent claims.
    /// @param depositor The address to claim yield for
    /// @return The amount of yield claimed
    function _claimYield(address depositor) internal returns (uint256) {
        _updateYieldFor(depositor);

        uint256 claimable = claimableYield[depositor];

        uint256 _cap = gaugeYieldClaimCap;
        if (depositor == vaultGauge && _cap > 0 && claimable > _cap) {
            claimable = _cap;
        }

        if (claimable > 0) {
            claimableYield[depositor] -= claimable;
            musdToken.safeTransfer(depositor, claimable);
            emit YieldClaimed(depositor, claimable);
        }

        return claimable;
    }

    /// @notice Receives yield from the MUSD protocol and distributes it to sMUSD holders.
    /// @dev Anyone can call this function. It operates under the assumption that
    ///      any yield received is from the MUSD protocol.
    /// @param amount The amount of MUSD yield to distribute
    function receiveProtocolYield(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        musdToken.safeTransferFrom(_msgSender(), address(this), amount);

        _receiveYield(amount);
        emit ProtocolYieldReceived(amount);
    }

    /// @notice Claims yield from the associated strategy and distributes it to sMUSD holders.
    /// @dev Anyone can call this function. Does nothing if no yield is available
    ///      from the strategy.
    function receiveYieldFromStrategy() public {
        uint256 amount = strategy.claimYield();

        if (amount > 0) {
            _receiveYield(amount);
            emit StrategyYieldReceived(amount);
        }
    }

    /// @dev Internal function that receives yield and updates the global yield index.
    ///      If no sMUSD tokens exist, yield is buffered until the first deposit.
    ///      Similar to the Pool's _update0 function.
    /// @param amount The amount of yield to distribute
    /// @return _totalSupply The current total supply of sMUSD tokens
    function _receiveYield(
        uint256 amount
    ) internal returns (uint256 _totalSupply) {
        _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            // Include any pending yield from when totalSupply was zero
            uint256 totalYieldToDistribute = amount + pendingYield;
            pendingYield = 0;

            // Calculate yield per token and add it to the global index.
            // The global index holds total accumulated yield per sMUSD token.
            uint256 _ratio = (totalYieldToDistribute * 1e18) / _totalSupply;
            if (_ratio > 0) {
                yieldIndex += _ratio;
            } else {
                // At this point tokens are transferred to this contract. If
                // the amount received (and transferred) is so small that the
                // _ratio gets rounded down to zero, we want to revert the
                // transaction instead of "losing" those tokens.
                revert AmountTooSmall();
            }
        } else {
            // Buffer yield until there are sMUSD holders
            pendingYield += amount;
        }
    }

    /// @dev Internal function that updates claimable yield for a specific user.
    ///      Calculates yield based on the difference between current and user's last
    ///      recorded yield index. Similar to the Pool's _updateFor function.
    /// @param recipient The address to update yield calculations for
    function _updateYieldFor(address recipient) internal {
        uint256 _supplied = balanceOf(recipient);
        if (_supplied > 0) {
            uint256 _supplyYieldIndex = supplyYieldIndex[recipient];
            uint256 _yieldIndex = yieldIndex;
            supplyYieldIndex[recipient] = _yieldIndex;
            uint256 _delta = _yieldIndex - _supplyYieldIndex;
            if (_delta > 0) {
                uint256 _share = (_supplied * _delta) / 1e18;
                claimableYield[recipient] += _share;
            }
        } else {
            supplyYieldIndex[recipient] = yieldIndex;
        }
    }

    /// @notice Returns the address of the yield token (MUSD).
    /// @dev Required by the IVault interface.
    /// @return The address of the MUSD token contract
    function yieldToken() external view override returns (address) {
        return address(musdToken);
    }

    /// @notice Changes the vault's investment strategy. Claims any pending yield
    ///         from the current strategy and migrates all principal funds to
    ///         the new strategy.
    /// @dev Can only be called by the contract owner. The new strategy cannot be
    ///      the zero address or the same as the current strategy.
    /// @param _newStrategy The address of the new strategy contract
    function setStrategy(address _newStrategy) external onlyOwner {
        if (_newStrategy == address(0)) revert ZeroAddress();
        if (_newStrategy == address(strategy)) revert SameStrategy();

        receiveYieldFromStrategy();

        IVaultStrategy oldStrategy = strategy;
        strategy = IVaultStrategy(_newStrategy);

        uint256 migratedAmount = oldStrategy.migrate(_newStrategy);
        strategy.onMigrated(migratedAmount);

        emit StrategyUpdated(
            address(oldStrategy),
            _newStrategy,
            migratedAmount
        );
    }

    /// @dev Allows the contract owner to update the address of MUSD Protocol
    ///      Controlled Value contract.
    function setPCV(address _pcv) external onlyOwner {
        if (_pcv == address(0)) revert ZeroAddress();
        emit PCVUpdated(address(pcv), _pcv);
        pcv = IPCV(_pcv);
    }

    /// @notice Sets the vault gauge whose yield claims are subject to the
    ///         {gaugeYieldClaimCap} per-claim cap.
    /// @dev Only callable by the contract owner.
    /// @param _vaultGauge The address of the vault gauge
    function setVaultGauge(address _vaultGauge) external onlyOwner {
        if (_vaultGauge == address(0)) revert ZeroAddress();
        emit VaultGaugeUpdated(vaultGauge, _vaultGauge);
        vaultGauge = _vaultGauge;
    }

    /// @notice Sets the per-claim cap on the yield the configured
    ///         {vaultGauge} can pull from the vault.
    /// @dev Only callable by the contract owner. A value of zero disables the
    ///      cap (the gauge claims behave like any other depositor).
    /// @param _cap The per-claim cap, denominated in MUSD (18 decimals)
    function setGaugeYieldClaimCap(uint256 _cap) external onlyOwner {
        emit GaugeYieldClaimCapUpdated(gaugeYieldClaimCap, _cap);
        gaugeYieldClaimCap = _cap;
    }

    /// @dev Updates yield tracking before every token transfer to ensure accurate
    ///      yield calculations.  Required so that one can't claim yield after
    ///      unstaking from the gauge.
    /// @param from The address sending tokens (or address(0) for minting)
    /// @param to The address receiving tokens (or address(0) for burning)
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (from == to) return;
        _updateYieldFor(from);
        _updateYieldFor(to);
    }

    /// @dev Override _msgSender to support ERC2771 meta-transactions.
    ///      Needed given ERC20Upgradeable inherits from ContextUpgradeable
    ///      which defines _msgSender().
    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// @dev Override _msgData to support ERC2771 meta-transactions.
    ///      Needed given ERC20Upgradeable inherits from ContextUpgradeable
    ///      which defines _msgData().
    function _msgData()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    /// @dev Override _contextSuffixLength to support ERC2771 meta-transactions.
    ///      Needed given ERC20Upgradeable inherits from ContextUpgradeable
    ///      which defines _contextSuffixLength().
    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
