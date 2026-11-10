// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ITroveManager, IHintHelpers, ISortedTroves, IPoolFactory, IRouter
} from "./interfaces/IMezo.sol";

// Checks and lookups of the vault, a linked library so they sit outside its size limit
library SystemMath {
    using Math for uint256;

    error SwapApprove();

    // Mezo rejects exits that drag the system ratio under CCR, a full close is the worst case
    function systemAllowsExit(ITroveManager tm, uint256 tcoll, uint256 tdebt, uint256 price)
        public
        view
        returns (bool)
    {
        uint256 debt = tm.getEntireSystemDebt();
        if (debt <= tdebt) return false;
        uint256 coll = tm.getEntireSystemColl() - tcoll;
        return coll.mulDiv(price, debt - tdebt) >= tm.CCR();
    }

    // Collateral the trove must keep at target so the rest of the system stays at CCR
    function systemKeep(
        ITroveManager tm,
        uint256 tcoll,
        uint256 tdebt,
        uint256 price,
        uint256 targetCR
    ) public view returns (uint256) {
        uint256 ccr = tm.CCR();
        uint256 debt = tm.getEntireSystemDebt().saturatingSub(tdebt);
        uint256 coll = tm.getEntireSystemColl().saturatingSub(tcoll);
        uint256 gap = debt.mulDiv(ccr, 1e18).saturatingSub(coll.mulDiv(price, 1e18));
        return gap.mulDiv(targetCR, (targetCR - ccr).mulDiv(price, 1e18), Math.Rounding.Ceil);
    }

    // Picks the list position closest to where the vault's trove lands, run by delegatecall
    function hint(
        IHintHelpers hintHelpers,
        ISortedTroves sortedTroves,
        bool active,
        uint256 tcoll,
        uint256 tdebt,
        uint256 coll,
        uint256 debt,
        uint256 trials
    ) public view returns (address, address) {
        uint256 nicr = coll.mulDiv(1e20, debt);
        uint256 moved = type(uint256).max;
        if (active) {
            uint256 current = tcoll.mulDiv(1e20, tdebt);
            moved = current > nicr ? current - nicr : nicr - current;
            // Our neighbours stay adjacent once the trove is lifted out, unbeatable for a small move
            if (moved <= nicr / 100) {
                return (sortedTroves.getPrev(address(this)), sortedTroves.getNext(address(this)));
            }
        }
        // Seeded by the ratio, so a gas estimate samples the same troves the transaction will
        (address found, uint256 diff,) = hintHelpers.getApproxHint(nicr, trials, nicr);
        if (moved <= diff || found == address(this)) {
            return (sortedTroves.getPrev(address(this)), sortedTroves.getNext(address(this)));
        }
        return (found, found);
    }

    // Runs as the vault, approving exactly what the router pulls so no allowance outlives the swap
    function swap(
        IRouter router,
        address factory,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) public returns (uint256) {
        if (!IERC20(tokenIn).approve(address(router), amountIn)) revert SwapApprove();
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(tokenIn, tokenOut, false, factory);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, minOut, routes, address(this), block.timestamp);
        return amounts[amounts.length - 1];
    }

    // A paused factory still quotes, but its pools refuse every swap
    function canBuy(
        IPoolFactory factory,
        IRouter router,
        address btc,
        address musd,
        uint256 btcIn,
        uint256 musdAmount
    ) public view returns (bool) {
        try factory.isPaused() returns (bool paused) {
            if (paused) return false;
        } catch {
            return false;
        }
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(btc, musd, false, address(factory));
        try router.getAmountsOut(btcIn, routes) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1] >= musdAmount;
        } catch {
            return false;
        }
    }
}
