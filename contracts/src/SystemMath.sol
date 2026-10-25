// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITroveManager} from "./interfaces/IMezo.sol";

// System ratio checks of the vault, a linked library so they sit outside its size limit
library SystemMath {
    using Math for uint256;

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
}
