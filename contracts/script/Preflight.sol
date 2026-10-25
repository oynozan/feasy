// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
 * Vault scenarios against the live Mezo testnet, one eth_call each.
 * Only this harness is injected (code override) and given BTC (balance
 * override), every Mezo contract and its state is the real one.
 * One eth_call is one transaction, so each scenario stays inside Mezo's 20
 * precompile calls and ends by reporting how many it left unused. Scenarios
 * that need a lean setup open at 1% slippage, where the testnet pool (about
 * 2.6% under the oracle) cannot fill the MUSD buy-back, which also exercises
 * the vault's degraded mode.
 * A paired scenario does not fit one budget, so preflight.py runs it again at
 * the same block with ALT set in its id. That run skips or swaps the step
 * under test, and the script diffs the two budgets and the views read after it.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vault} from "../src/Vault.sol";
import {RedeemQueue} from "../src/RedeemQueue.sol";
import {VeSleeve} from "../src/VeSleeve.sol";
import {
    IBorrowerOperations,
    IHintHelpers,
    ISavings,
    IRouter,
    IVoter
} from "../src/interfaces/IMezo.sol";

interface IVeLike {
    function distributor() external view returns (address);
    function checkpoint() external;
}

interface IDistributorLike {
    function claim(uint256 id) external returns (uint256);
    function depositor() external view returns (address);
}

interface ISavingsYield {
    function receiveProtocolYield(uint256 amount) external;
}

contract User {
    function call(address target, bytes calldata data)
        external
        returns (bool ok, bytes memory out)
    {
        (ok, out) = target.call(data);
    }
}

