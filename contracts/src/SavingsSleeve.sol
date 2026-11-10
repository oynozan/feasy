// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * Holds the vault's sMUSD, stakes a share of it in Mezo's sMUSD gauge and
 * measures what sMUSD actually pays.
 *
 * Staked sMUSD earns the gauge's MEZO emissions, and its MUSD yield goes as
 * fees to the veBTC locks that vote for the gauge, the vault's own sleeve
 * among them. MEZO never stays here, harvestMezo sells it for BTC that goes
 * straight to the vault.
 *
 * The savings rate comes from sMUSD's yieldIndex, the MUSD paid per sMUSD.
 * A snapshot a week keeps up to four weeks of history, and the rate is the
 * index growth since the oldest one. The vault opens or raises its loan only
 * while that rate beats the loan rate by minSpreadBps.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IBorrowerOperations,
    ITroveManager,
    IInterestRateManager,
    ISavings,
    IStakingGauge,
    IPoolFactory,
    IRouter,
    IVoter
} from "./interfaces/IMezo.sol";

interface IVaultRoles {
    function owner() external view returns (address);
    function guardian() external view returns (address);
    function keeper() external view returns (address);
}

contract SavingsSleeve {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Snapshot {
        uint192 index;
        uint64 time;
    }

    uint256 private constant BPS = 10_000;
    uint256 private constant WEEK = 7 days;
    uint256 private constant YEAR = 365 days;
    uint256 private constant SLOTS = 4;
    // A rate from less history than this is noise, so borrowing waits for it
    uint256 private constant MIN_WINDOW = 1 days;
    // Staking runs inside rebalance, so a failing gauge costs at most this and leaves sMUSD unstaked
    uint256 private constant STAKE_GAS = 300_000;

    address public immutable vault;
    IERC20 public immutable musd;
    IERC20 public immutable btc;
    ISavings public immutable savings;
    IStakingGauge public immutable gauge;
    IERC20 public immutable mezo;
    IRouter public immutable router;
    address public immutable poolFactory;
    ITroveManager public immutable troveManager;
    IInterestRateManager public immutable interestRateManager;
    IBorrowerOperations public immutable borrowerOperations;

    Snapshot[4] public snapshots;
    uint8 public latest;
    uint16 public stakeBps;
    uint16 public minSpreadBps;
    // Share of harvested MEZO sent to the booster's veMEZO, the rest is sold for BTC
    uint16 public boostBps;
    address public booster;

    event Staked(uint256 staked);
    event StakeSet(uint16 bps);
    event MinSpreadSet(uint16 bps);
    event Snapshotted(uint256 index, uint256 time);
    event MezoHarvested(uint256 mezoIn, uint256 btcOut);
    event MezoBoosted(uint256 mezo);
    event BoosterSet(address booster, uint16 boostBps);

    error NotVault();
    error NotAllowed();
    error BadSleeve();

    constructor(
        address vault_,
        ISavings savings_,
        IERC20 btc_,
        IBorrowerOperations borrowerOperations_,
        IVoter voter_,
        IRouter router_,
        address poolFactory_
    ) {
        vault = vault_;
        savings = savings_;
        btc = btc_;
        borrowerOperations = borrowerOperations_;
        musd = IERC20(borrowerOperations_.musd());
        troveManager = ITroveManager(borrowerOperations_.troveManager());
        interestRateManager = IInterestRateManager(borrowerOperations_.interestRateManager());
        router = router_;
        poolFactory = poolFactory_;
        // Without a voter or a gauge for sMUSD the sleeve only saves and measures
        IStakingGauge gauge_;
        if (address(voter_) != address(0)) {
            gauge_ = IStakingGauge(voter_.gauges(address(savings_)));
            if (address(gauge_) != address(0) && gauge_.stakingToken() != address(savings_)) {
                revert BadSleeve();
            }
        }
        gauge = gauge_;
        mezo = IERC20(address(gauge_) == address(0) ? address(0) : gauge_.rewardToken());
        snapshots[0] = Snapshot(uint192(savings_.yieldIndex()), uint64(block.timestamp));
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    /* Vault side */

    // Saves every MUSD sent here, then moves the staked share toward stakeBps
    function park() external onlyVault {
        uint256 held = musd.balanceOf(address(this));
        if (held > 0) {
            musd.forceApprove(address(savings), held);
            savings.deposit(held);
        }
        snapshot();
        _restake();
    }

    // Sends the vault up to amount MUSD, from loose MUSD, then yield, then principal
    function pull(uint256 amount) external onlyVault returns (uint256 sent) {
        uint256 held = musd.balanceOf(address(this));
        if (held < amount) {
            uint256 free = savings.balanceOf(address(this));
            uint256 accrued = _accrued(free);
            uint256 need = (amount - held).saturatingSub(accrued);
            if (need > free && address(gauge) != address(0)) {
                uint256 out = Math.min(need - free, gauge.balanceOf(address(this)));
                if (out > 0) gauge.withdraw(out);
                free += out;
            }
            // sMUSD pays all accrued yield on withdraw as well
            uint256 principal = Math.min(need, free);
            if (principal > 0) savings.withdraw(principal);
            else if (accrued > 0) savings.claimYield();
        }
        sent = Math.min(amount, musd.balanceOf(address(this)));
        if (sent > 0) musd.safeTransfer(vault, sent);
    }

    // Everything here in MUSD, staked principal included, its yield belongs to the gauge's voters
    function value() external view returns (uint256) {
        uint256 free = savings.balanceOf(address(this));
        return free + staked() + _accrued(free) + musd.balanceOf(address(this));
    }

    /* Spread */

    // Anyone may call, it adds a snapshot once the newest is a week old
    function snapshot() public {
        if (block.timestamp < snapshots[latest].time + WEEK) return;
        uint8 next = uint8((latest + 1) % SLOTS);
        uint256 index = savings.yieldIndex();
        snapshots[next] = Snapshot(uint192(index), uint64(block.timestamp));
        latest = next;
        emit Snapshotted(index, block.timestamp);
    }

    // Realized sMUSD rate in basis points a year, zero until a day of history exists
    function savingsRate() public view returns (uint256) {
        Snapshot memory oldest = snapshots[(latest + 1) % SLOTS];
        if (oldest.time == 0) oldest = snapshots[0];
        uint256 elapsed = block.timestamp - oldest.time;
        if (elapsed < MIN_WINDOW) return 0;
        return (savings.yieldIndex() - oldest.index).mulDiv(YEAR * BPS, elapsed * 1e18);
    }

    // New debt's cost in bps a year, the higher of two rates plus the borrow fee over a year
    function loanRate() public view returns (uint256) {
        uint256 rate = Math.max(
            troveManager.getTroveInterestRate(vault), interestRateManager.interestRate()
        );
        return rate + borrowerOperations.borrowingRate() / 1e14;
    }

    function spreadOk() external view returns (bool) {
        return savingsRate() >= loanRate() + minSpreadBps;
    }

    /* MEZO */

    function staked() public view returns (uint256) {
        return address(gauge) == address(0) ? 0 : gauge.balanceOf(address(this));
    }

    function mezoEarned() external view returns (uint256) {
        return address(gauge) == address(0) ? 0 : gauge.earned(address(this));
    }

    // MEZO has no oracle here, so the keeper names the sale's floor from Mezo Pools' quotes
    function harvestMezo(uint256 minBtcOut) external returns (uint256 btcOut) {
        IVaultRoles roles = IVaultRoles(vault);
        if (msg.sender != roles.keeper() && msg.sender != roles.owner()) revert NotAllowed();
        if (address(gauge) == address(0)) return 0;
        gauge.getReward(address(this));
        uint256 amount = mezo.balanceOf(address(this));
        uint256 boosted = amount.mulDiv(boostBps, BPS);
        if (boosted > 0) {
            mezo.safeTransfer(booster, boosted);
            emit MezoBoosted(boosted);
        }
        amount -= boosted;
        if (amount == 0) return 0;
        if (!mezo.approve(address(router), amount)) revert BadSleeve();
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amount, minBtcOut, _route(), vault, block.timestamp);
        btcOut = amounts[amounts.length - 1];
        emit MezoHarvested(amount, btcOut);
    }

    // Straight to BTC when Mezo Pools has the pair, otherwise through MUSD
    function _route() internal view returns (IRouter.Route[] memory routes) {
        if (IPoolFactory(poolFactory).getPool(address(mezo), address(btc), false) != address(0)) {
            routes = new IRouter.Route[](1);
            routes[0] = IRouter.Route(address(mezo), address(btc), false, poolFactory);
        } else {
            routes = new IRouter.Route[](2);
            routes[0] = IRouter.Route(address(mezo), address(musd), false, poolFactory);
            routes[1] = IRouter.Route(address(musd), address(btc), false, poolFactory);
        }
    }

    /* Settings */

    // Through the vault owner's 24 hour timelock
    function setStake(uint16 bps) external {
        if (msg.sender != IVaultRoles(vault).owner() || bps > BPS) revert NotAllowed();
        stakeBps = bps;
        emit StakeSet(bps);
        _restake();
    }

    // Higher only ever means less borrowing, so the guardian may raise it and the owner may set it
    function setMinSpread(uint16 bps) external {
        IVaultRoles roles = IVaultRoles(vault);
        if (msg.sender != roles.owner() && (msg.sender != roles.guardian() || bps < minSpreadBps)) {
            revert NotAllowed();
        }
        minSpreadBps = bps;
        emit MinSpreadSet(bps);
    }

    // Through the vault owner's timelock, a booster is needed before any MEZO can go to it
    function setBooster(address booster_, uint16 boostBps_) external {
        if (
            msg.sender != IVaultRoles(vault).owner() || boostBps_ > BPS
                || (boostBps_ > 0 && booster_ == address(0))
        ) revert NotAllowed();
        booster = booster_;
        boostBps = boostBps_;
        emit BoosterSet(booster_, boostBps_);
    }

    // The guardian may take every sMUSD out of the gauge, only the owner stakes again
    function unstake() external {
        IVaultRoles roles = IVaultRoles(vault);
        if (msg.sender != roles.owner() && msg.sender != roles.guardian()) revert NotAllowed();
        stakeBps = 0;
        emit StakeSet(0);
        uint256 amount = staked();
        if (amount > 0) gauge.withdraw(amount);
        emit Staked(0);
    }

    function _restake() internal {
        if (address(gauge) == address(0)) return;
        uint256 current = staked();
        uint256 target = (savings.balanceOf(address(this)) + current).mulDiv(stakeBps, BPS);
        if (target > current) {
            IERC20 receipt = IERC20(address(savings));
            receipt.forceApprove(address(gauge), target - current);
            // A killed gauge refuses deposits, the sMUSD then just keeps its own yield
            try gauge.deposit{gas: STAKE_GAS}(target - current) {
                emit Staked(target);
            } catch {
                receipt.forceApprove(address(gauge), 0);
            }
        } else if (current > target) {
            gauge.withdraw(current - target);
            emit Staked(target);
        }
    }

    function _accrued(uint256 free) internal view returns (uint256) {
        uint256 index = savings.yieldIndex() - savings.supplyYieldIndex(address(this));
        return savings.claimableYield(address(this)) + free * index / 1e18;
    }
}
