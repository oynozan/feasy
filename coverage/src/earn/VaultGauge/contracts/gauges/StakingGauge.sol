// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IStakingGauge} from "../interfaces/IStakingGauge.sol";
import {Gauge} from "./Gauge.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Staking Gauge
/// @author veldorome.finance, @figs999, @pegahcarter
/// @notice Gauge contract for distribution of emissions by staking address.
abstract contract StakingGauge is IStakingGauge, Gauge {
    using SafeERC20 for IERC20;
    /// @inheritdoc IStakingGauge
    address public immutable stakingToken;
    /// @inheritdoc IStakingGauge
    address public immutable feesVotingReward;

    constructor(
        address _forwarder,
        address _stakingToken,
        address _feesVotingReward,
        address _rewardToken,
        address _voter
    ) Gauge(_forwarder, _rewardToken, _voter) {
        stakingToken = _stakingToken;
        feesVotingReward = _feesVotingReward;
    }

    function _claimFees() internal virtual;

    /// @inheritdoc IStakingGauge
    function deposit(uint256 _amount) external {
        _depositFor(_amount, _msgSender());
    }

    /// @inheritdoc IStakingGauge
    function deposit(uint256 _amount, address _recipient) external {
        _depositFor(_amount, _recipient);
    }

    function _depositFor(
        uint256 _amount,
        address _recipient
    ) internal nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (!IVoter(voter).isAlive(address(this))) revert NotAlive();

        address sender = _msgSender();
        _updateRewards(_recipient);

        IERC20(stakingToken).safeTransferFrom(sender, address(this), _amount);
        totalSupply += _amount;
        balanceOf[_recipient] += _amount;

        emit Deposit(sender, _recipient, _amount);
    }

    /// @inheritdoc IStakingGauge
    function withdraw(uint256 _amount) external nonReentrant {
        address sender = _msgSender();

        _updateRewards(sender);

        totalSupply -= _amount;
        balanceOf[sender] -= _amount;
        IERC20(stakingToken).safeTransfer(sender, _amount);

        emit Withdraw(sender, _amount);
    }

    function _onNotifyRewardAmount() internal override {
        _claimFees();
    }

    /// @inheritdoc IStakingGauge
    function notifyRewardWithoutClaim(uint256 _amount) external nonReentrant {
        address sender = _msgSender();
        if (sender != IVotingEscrow(ve).team()) revert NotTeam();
        if (_amount == 0) revert ZeroAmount();
        _notifyRewardAmount(sender, _amount);
    }
}
