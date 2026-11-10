// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * Holds the vault's veMEZO and spends its votes boosting the vault's own veBTC
 * locks on Mezo Earn's BoostVoter.
 *
 * MEZO arrives from the savings sleeve's share of gauge rewards and goes into
 * one permanent veMEZO lock, so its weight never decays. Once a week boost()
 * votes that lock evenly for the boost gauges of the sleeve's live rungs,
 * applies each rung's new boost on veBTC and refreshes the rung's Voter vote,
 * so the rungs carry up to five times the weight and take a larger share of the
 * sMUSD gauge's fees.
 *
 * The vault mints its performance fee here. Those shares are protocol revenue
 * the vault owner can move out with sweep, the veMEZO lock never leaves.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVeBTC, IVoter, IBoostVoter, IVeMezo} from "./interfaces/IMezo.sol";

interface IBoostedVault {
    function owner() external view returns (address);
    function keeper() external view returns (address);
    function sleeve() external view returns (IBoostedSleeve);
}

interface IBoostedSleeve {
    function ve() external view returns (IVeBTC);
    function voter() external view returns (IVoter);
    function rungs(uint256 i) external view returns (uint256 id, uint128 amount, uint64 end);
}

contract Booster {
    using SafeERC20 for IERC20;

    uint256 private constant SLOTS = 4;
    // veMEZO's longest lock, made permanent right after it opens
    uint256 private constant MAX_LOCK = 208 weeks;

    IBoostedVault public immutable vault;
    IBoostedSleeve public immutable sleeve;
    IBoostVoter public immutable boostVoter;
    IVeMezo public immutable veMezo;
    IERC20 public immutable mezo;
    IVoter public immutable voter;

    uint256 public veMezoId;

    event Locked(uint256 veMezoId, uint256 amount);
    event Boosted(uint256 indexed rung, address gauge, uint256 boost);
    event Swept(address token, address to, uint256 amount);

    error NotAllowed();

    constructor(IBoostedVault vault_) {
        vault = vault_;
        sleeve = vault_.sleeve();
        voter = sleeve.voter();
        boostVoter = IBoostVoter(sleeve.ve().booster());
        veMezo = IVeMezo(boostVoter.ve());
        mezo = IERC20(veMezo.token());
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != vault.keeper() && msg.sender != vault.owner()) revert NotAllowed();
        _;
    }

    // Puts every MEZO here into the one veMEZO lock
    function lock() external onlyKeeperOrOwner {
        uint256 amount = mezo.balanceOf(address(this));
        if (amount == 0) return;
        mezo.forceApprove(address(veMezo), amount);
        uint256 id = veMezoId;
        if (id == 0) {
            id = veMezo.createLock(amount, MAX_LOCK);
            veMezo.lockPermanent(id);
            veMezoId = id;
        } else {
            veMezo.increaseAmount(id, amount);
        }
        emit Locked(id, amount);
    }

    // Once an epoch, Mezo allows one vote a lock between an hour after the flip and an hour before
    function boost() external onlyKeeperOrOwner {
        address[] memory gauges = new address[](SLOTS);
        uint256[] memory ids = new uint256[](SLOTS);
        uint256 n;
        for (uint256 i; i < SLOTS; i++) {
            (uint256 id,, uint64 end) = sleeve.rungs(i);
            // veBTC refuses to boost an ended lock, which waits in its slot until a roll releases it
            if (id == 0 || end <= block.timestamp) continue;
            address gauge = boostVoter.boostableTokenIdToGauge(id);
            if (gauge == address(0)) continue;
            gauges[n] = gauge;
            ids[n++] = id;
        }
        if (n == 0 || veMezoId == 0) return;
        assembly ("memory-safe") {
            mstore(gauges, n)
            mstore(ids, n)
        }
        uint256[] memory weights = new uint256[](n);
        for (uint256 k; k < n; k++) {
            weights[k] = 1;
        }
        boostVoter.vote(veMezoId, gauges, weights);
        for (uint256 k; k < n; k++) {
            boostVoter.pokeBoost(ids[k]);
            voter.poke(ids[k]);
            emit Boosted(ids[k], gauges[k], boostVoter.getBoost(ids[k]));
        }
    }

    // Protocol revenue, fee shares or anything sent by mistake, MEZO only goes into the lock
    function sweep(IERC20 token, address to, uint256 amount) external {
        if (msg.sender != vault.owner() || token == mezo) revert NotAllowed();
        token.safeTransfer(to, amount);
        emit Swept(address(token), to, amount);
    }
}
