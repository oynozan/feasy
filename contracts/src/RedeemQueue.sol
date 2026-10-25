// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * First-in-first-out redemption queue of the vault.
 *
 * The vault escrows requested shares here and they stay in the share supply,
 * so they keep their part of every gain and loss until a fill burns them at
 * the share price of that moment. Each fill sends its BTC here and adds one
 * cumulative checkpoint, so a fill costs the same however long the queue is
 * and a claim finds its part inside the right fill. Claims pull, need no
 * price, and pay only the receiver fixed at request time.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {QueueMath} from "./QueueMath.sol";

interface IEscrow {
    function escrow(address owner, address spender, uint256 shares) external;
}

contract RedeemQueue is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Request {
        address owner;
        address receiver;
        uint128 end;
        uint128 claimed;
    }

    uint256 public constant MAX_CLAIMS = 16;

    address public immutable vault;
    IERC20 public immutable btc;

    Request[] private _requests;
    QueueMath.Fill[] private _fills;
    mapping(address => uint256[]) private _ids;
    uint256 public queuedShares;
    uint256 public filledShares;
    uint256 public reserved;

    event RedeemRequested(
        uint256 indexed id, address indexed owner, address indexed receiver, uint256 shares
    );
    event QueueFilled(uint256 shares, uint256 assets, uint256 filledShares);
    event Claimed(
        uint256 indexed id,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    error NotVault();
    error BadReceiver();
    error BadParams();

    constructor(IERC20 btc_) {
        vault = msg.sender;
        btc = btc_;
        _requests.push();
        _fills.push();
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    // Shares stay in the supply while they wait, so they keep their part of gains and losses
    function requestRedeem(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (shares == 0) revert BadParams();
        // A 0x7b7c system address could never spend the BTC it is paid
        if (
            receiver == address(0) || receiver == vault || receiver == address(this)
                || bytes2(bytes20(receiver)) == 0x7b7c
        ) revert BadReceiver();
        IEscrow(vault).escrow(owner, msg.sender, shares);
        uint256 start = queuedShares;
        queuedShares = start + shares;
        id = _requests.length;
        _requests.push(
            Request(owner, receiver, SafeCast.toUint128(start + shares), SafeCast.toUint128(start))
        );
        _ids[owner].push(id);
        emit RedeemRequested(id, owner, receiver, shares);
    }

    function fill(uint256 shares) external payable onlyVault {
        // A fill of no shares would hand its BTC to whichever shares come next
        if (shares == 0) revert BadParams();
        uint256 filled = filledShares + shares;
        filledShares = filled;
        reserved += msg.value;
        uint256 total = _fills[_fills.length - 1].assets + msg.value;
        _fills.push(QueueMath.Fill(SafeCast.toUint128(filled), SafeCast.toUint128(total)));
        emit QueueFilled(shares, msg.value, filled);
    }

    // Anyone may call, each request is paid only to its own receiver
    function claim(uint256[] calldata ids) external nonReentrant returns (uint256 assets) {
        if (ids.length > MAX_CLAIMS) revert BadParams();
        for (uint256 i; i < ids.length; i++) {
            assets += _claim(ids[i]);
        }
    }

    function pending() external view returns (uint256) {
        return queuedShares - filledShares;
    }

    function requestCount() external view returns (uint256) {
        return _requests.length - 1;
    }

    function requestsOf(address owner) external view returns (uint256[] memory) {
        return _ids[owner];
    }

    // Unfilled shares queued ahead of this request
    function sharesAhead(uint256 id) external view returns (uint256) {
        if (id >= _requests.length) return 0;
        return uint256(_requests[id].claimed).saturatingSub(filledShares);
    }

    function queueState()
        external
        view
        returns (uint256 queued, uint256 filled, uint256 reservedBtc, uint256 requests)
    {
        return (queuedShares, filledShares, reserved, _requests.length - 1);
    }

    function getRequest(uint256 id) external view returns (Request memory r) {
        if (id < _requests.length) r = _requests[id];
    }

    function pendingRedeem(uint256 id) external view returns (uint256) {
        if (id >= _requests.length) return 0;
        Request memory r = _requests[id];
        return r.end - Math.max(r.claimed, Math.min(r.end, filledShares));
    }

    function claimableRedeem(uint256 id) external view returns (uint256) {
        if (id >= _requests.length) return 0;
        Request memory r = _requests[id];
        uint256 to = Math.min(r.end, filledShares);
        return to > r.claimed ? QueueMath.paid(_fills, r.claimed, to) : 0;
    }

    function _claim(uint256 id) internal returns (uint256 assets) {
        if (id == 0 || id >= _requests.length) revert BadParams();
        Request storage r = _requests[id];
        uint256 from = r.claimed;
        uint256 to = Math.min(r.end, filledShares);
        if (to <= from) return 0;
        assets = QueueMath.paid(_fills, from, to);
        r.claimed = uint128(to);
        reserved -= assets;
        if (assets > 0) btc.safeTransfer(r.receiver, assets);
        emit Claimed(id, r.owner, r.receiver, to - from, assets);
    }
}
