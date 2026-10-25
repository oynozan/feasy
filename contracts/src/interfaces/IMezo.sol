// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Minimal views of the Mezo contracts the vault touches, checked against mezo-org/musd

interface IBorrowerOperations {
    function openTrove(uint256 debtAmount, address upperHint, address lowerHint) external payable;
    function addColl(address upperHint, address lowerHint) external payable;
    function withdrawColl(uint256 amount, address upperHint, address lowerHint) external;
    function adjustTrove(
        uint256 collWithdrawal,
        uint256 debtChange,
        bool isDebtIncrease,
        address upperHint,
        address lowerHint
    ) external payable;
    function closeTrove() external;
    function refinance(address upperHint, address lowerHint) external;
    function claimCollateral() external;
    function minNetDebt() external view returns (uint256);
    function borrowingRate() external view returns (uint256);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
    function troveManager() external view returns (address);
    function priceFeed() external view returns (address);
    function sortedTroves() external view returns (address);
    function collSurplusPool() external view returns (address);
    function activePool() external view returns (address);
    function interestRateManager() external view returns (address);
    function musd() external view returns (address);
}

interface ITroveManager {
    function getTroveStatus(address borrower) external view returns (uint8);
    function getEntireDebtAndColl(address borrower)
        external
        view
        returns (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingColl,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        );
    function getTroveMaxBorrowingCapacity(address borrower) external view returns (uint256);
    function getTroveInterestRate(address borrower) external view returns (uint16);
    function getEntireSystemColl() external view returns (uint256);
    function getEntireSystemDebt() external view returns (uint256);
    function CCR() external view returns (uint256);
    function checkRecoveryMode(uint256 price) external view returns (bool);
}

interface IPriceFeed {
    function fetchPrice() external view returns (uint256);
}

interface ISortedTroves {
    function getPrev(address id) external view returns (address);
    function getNext(address id) external view returns (address);
}

interface IHintHelpers {
    function getApproxHint(uint256 cr, uint256 numTrials, uint256 inputRandomSeed)
        external
        view
        returns (address hintAddress, uint256 diff, uint256 latestRandomSeed);
}

interface ICollSurplusPool {
    function getCollateral(address account) external view returns (uint256);
}

interface IActivePool {
    function getInterest() external view returns (uint256);
}

interface IInterestRateManager {
    function interestRate() external view returns (uint16);
}

// MUSDSavingsRate (sMUSD), a one to one receipt token whose yield accrues through a global index
interface ISavings {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimYield() external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function yieldIndex() external view returns (uint256);
    function supplyYieldIndex(address account) external view returns (uint256);
    function claimableYield(address account) external view returns (uint256);
}

// A paused factory still quotes, but its pools refuse every swap
interface IPoolFactory {
    function isPaused() external view returns (bool);
}

interface IRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, Route[] memory routes)
        external
        view
        returns (uint256[] memory amounts);
}

// Mezo Earn veBTC, the lock NFTs that vote on gauges
interface IVeBTC {
    function token() external view returns (address);
    function voter() external view returns (address);
    function distributor() external view returns (address);
    function createLock(uint256 value, uint256 lockDuration) external returns (uint256);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function withdraw(uint256 tokenId) external;
    function voted(uint256 tokenId) external view returns (bool);
    function votingPowerOfNFT(uint256 tokenId) external view returns (uint256);
}

// Mezo Earn Pools Voter, where a vote names the pool and the gauge follows from it
interface IVoter {
    function ve() external view returns (address);
    function gauges(address pool) external view returns (address);
    function isAlive(address gauge) external view returns (bool);
    function gaugeToFees(address gauge) external view returns (address);
    function gaugeToBribe(address gauge) external view returns (address);
    function lastVoted(uint256 tokenId) external view returns (uint256);
    function votes(uint256 tokenId, address pool) external view returns (uint256);
    function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata weights) external;
    function reset(uint256 tokenId) external;
    function poke(uint256 tokenId) external;
}

interface IReward {
    function getReward(uint256 tokenId, address[] memory tokens) external;
}

interface IRewardsDistributor {
    function claim(uint256 tokenId) external returns (uint256);
}
