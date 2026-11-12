// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * An ERC-20 whose holders earn BTC and MUSD just by holding it.
 *
 * Income is streamed to holders over the seven days after it arrives, so
 * whoever holds the token for that week earns it, not whoever buys in just
 * before a payout. Every balance change settles both streams first. Direct
 * credits pay one account at once, for the protocol fee and the veMEZO cut.
 * owedTotal is every token promised and not yet paid, so a contract can tell
 * new income from what it already owes. A stream that runs while nobody holds
 * the token gives its part back to income instead of losing it, and that part
 * is kept apart so it is never charged a fee twice. Income under a tenth of
 * what a running stream still owes joins it without moving its end, so tiny
 * donations cannot stretch a payout out.
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract LockerRewards is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Stream {
        uint256 perToken;
        uint256 rate;
        uint64 finish;
        uint64 updated;
    }

    uint256 public constant DURATION = 7 days;
    uint256 private constant ACC = 1e18;

    IERC20 public immutable btc;
    IERC20 public immutable musd;

    mapping(IERC20 => Stream) public streams;
    mapping(IERC20 => uint256) public owedTotal;
    // Streamed while nobody held the token, back in income and already charged
    mapping(IERC20 => uint256) internal _returned;
    mapping(IERC20 => mapping(address => uint256)) private _paid;
    mapping(IERC20 => mapping(address => uint256)) private _owed;

    event RewardStreamed(address indexed token, uint256 amount, uint256 finish);
    event RewardCredited(address indexed token, address indexed account, uint256 amount);
    event RewardPaid(address indexed account, address indexed token, uint256 amount);

    constructor(IERC20 btc_, IERC20 musd_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {
        btc = btc_;
        musd = musd_;
    }

    function perToken(IERC20 token) public view returns (uint256) {
        Stream memory s = streams[token];
        uint256 to = Math.min(block.timestamp, s.finish);
        uint256 supply = totalSupply();
        if (to <= s.updated || supply == 0) return s.perToken;
        return s.perToken + (to - s.updated) * s.rate / supply;
    }

    function earned(IERC20 token, address account) public view returns (uint256) {
        return _owed[token][account]
            + balanceOf(account) * (perToken(token) - _paid[token][account]) / ACC;
    }

    // What one token pays all holders together each second, in that token's wei
    function rewardRate(IERC20 token) external view returns (uint256) {
        Stream memory s = streams[token];
        return block.timestamp < s.finish ? s.rate / ACC : 0;
    }

    function claim() external nonReentrant returns (uint256 btcPaid, uint256 musdPaid) {
        btcPaid = _pay(btc, msg.sender);
        musdPaid = _pay(musd, msg.sender);
    }

    // Income above what is owed, BTC also leaves out what the caller holds as principal
    function _income(IERC20 token, uint256 principal) internal view returns (uint256) {
        uint256 held = token.balanceOf(address(this));
        uint256 owed = owedTotal[token] + principal;
        return held > owed ? held - owed : 0;
    }

    // What came back from an unheld stream, cleared as it is streamed again
    function _takeReturned(IERC20 token, uint256 income) internal returns (uint256 back) {
        back = Math.min(_returned[token], income);
        _returned[token] = 0;
    }

    // Starts a week long stream, adding what is left of the running one
    function _stream(IERC20 token, uint256 amount) internal {
        if (amount == 0) return;
        _checkpoint(token);
        Stream storage s = streams[token];
        uint256 left = s.finish > block.timestamp ? (s.finish - block.timestamp) * s.rate : 0;
        if (amount * ACC * 10 < left) {
            s.rate += amount * ACC / (s.finish - block.timestamp);
        } else {
            s.rate = (amount * ACC + left) / DURATION;
            s.finish = uint64(block.timestamp + DURATION);
        }
        s.updated = uint64(block.timestamp);
        owedTotal[token] += amount;
        emit RewardStreamed(address(token), amount, s.finish);
    }

    function _credit(IERC20 token, address account, uint256 amount) internal {
        if (amount == 0) return;
        _owed[token][account] += amount;
        owedTotal[token] += amount;
        emit RewardCredited(address(token), account, amount);
    }

    function _pay(IERC20 token, address account) internal returns (uint256 amount) {
        _checkpoint(token);
        _accrue(token, account);
        amount = _owed[token][account];
        if (amount == 0) return 0;
        _owed[token][account] = 0;
        owedTotal[token] -= amount;
        token.safeTransfer(account, amount);
        emit RewardPaid(account, address(token), amount);
    }

    function _checkpoint(IERC20 token) private {
        Stream storage s = streams[token];
        uint256 to = Math.min(block.timestamp, s.finish);
        if (to <= s.updated) return;
        uint256 supply = totalSupply();
        if (supply == 0) {
            uint256 back = (to - s.updated) * s.rate / ACC;
            owedTotal[token] -= back;
            _returned[token] += back;
        } else {
            s.perToken += (to - s.updated) * s.rate / supply;
        }
        s.updated = uint64(to);
    }

    function _accrue(IERC20 token, address account) private {
        uint256 index = streams[token].perToken;
        _owed[token][account] += balanceOf(account) * (index - _paid[token][account]) / ACC;
        _paid[token][account] = index;
    }

    function _update(address from, address to, uint256 value) internal override {
        _settle(btc, from, to);
        _settle(musd, from, to);
        super._update(from, to, value);
    }

    function _settle(IERC20 token, address from, address to) private {
        _checkpoint(token);
        if (from != address(0)) _accrue(token, from);
        if (to != address(0)) _accrue(token, to);
    }
}