contract Preflight {
    address constant BTC = 0x7b7C000000000000000000000000000000000000;
    address constant BORROWER_OPS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address constant HINT_HELPERS = 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant ROUTER = 0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9;
    address constant POOL_FACTORY = 0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A;
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant VOTER = 0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D;
    // A live v7 rung, its first flip is Oct 29
    uint256 constant LIVE_RUNG = 1724;
    uint256 constant CLAIM_GAS = 600_000;
    uint256 constant FILLABLE = 400;
    uint256 constant UNFILLABLE = 100;
    uint256 constant ALT = 1 << 128;

    error StepFailed(string step, bytes reason);

    Vault vault;
    string[] labels;
    uint256[] values;
    bool alt;

    function deploy() external {
        vault = new Vault(
            IERC20(BTC),
            IBorrowerOperations(BORROWER_OPS),
            IHintHelpers(HINT_HELPERS),
            ISavings(SMUSD),
            IRouter(ROUTER),
            POOL_FACTORY,
            address(this),
            address(this),
            7 days,
            IVoter(VOTER),
            "Feasy BTC",
            "fBTC"
        );
        // The vault starts with borrowing off and the trove scenarios need it on
        vault.setBorrowingEnabled(true);
    }

    function scenario(uint256 id) external returns (string[] memory, uint256[] memory) {
        alt = id >= ALT;
        id %= ALT;
        _step("deploy", address(this), abi.encodeCall(this.deploy, ()), 0);
        if (id == 0) {
            _open(0.2 ether, FILLABLE);
        } else if (id == 1) {
            _open(0.2 ether, UNFILLABLE);
            _yield();
            _snap("yield paid", false);
            _step("harvest", address(vault), abi.encodeCall(Vault.harvest, (type(uint256).max)), 0);
        } else if (id == 2) {
            _open(0.2 ether, FILLABLE);
            _step("withdraw 0.05 via trove", address(vault), _withdraw(0.05 ether), 0);
        } else if (id == 3) {
            _open(0.2 ether, FILLABLE);
            _step("redeem max", address(vault), _redeem(vault.maxRedeem(address(this))), 0);
            return _finish(id, false);
        } else if (id == 4) {
            _open(0.2 ether, UNFILLABLE);
            _deposit(0.4 ether);
            _step(
                "rebalance add, refinance, borrow",
                address(vault),
                abi.encodeCall(Vault.rebalance, ()),
                0
            );
        } else if (id == 5) {
            _open(0.2 ether, FILLABLE);
            _params(2.6e18, 2.8e18, 3.5e18, FILLABLE);
            _step("rebalance repay", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        } else if (id == 6) {
            _open(0.2 ether, FILLABLE);
            _step("unwind", address(vault), abi.encodeCall(Vault.unwind, ()), 0);
        } else if (id == 7) {
            _params(2e18, 2.5e18, 3e18, FILLABLE);
            _step(
                "approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), 0.2 ether)), 0
            );
            _step(
                "deposit erc20 0.2",
                address(vault),
                abi.encodeCall(vault.deposit, (0.2 ether, address(this))),
                0
            );
            _step("rebalance open", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        } else if (id == 8 || id == 9) {
            _open(0.08 ether, FILLABLE);
            _step("withdraw", address(vault), _withdraw(id == 8 ? 0.02 ether : 0.04 ether), 0);
        } else if (id == 10) {
            return _twoUsers();
        } else if (id == 11) {
            _open(0.08 ether, FILLABLE);
            _params(3.2e18, 3.4e18, 3.6e18, FILLABLE);
            _step("rebalance close", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        } else if (id == 12) {
            _params(2e18, 2.5e18, 3e18, FILLABLE);
            _step(
                "approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), 0.1 ether)), 0
            );
            _step(
                "mint 0.1e24 shares",
                address(vault),
                abi.encodeCall(vault.mint, (0.1e24, address(this))),
                0
            );
            _step("redeem 0.04e24 shares", address(vault), _redeem(0.04e24), 0);
        } else if (id == 13) {
            _open(0.1 ether, UNFILLABLE);
            uint256 maxAssets = vault.maxWithdraw(address(this));
            _push("maxWithdraw", maxAssets);
            _step("withdraw maxWithdraw", address(vault), _withdraw(maxAssets), 0);
        } else if (id == 14) {
            _open(0.08 ether, UNFILLABLE);
            _params(3.2e18, 3.4e18, 3.6e18, UNFILLABLE);
            _step(
                "rebalance repays to minimum",
                address(vault),
                abi.encodeCall(Vault.rebalance, ()),
                0
            );
        } else if (id == 15) {
            _open(150 ether, FILLABLE);
            _step("withdraw nearly all", address(vault), _withdraw(149.7 ether), 0);
        } else if (id == 16) {
            _open(150 ether, UNFILLABLE);
            _step(
                "withdraw maxWithdraw",
                address(vault),
                _withdraw(vault.maxWithdraw(address(this))),
                0
            );
        } else if (id == 17) {
            _open(0.2 ether, UNFILLABLE);
            _yield();
            _snap("yield paid", false);
            _step(
                "harvest a 50 MUSD chunk", address(vault), abi.encodeCall(Vault.harvest, (50e18)), 0
            );
            return _finish(id, false);
        } else if (id == 18) {
            return _proRata();
        } else if (id == 19) {
            _open(0.2 ether, UNFILLABLE);
            User bob = new User();
            (bool ok,) =
                bob.call(address(vault), abi.encodeCall(Vault.harvest, (type(uint256).max)));
            _expect(!ok, "stranger cannot harvest while the trove is open");
            return _finish(id, false);
        } else if (id == 20) {
            return _inflationAttack();
        } else if (id == 21) {
            return _payoutSnipe();
        } else if (id == 22) {
            return _snipeAfterClose();
        } else if (id == 23) {
            return _donation();
        } else if (id >= 24 && id <= 26) {
            return _continuity(id);
        } else if (id >= 27 && id <= 29) {
            return _priced(id);
        } else if (id >= 30 && id <= 33) {
            return _exactMax(id);
        } else if (id == 34) {
            return _lossNetting();
        } else if (id == 35) {
            return _queueThroughTrove();
        } else if (id == 36) {
            return _queueOrder();
        } else if (id == 37) {
            return _dustRequest();
        } else if (id >= 38 && id <= 40) {
            return _queueBudget(id);
        } else if (id == 41) {
            return _rollBudget();
        } else if (id == 42) {
            return _rebateClaim();
        }
        return _finish(id, true);
    }

    // A sniper deposits just before an sMUSD payout and redeems right after it
    function _payoutSnipe() internal returns (string[] memory, uint256[] memory) {
        User bob = new User();
        _open(0.2 ether, UNFILLABLE);
        _step(
            "bob depositBTC 0.1",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(bob))),
            0.1 ether
        );
        uint256 savings = vault.savingsValue();
        _yield();
        _push("payout to the vault, MUSD", vault.savingsValue() - savings);
        uint256 shares = vault.balanceOf(address(bob));
        _as(
            bob,
            "bob redeems all",
            address(vault),
            abi.encodeCall(vault.redeem, (shares, address(bob), address(bob)))
        );
        _push("bob deposited", 0.1 ether);
        _push("bob got back", address(bob).balance);
        _expect(address(bob).balance <= 0.1 ether, "sniper gets at most its deposit");
        return _done();
    }

    // With no trove anyone may harvest, a sniper tries to catch the sale above the haircut
    function _snipeAfterClose() internal returns (string[] memory, uint256[] memory) {
        User bob = new User();
        _deposit(0.2 ether);
        // What a closed trove leaves behind, a real close does not fit the budget with the rest
        _borrow(2000e18);
        _step(
            "MUSD left on the vault",
            MUSD,
            abi.encodeCall(IERC20.transfer, (address(vault), 2000e18)),
            0
        );
        _step(
            "bob depositBTC 0.1",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(bob))),
            0.1 ether
        );
        _as(bob, "bob harvests", address(vault), abi.encodeCall(Vault.harvest, (type(uint256).max)));
        _push("locked after harvest", vault.lockedProfit());
        uint256 shares = vault.balanceOf(address(bob));
        _as(
            bob,
            "bob redeems all",
            address(vault),
            abi.encodeCall(vault.redeem, (shares, address(bob), address(bob)))
        );
        _push("bob deposited", 0.1 ether);
        _push("bob got back", address(bob).balance);
        _expect(
            !vault.trove().active && IERC20(MUSD).balanceOf(address(vault)) == 0
                && address(bob).balance <= 0.1 ether,
            "harvest sold it all, sniper gets at most its deposit"
        );
        return _done();
    }

    function _donation() internal returns (string[] memory, uint256[] memory) {
        _deposit(0.2 ether);
        uint256 before = vault.totalAssets();
        _donate(0.01 ether);
        uint256 total = vault.totalAssets();
        uint256 pending = vault.pendingProfit();
        _step("sync", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        (,, uint64 unlockAt) = vault.profit();
        uint256 locked = vault.lockedProfit();
        uint256 synced = vault.totalAssets();
        _push("totalAssets before", before);
        _push("totalAssets after donation", total);
        _push("pendingProfit", pending);
        _push("lockedProfit after sync", locked);
        _push("totalAssets after sync", synced);
        _expect(total == before && pending == 0.01 ether, "donation hidden, all of it pending");
        _expect(locked == 0.01 ether && synced == before, "sync locked it, totalAssets unchanged");
        _expect(
            unlockAt == block.timestamp + vault.unlockPeriod(), "unlocks a full period from now"
        );
        return _done();
    }

    // Each step checkpoints a pending gain, the paired run reads the views in its place
    function _continuity(uint256 id) internal returns (string[] memory, uint256[] memory) {
        if (id == 24) {
            _open(0.2 ether, UNFILLABLE);
            _donate(0.01 ether);
            _measured("sync", address(vault), abi.encodeCall(Vault.sync, ()), 2);
        } else if (id == 25) {
            _open(0.2 ether, UNFILLABLE);
            _borrow(2000e18);
            // MUSD keeps idle BTC under the buffer, so the rebalance only checkpoints and parks it
            _step(
                "donate MUSD", MUSD, abi.encodeCall(IERC20.transfer, (address(vault), 2000e18)), 0
            );
            Vault.Trove memory t = vault.trove();
            _measured("rebalance", address(vault), abi.encodeCall(Vault.rebalance, ()), 2);
            Vault.Trove memory t1 = vault.trove();
            _expect(t1.coll == t.coll && t1.debt == t.debt, "rebalance left the trove alone");
        } else {
            _deposit(0.2 ether);
            _borrow(2000e18);
            _step(
                "donate MUSD", MUSD, abi.encodeCall(IERC20.transfer, (address(vault), 2000e18)), 0
            );
            _measured(
                "harvest", address(vault), abi.encodeCall(Vault.harvest, (type(uint256).max)), 5
            );
        }
        _push("view totalAssets", vault.totalAssets());
        _push("view convertToAssets(1e24)", vault.convertToAssets(1e24));
        _push("view maxWithdraw", vault.maxWithdraw(address(this)));
        _push("view maxRedeem", vault.maxRedeem(address(this)));
        return _done();
    }

    // Entry points that move assets must price them at the views read just before
    function _priced(uint256 id) internal returns (string[] memory, uint256[] memory) {
        // The first step checkpoints the opening fee loss, the second a donation at an uneven price
        _open(0.2 ether, UNFILLABLE);
        if (id == 27) {
            uint256 preview = vault.previewDeposit(0.1 ether);
            uint256 shares = vault.balanceOf(address(this));
            _deposit(0.1 ether);
            _priceCheck("depositBTC", vault.balanceOf(address(this)) - shares, preview);
            _donate(0.01 ether);
            preview = vault.previewDeposit(0.1 ether);
            shares = vault.balanceOf(address(this));
            _step(
                "approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), 0.1 ether)), 0
            );
            _step(
                "deposit erc20 0.1",
                address(vault),
                abi.encodeCall(vault.deposit, (0.1 ether, address(this))),
                0
            );
            _priceCheck("deposit", vault.balanceOf(address(this)) - shares, preview);
        } else if (id == 28) {
            uint256 preview = vault.previewMint(0.1e24);
            uint256 btc = address(this).balance;
            _step("approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), preview)), 0);
            _step(
                "mint 0.1e24 shares",
                address(vault),
                abi.encodeCall(vault.mint, (0.1e24, address(this))),
                0
            );
            _priceCheck("mint", btc - address(this).balance, preview);
            _donate(0.01 ether);
            preview = vault.previewWithdraw(0.05 ether);
            uint256 shares = vault.balanceOf(address(this));
            _step("withdraw 0.05", address(vault), _withdraw(0.05 ether), 0);
            _priceCheck("withdraw", shares - vault.balanceOf(address(this)), preview);
        } else {
            RedeemQueue queue = vault.queue();
            uint256 preview = vault.previewRedeem(0.005e24);
            uint256 btc = address(this).balance;
            _step("redeem 0.005e24 shares", address(vault), _redeem(0.005e24), 0);
            _priceCheck("redeem", address(this).balance - btc, preview);
            _request(0.005e24);
            _donate(0.01 ether);
            preview = vault.previewRedeem(0.005e24);
            _step(
                "processQueue",
                address(vault),
                abi.encodeCall(Vault.processQueue, (type(uint256).max)),
                0
            );
            _priceCheck("processQueue", queue.reserved(), preview);
        }
        return _done();
    }

    // Each max is reachable after a payout and a sync under a cap, the paired run tries one more
    function _exactMax(uint256 id) internal returns (string[] memory, uint256[] memory) {
        _step(
            "setParams, 0.5 BTC cap",
            address(vault),
            abi.encodeCall(Vault.setParams, (2e18, 2.5e18, 3e18, 300, UNFILLABLE, 200, 0.5 ether)),
            0
        );
        _deposit(0.2 ether);
        _step("rebalance open", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        // Taking the opening fee loss first leaves an uneven share price, so rounding shows
        _step("sync the opening loss", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        _payout(8000e18);
        _step("sync", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        _push("lockedProfit", vault.lockedProfit());
        _push("totalAssets", vault.recorded() - vault.lockedProfit());
        uint256 extra = alt ? 1 : 0;
        uint256 btc = address(this).balance;
        if (id == 30) {
            uint256 max = vault.maxDeposit(address(this));
            _push("view maxDeposit", max);
            _step(
                "approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), max + extra)), 0
            );
            _try(
                "deposit maxDeposit",
                abi.encodeCall(vault.deposit, (max + extra, address(this))),
                ERC4626.ERC4626ExceededMaxDeposit.selector
            );
            if (!alt) _expect(vault.recorded() == 0.5 ether, "deposits reach the cap exactly");
        } else if (id == 31) {
            uint256 max = vault.maxMint(address(this));
            uint256 shares = vault.balanceOf(address(this));
            _push("view maxMint", max);
            _step(
                "approve BTC", BTC, abi.encodeCall(IERC20.approve, (address(vault), 0.5 ether)), 0
            );
            _try(
                "mint maxMint",
                abi.encodeCall(vault.mint, (max + extra, address(this))),
                ERC4626.ERC4626ExceededMaxMint.selector
            );
            if (!alt) {
                _expect(vault.balanceOf(address(this)) - shares == max, "minted exactly maxMint");
            }
        } else if (id == 32) {
            uint256 max = vault.maxWithdraw(address(this));
            _push("view maxWithdraw", max);
            _try(
                "withdraw maxWithdraw",
                _withdraw(max + extra),
                ERC4626.ERC4626ExceededMaxWithdraw.selector
            );
            if (!alt) _expect(address(this).balance - btc == max, "paid exactly maxWithdraw");
        } else {
            uint256 max = vault.maxRedeem(address(this));
            _push("view maxRedeem", max);
            _try(
                "redeem maxRedeem", _redeem(max + extra), ERC4626.ERC4626ExceededMaxRedeem.selector
            );
            if (!alt) _expect(vault.balanceOf(address(this)) == 0, "redeemed every share");
        }
        return _done();
    }

    // A loss first uses up locked profit, only the part beyond the lock reaches the share price
    function _lossNetting() internal returns (string[] memory, uint256[] memory) {
        _open(150 ether, UNFILLABLE);
        _step("sync the opening loss", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        Vault.Trove memory t = vault.trove();
        uint256 gap =
            t.debt - 200e18 - vault.savingsValue() - IERC20(MUSD).balanceOf(address(vault));
        uint256 base = _cost(gap, UNFILLABLE);
        uint256 inside = _cost(gap, 300) - base;
        uint256 beyond = _cost(gap, 500) - base;
        // Between the loss at 3% and at 5% slippage, so only the second outgrows the lock
        uint256 lock = _cost(gap, 400) - base;
        _donate(lock);
        _step("sync", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        uint256 locked = vault.lockedProfit();
        uint256 before = vault.totalAssets();
        _params(2e18, 2.5e18, 3e18, 300);
        uint256 atInside = vault.totalAssets();
        _params(2e18, 2.5e18, 3e18, 500);
        uint256 atBeyond = vault.totalAssets();
        _push("MUSD gap", gap);
        _push("lockedProfit", locked);
        _push("loss at 3% slippage", inside);
        _push("loss at 5% slippage", beyond);
        _push("totalAssets at 1%", before);
        _push("totalAssets at 3%", atInside);
        _push("totalAssets at 5%", atBeyond);
        _expect(locked == lock && atInside == before, "loss inside the lock leaves totalAssets");
        _expect(
            before >= atBeyond && before - atBeyond == beyond - lock,
            "loss beyond the lock costs only the excess"
        );
        return _done();
    }

    // A request beyond the instant cap waits, processQueue frees collateral for it
    function _queueThroughTrove() internal returns (string[] memory, uint256[] memory) {
        RedeemQueue queue = vault.queue();
        _open(0.2 ether, UNFILLABLE);
        uint256 shares = vault.balanceOf(address(this));
        uint256 instant = vault.maxRedeem(address(this));
        uint256 total = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        Vault.Trove memory t = vault.trove();
        _request(shares);
        _step(
            "processQueue",
            address(vault),
            abi.encodeCall(Vault.processQueue, (type(uint256).max)),
            0
        );
        Vault.Trove memory t1 = vault.trove();
        uint256 filled = queue.filledShares();
        uint256 assets = queue.reserved();
        _snap("filled", false);
        _push("instant maxRedeem e24", instant / 1e6);
        _push("requested e24", shares / 1e6);
        _push("filled e24", filled / 1e6);
        _push("paid into the queue", assets);
        _expect(
            shares > instant && filled > 0 && filled < shares,
            "request beyond the instant cap, partly filled"
        );
        _expect(t1.active && t1.coll < t.coll, "fill freed collateral, trove stays");
        _expect(
            assets == Math.mulDiv(filled, total + 1, supply + 1e6)
                && vault.totalSupply() == supply - filled,
            "burned at the share price"
        );
        uint256 btc = address(this).balance;
        _claim(1, 1);
        _expect(
            address(this).balance - btc == assets && queue.reserved() == 0,
            "claim paid the receiver, reserved back to 0"
        );
        return _done();
    }

    // Requests are paid in arrival order, a capped fill pays the head and part of the next
    function _queueOrder() internal returns (string[] memory, uint256[] memory) {
        RedeemQueue queue = vault.queue();
        User[3] memory to = [new User(), new User(), new User()];
        _deposit(0.3 ether);
        for (uint256 i; i < 3; i++) {
            _step(
                "requestRedeem 0.1e24",
                address(queue),
                abi.encodeCall(RedeemQueue.requestRedeem, (0.1e24, address(to[i]), address(this))),
                0
            );
        }
        _step(
            "processQueue up to 0.15 BTC",
            address(vault),
            abi.encodeCall(Vault.processQueue, (0.15 ether)),
            0
        );
        uint256 first = queue.claimableRedeem(1);
        uint256 second = queue.claimableRedeem(2);
        _push("claimable 1", first);
        _push("claimable 2", second);
        _push("claimable 3", queue.claimableRedeem(3));
        _push("shares ahead of 3 e24", queue.sharesAhead(3) / 1e6);
        _expect(
            first == 0.1 ether && second == 0.05 ether && queue.claimableRedeem(3) == 0
                && queue.sharesAhead(3) == 0.05e24,
            "head paid in full, next in part, last waits"
        );
        _claim(1, 1);
        _step(
            "processQueue the rest",
            address(vault),
            abi.encodeCall(Vault.processQueue, (type(uint256).max)),
            0
        );
        _claim(2, 2);
        _push("receiver 1 BTC", address(to[0]).balance);
        _push("receiver 2 BTC", address(to[1]).balance);
        _push("receiver 3 BTC", address(to[2]).balance);
        _expect(
            address(to[0]).balance == 0.1 ether && address(to[1]).balance == 0.1 ether
                && address(to[2]).balance == 0.1 ether && queue.reserved() == 0
                && queue.pending() == 0,
            "every receiver paid its own request, reserved back to 0"
        );
        return _done();
    }

    // A request worth under 1 wei must not keep the queue pending and shut off borrowing
    function _dustRequest() internal returns (string[] memory, uint256[] memory) {
        RedeemQueue queue = vault.queue();
        _open(0.2 ether, UNFILLABLE);
        _request(1);
        _deposit(0.4 ether);
        Vault.Trove memory t = vault.trove();
        _step("rebalance", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        Vault.Trove memory t1 = vault.trove();
        _snap("end", false);
        _expect(
            queue.pending() == 0 && queue.filledShares() == 1 && queue.reserved() == 0
                && queue.claimableRedeem(1) == 0,
            "dust burned in a 0 BTC fill"
        );
        _expect(t1.coll > t.coll && t1.debt > t.debt, "same rebalance added collateral, borrowed");
        return _done();
    }

    // The paired run stops before the queue step, py diffs the two budgets
    function _queueBudget(uint256 id) internal returns (string[] memory, uint256[] memory) {
        RedeemQueue queue = vault.queue();
        if (id == 38) {
            _open(0.2 ether, UNFILLABLE);
            _request(vault.balanceOf(address(this)));
            _measured(
                "processQueue through the trove",
                address(vault),
                abi.encodeCall(Vault.processQueue, (type(uint256).max)),
                4
            );
            if (!alt) _expect(vault.trove().active && queue.reserved() > 0, "fill left a trove");
        } else if (id == 39) {
            // With no buffer the closing swap has to take collateral out first, the worst case
            _step(
                "setParams, no buffer",
                address(vault),
                abi.encodeCall(
                    Vault.setParams, (2e18, 2.5e18, 3e18, 0, UNFILLABLE, 200, type(uint256).max)
                ),
                0
            );
            _deposit(0.1 ether);
            _step("rebalance open", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
            _params(2e18, 2.5e18, 3e18, FILLABLE);
            _request(vault.balanceOf(address(this)));
            _measured(
                "processQueue closing the trove",
                address(vault),
                abi.encodeCall(Vault.processQueue, (type(uint256).max)),
                11
            );
            if (!alt) {
                _expect(!vault.trove().active && queue.reserved() > 0, "fill closed the trove");
            }
        } else {
            _deposit(0.16 ether);
            for (uint256 i; i < 16; i++) {
                _request(0.01e24);
            }
            // Request 16 stays unfilled, a fully paid 16 would need 21 calls with this setup
            _step(
                "processQueue up to 0.15 BTC - 1",
                address(vault),
                abi.encodeCall(Vault.processQueue, (0.15 ether - 1)),
                0
            );
            uint256 paid;
            for (uint256 i = 1; i <= 16; i++) {
                if (queue.claimableRedeem(i) > 0) paid++;
            }
            _push("paid request ids", paid);
            uint256[] memory ids = new uint256[](16);
            for (uint256 i; i < 16; i++) {
                ids[i] = i + 1;
            }
            _measured("claim 16 ids", address(queue), abi.encodeCall(RedeemQueue.claim, (ids)), 15);
            if (!alt) {
                _expect(
                    queue.reserved() == 0 && queue.pendingRedeem(16) == 0.01e24,
                    "claimed all filled BTC, request 16 still waits"
                );
            }
        }
        return _done();
    }

    // The keeper's first roll reads the price and opens two rungs, approve and createLock each
    function _rollBudget() internal returns (string[] memory, uint256[] memory) {
        VeSleeve sleeve = vault.sleeve();
        _step(
            "setSleeve 25%, two weeks",
            address(sleeve),
            abi.encodeCall(VeSleeve.setSleeve, (2500, type(uint256).max, 2)),
            0
        );
        _deposit(0.1 ether);
        _measured("bootstrap roll", address(vault), abi.encodeCall(Vault.roll, ()), 6);
        if (!alt) {
            uint256 sum;
            uint256 n;
            for (uint256 i; i < 4; i++) {
                (uint256 rung, uint128 amount, uint64 end) = sleeve.rungs(i);
                if (rung == 0) continue;
                n++;
                sum += amount;
                _push("rung end", end);
                _expect(end % 7 days == 0, "rung ends on a Thursday at 00:00 UTC");
            }
            _push("sleeve principal", sleeve.principal());
            // A caught Earn call that ran out of budget would leave a rung missing, not a revert
            _expect(
                n == 2 && sum == sleeve.principal() && sum == 0.025 ether,
                "two rungs hold the 25% share"
            );
        }
        return _done();
    }

    // Run at a block between the flip and veBTC's first write, the paired run checkpoints first
    function _rebateClaim() internal returns (string[] memory, uint256[] memory) {
        address ve = IVoter(VOTER).ve();
        address distributor = IVeLike(ve).distributor();
        // Claims wait for Mezo's weekly period update, which writes nothing to veBTC
        (bool updated,) = IDistributorLike(distributor)
            .depositor()
            .call(abi.encodeWithSignature("updatePeriod()"));
        _expect(updated, "updatePeriod() ran, a no-op once Mezo ran it");
        if (alt) _step("veBTC checkpoint", ve, abi.encodeCall(IVeLike.checkpoint, ()), 0);
        uint256 gas = gasleft();
        (bool ok, bytes memory reason) =
            distributor.call(abi.encodeCall(IDistributorLike.claim, (LIVE_RUNG)));
        gas -= gasleft();
        if (!ok) _push(string.concat("claim reverted, selector in ids"), uint32(bytes4(reason)));
        _push(alt ? "checkpointed claim gas" : "stale checkpoint claim gas", gas);
        _expect(ok, "claim went through, the period is updated");
        if (alt) _expect(gas < CLAIM_GAS, "fits the sleeve's CLAIM_GAS once checkpointed");
        else _expect(gas > CLAIM_GAS, "stale claim exceeds the sleeve's CLAIM_GAS");
        return _done();
    }

    // First depositor stakes 1 wei then donates BTC straight to the vault, hoping to round the next deposit down
    function _inflationAttack() internal returns (string[] memory, uint256[] memory) {
        User victim = new User();
        _step(
            "attacker depositBTC 1 wei",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(this))),
            1
        );
        _step(
            "attacker donates 0.5 BTC",
            BTC,
            abi.encodeCall(IERC20.transfer, (address(vault), 0.5 ether)),
            0
        );
        _step(
            "victim depositBTC 0.4",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(victim))),
            0.4 ether
        );
        uint256 victimAssets = vault.convertToAssets(vault.balanceOf(address(victim)));
        uint256 attackerAssets = vault.convertToAssets(vault.balanceOf(address(this)));
        _push("victim deposited", 0.4 ether);
        _push("victim now owns", victimAssets);
        _push("attacker paid", 0.5 ether + 1);
        _push("attacker now owns", attackerAssets);
        _expect(
            victimAssets >= 0.4 ether - 0.5 ether / 1e6, "victim loses at most donation over 1e6"
        );
        _expect(attackerAssets < 0.5 ether, "attacker loses money");
        _push("precompile budget left", _budgetLeft());
        return (labels, values);
    }

    // Buys MUSD and pays it to every sMUSD holder the way PCV does, a real protocol yield step
    function _yield() internal {
        _step("approve BTC to router", BTC, abi.encodeCall(IERC20.approve, (ROUTER, 0.2 ether)), 0);
        IRouter.Route[] memory route = new IRouter.Route[](1);
        route[0] = IRouter.Route(BTC, MUSD, false, POOL_FACTORY);
        _step(
            "buy MUSD with 0.2 BTC",
            ROUTER,
            abi.encodeCall(
                IRouter.swapExactTokensForTokens,
                (0.2 ether, 1, route, address(this), block.timestamp)
            ),
            0
        );
        _pay(IERC20(MUSD).balanceOf(address(this)));
    }

    // The same payout as _yield, funded by a harness trove to save three precompile calls
    function _payout(uint256 amount) internal {
        _borrow(amount);
        _pay(amount);
    }

    function _pay(uint256 amount) internal {
        _step("approve MUSD to sMUSD", MUSD, abi.encodeCall(IERC20.approve, (SMUSD, amount)), 0);
        _step(
            "sMUSD receiveProtocolYield",
            SMUSD,
            abi.encodeCall(ISavingsYield.receiveProtocolYield, (amount)),
            0
        );
    }

    // Opens the harness's own trove at 400%, it prices off the vault's last oracle read
    function _borrow(uint256 amount) internal {
        uint256 coll = Math.mulDiv(amount, 4e18, vault.lastPrice());
        uint256 nicr = Math.mulDiv(coll, 1e20, amount + 200e18);
        (address hint,,) = IHintHelpers(HINT_HELPERS).getApproxHint(nicr, 15, nicr);
        _step(
            "harness borrows MUSD",
            BORROWER_OPS,
            abi.encodeCall(IBorrowerOperations.openTrove, (amount, hint, hint)),
            coll
        );
    }

    // A BTC token transfer, the one donation the vault cannot refuse
    function _donate(uint256 amount) internal {
        _step("donate BTC", BTC, abi.encodeCall(IERC20.transfer, (address(vault), amount)), 0);
    }

    function _open(uint256 amount, uint256 slippage) internal {
        _params(2e18, 2.5e18, 3e18, slippage);
        _deposit(amount);
        _step("rebalance open", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        _snap("opened", false);
    }

    function _deposit(uint256 amount) internal {
        _step(
            "depositBTC", address(vault), abi.encodeCall(Vault.depositBTC, (address(this))), amount
        );
    }

    // A second depositor joins after the trove opens, then an sMUSD payout arrives and is synced
    function _twoUsers() internal returns (string[] memory, uint256[] memory) {
        User bob = new User();
        _open(0.2 ether, UNFILLABLE);
        _step(
            "bob depositBTC 0.1",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(bob))),
            0.1 ether
        );
        // Right after a deposit raw equals recorded, so this is what totalAssets reads
        uint256 before = vault.recorded() - vault.lockedProfit();
        _payout(8000e18);
        _snap("end", false);
        uint256 total = vault.totalAssets();
        uint256 pending = vault.pendingProfit();
        _step("sync", address(vault), abi.encodeCall(Vault.sync, ()), 0);
        uint256 locked = vault.lockedProfit();
        uint256 synced = vault.totalAssets();
        _push("totalAssets before payout", before);
        _push("totalAssets after payout", total);
        _push("pendingProfit", pending);
        _push("lockedProfit after sync", locked);
        _push("totalAssets after sync", synced);
        _expect(total == before && pending > 0, "payout left totalAssets alone, all of it pending");
        _expect(locked == pending && synced == before, "sync locked the payout, totalAssets held");
        _push("precompile budget left", _budgetLeft());
        return (labels, values);
    }

    // When a close cannot be bought, exit liquidity is split by share, not first come
    function _proRata() internal returns (string[] memory, uint256[] memory) {
        User bob = new User();
        _params(2e18, 2.5e18, 3e18, UNFILLABLE);
        _deposit(150 ether);
        _step(
            "bob depositBTC 0.1",
            address(vault),
            abi.encodeCall(Vault.depositBTC, (address(bob))),
            0.1 ether
        );
        _step("rebalance open", address(vault), abi.encodeCall(Vault.rebalance, ()), 0);
        uint256 total = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        uint256 aliceMax = vault.maxWithdraw(address(this));
        uint256 bobMax = vault.maxWithdraw(address(bob));
        uint256 bobAssets = total * vault.balanceOf(address(bob)) / supply;
        _push("alice assets", total * vault.balanceOf(address(this)) / supply);
        _push("alice maxWithdraw", aliceMax);
        _push("bob assets", bobAssets);
        _push("bob maxWithdraw", bobMax);
        _step("alice withdraws her max", address(vault), _withdraw(aliceMax), 0);
        _expect(bobMax > bobAssets * 99 / 100, "bob keeps his pro rata exit");
        _snap("end", false);
        _push("precompile budget left", _budgetLeft());
        return (labels, values);
    }

    // Snapshot, price-free invariant checks, then the unused precompile budget
    function _finish(uint256 id, bool priced) internal returns (string[] memory, uint256[] memory) {
        _snap("end", priced);
        Vault.Trove memory t = vault.trove();
        uint256 user = address(this).balance;
        uint256 owed = t.debt > 200e18 ? t.debt - 200e18 : 0;
        uint256 held =
            vault.savingsValue() + IERC20(address(vault.musd())).balanceOf(address(vault));
        if (id == 0 || id == 7) {
            _expect(t.active && t.coll == 0.194 ether && held >= owed, "opened, gap bought");
        }
        if (id == 1) {
            _expect(
                held >= owed && address(vault).balance > 0.006 ether, "harvest kept cover, BTC up"
            );
        }
        if (id == 2) _expect(t.active && user == 0.85 ether, "withdrawal paid in full");
        if (id == 3) {
            _expect(!t.active && user > 0.999 ether, "exit closed the trove without a swap");
        }
        if (id == 4) _expect(t.coll > 0.58 ether, "big deposit went into the trove");
        if (id == 5) _expect(t.active && held >= owed, "trove repaid toward target");
        if (id == 6 || id == 11) {
            _expect(!t.active && address(vault).balance > 0.0798 ether, "trove closed");
        }
        if (id == 8) _expect(t.debt == 2000e18 && user == 0.94 ether, "loan pinned at minimum");
        if (id == 9) _expect(!t.active && user == 0.96 ether, "withdrawal closed the trove");
        if (id == 12) _expect(user == 0.94 ether, "mint and redeem round trip");
        if (id == 13) {
            _expect(t.debt < 2001e18 && user > 0.93 ether, "exit stopped short of a close");
        }
        if (id == 14) _expect(t.active && t.debt == 2000e18, "repaid to the minimum loan");
        if (id == 15) {
            _expect(t.active && user == 299.7 ether, "big exit paid, loan back at target");
        }
        if (id == 16) {
            _expect(
                t.active && held < 1e12 && user > 299.84 ether, "big exit repaid with all MUSD held"
            );
        }
        if (id == 17) {
            _expect(
                t.active && held > owed && address(vault).balance > 0.006 ether,
                "chunk sold, rest kept"
            );
        }
        _push("precompile budget left", _budgetLeft());
        return (labels, values);
    }

    function _params(uint256 minCR, uint256 targetCR, uint256 maxCR, uint256 slippage) internal {
        _step(
            "setParams",
            address(vault),
            abi.encodeCall(
                Vault.setParams, (minCR, targetCR, maxCR, 300, slippage, 200, type(uint256).max)
            ),
            0
        );
    }

    function _withdraw(uint256 assets) internal view returns (bytes memory) {
        return abi.encodeCall(vault.withdraw, (assets, address(this), address(this)));
    }

    function _redeem(uint256 shares) internal view returns (bytes memory) {
        return abi.encodeCall(vault.redeem, (shares, address(this), address(this)));
    }

    function _request(uint256 shares) internal {
        _step(
            "requestRedeem",
            address(vault.queue()),
            abi.encodeCall(RedeemQueue.requestRedeem, (shares, address(this), address(this))),
            0
        );
    }

    function _claim(uint256 first, uint256 count) internal {
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; i++) {
            ids[i] = first + i;
        }
        _step("claim", address(vault.queue()), abi.encodeCall(RedeemQueue.claim, (ids)), 0);
    }

    // Mirrors the vault's _btcCost at its last price
    function _cost(uint256 musdAmount, uint256 slippage) internal view returns (uint256) {
        return Math.mulDiv(
            musdAmount, (10_000 + slippage) * 1e18, vault.lastPrice() * 10_000, Math.Rounding.Ceil
        );
    }

    function _as(User user, string memory step, address target, bytes memory data) internal {
        uint256 gas = gasleft();
        (bool ok, bytes memory reason) = user.call(target, data);
        if (!ok) revert StepFailed(step, reason);
        _push(string.concat(step, " gas"), gas - gasleft());
    }

    // The paired run skips this step, py reads its precompile calls off the two budgets
    function _measured(string memory step, address target, bytes memory data, uint256 calls)
        internal
    {
        _push(string.concat(step, " expected precompile calls"), calls);
        if (!alt) _step(step, target, data, 0);
    }

    // The plain run must succeed at max, the paired run at max + 1 must fail the max check
    function _try(string memory step, bytes memory data, bytes4 error) internal {
        if (!alt) {
            _step(step, address(vault), data, 0);
            return;
        }
        (bool ok, bytes memory reason) = address(vault).call(data);
        _expect(!ok && bytes4(reason) == error, string.concat(step, " + 1 fails the max check"));
    }

    function _priceCheck(string memory step, uint256 used, uint256 preview) internal {
        _push(string.concat(step, " used"), used);
        _push(string.concat(step, " preview"), preview);
        _expect(used == preview, string.concat(step, " priced at the view read just before"));
    }

    function _done() internal returns (string[] memory, uint256[] memory) {
        _push("precompile budget left", _budgetLeft());
        return (labels, values);
    }

    function _step(string memory step, address target, bytes memory data, uint256 value) internal {
        uint256 gas = gasleft();
        (bool ok, bytes memory reason) = target.call{value: value}(data);
        if (!ok) revert StepFailed(step, reason);
        _push(string.concat(step, " gas"), gas - gasleft());
    }

    // totalAssets reads the oracle, two precompile calls, so only the last snapshot is priced
    function _snap(string memory tag, bool priced) internal {
        Vault.Trove memory t = vault.trove();
        _push(string.concat("== ", tag), 0);
        _push("vault idle BTC", address(vault).balance);
        _push("trove coll", t.coll);
        _push("trove debt", t.debt);
        _push("savings value", vault.savingsValue());
        _push("vault idle MUSD", IERC20(address(vault.musd())).balanceOf(address(vault)));
        _push("totalSupply e24", vault.totalSupply() / 1e6);
        _push("user BTC", address(this).balance);
        if (priced) _push("totalAssets", vault.totalAssets());
    }

    function _expect(bool ok, string memory what) internal {
        _push(string.concat(ok ? "check ok: " : "CHECK FAILED: ", what), 0);
    }

    function _budgetLeft() internal view returns (uint256 n) {
        for (uint256 i; i < 20; i++) {
            (bool ok,) =
                BTC.staticcall{gas: 50_000}(abi.encodeCall(IERC20.balanceOf, (address(this))));
            if (ok) n++;
        }
    }

    function _push(string memory label, uint256 value) internal {
        labels.push(label);
        values.push(value);
    }
}
