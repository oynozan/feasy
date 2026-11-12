// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BtcLocker} from "vault/BtcLocker.sol";
import {MezoLocker} from "vault/MezoLocker.sol";
import {LockerRewards} from "vault/LockerRewards.sol";
import {IVoter, IBoostVoter, ISavings} from "vault/interfaces/IMezo.sol";
import {SleeveBase, IEarnVe} from "./SleeveBase.sol";

interface IVeNft {
    function approve(address spender, uint256 id) external;
    function unlockPermanent(uint256 id) external;
}

interface IWhitelist {
    function whitelistToken(address token, bool allowed) external;
}

// The liquid locker on Mezo's own veBTC, Voter, veMEZO and BoostVoter, MEZO played by a tigris LP
contract LockerTest is SleeveBase {
    uint256 constant BPS = 10_000;

    BtcLocker locker;
    MezoLocker mezoLocker;
    address treasury = makeAddr("treasury");
    address erin = makeAddr("erin");

    function setUp() public override {
        super.setUp();
        _lpEarn();
        locker = new BtcLocker(IVoter(address(voter)), btc, musd, savings, treasury);
        mezoLocker = locker.mezoLocker();
    }

    /* Helpers */

    function _deposit(address user, uint256 amount) internal {
        vm.deal(user, user.balance + amount);
        vm.prank(user);
        locker.deposit{value: amount}(user);
    }

    function _mezo(address user, uint256 amount) internal {
        vm.prank(whale);
        IERC20(lp).transfer(user, amount);
    }

    function _depositMezo(address user, uint256 amount) internal {
        _mezo(user, amount);
        vm.startPrank(user);
        IERC20(lp).approve(address(mezoLocker), amount);
        mezoLocker.deposit(amount, user);
        vm.stopPrank();
    }

    // A veBTC lock of the user's own, ending at the Thursday its duration rounds down to
    function _veLock(address user, uint256 amount, uint256 duration) internal returns (uint256 id) {
        vm.deal(user, user.balance + amount);
        vm.startPrank(user);
        btc.approve(address(ve), amount);
        id = ve.createLock(amount, duration);
        IVeNft(address(ve)).approve(address(locker), id);
        vm.stopPrank();
    }

    function _nextWeek(uint256 k) internal {
        vm.warp(_epoch(k) + 1 minutes);
        _mezoWeek(true);
        vm.warp(_epoch(k) + 1 hours + 1);
    }

    function _rung(uint256 end) internal view returns (uint256 id, uint256 amount) {
        (uint256 rid, uint128 ramount, uint64 rend) = locker.rungs(end / WEEK % 4);
        if (rend == end) return (rid, ramount);
    }

    // Supply plus the unfilled queue always equals principal in the ladder and out of it
    function _assertBacked() internal view {
        assertEq(
            locker.totalSupply() + locker.queued() - locker.filled(),
            locker.locked() + locker.idle(),
            "principal backs every fveBTC and queued request"
        );
        assertGe(
            btc.balanceOf(address(locker)),
            locker.idle() + locker.reserved() + locker.owedTotal(btc),
            "BTC covers idle, queue and rewards"
        );
    }

    /* Wiring */

    function test_wiring() public view {
        assertEq(locker.name(), "Feasy liquid veBTC");
        assertEq(locker.symbol(), "fveBTC");
        assertEq(address(locker.ve()), address(ve));
        assertEq(locker.pool(), savings);
        assertEq(locker.gauge(), gauge);
        assertEq(address(locker.boostVoter()), lpBooster);
        assertEq(locker.owner(), address(this));
        assertEq(locker.guardian(), address(this));
        assertEq(locker.treasury(), treasury);
        assertEq(locker.boostBps(), 1500);
        assertEq(locker.feeBps(), 500);
        assertTrue(locker.live());

        assertEq(mezoLocker.symbol(), "fveMEZO");
        assertEq(address(mezoLocker.ladder()), address(locker));
        assertEq(address(mezoLocker.veMezo()), lpVe);
        assertEq(address(mezoLocker.mezo()), lp);
        assertEq(address(mezoLocker.ve()), address(ve));
        assertEq(address(mezoLocker.boostVoter()), lpBooster);
    }

    function test_constructorChecksWiring() public {
        vm.expectRevert(BtcLocker.BadLocker.selector);
        new BtcLocker(IVoter(address(voter)), btc, musd, address(musd), treasury);
        vm.expectRevert(BtcLocker.BadLocker.selector);
        new BtcLocker(IVoter(address(voter)), musd, musd, savings, treasury);
    }

    /* Deposits */

    function test_depositOpensLongestRungAndVotes() public {
        _deposit(alice, 1 ether);
        assertEq(locker.balanceOf(alice), 1 ether, "one fveBTC for one BTC");
        (uint256 id, uint256 amount) = _rung(_epoch(4));
        assertGt(id, 0, "rung ends in four Thursdays");
        assertEq(amount, 1 ether);
        assertEq(ve.ownerOf(id), address(locker));
        assertEq(uint256(int256(ve.locked(id).amount)), 1 ether);
        assertEq(voter.votes(id, savings), ve.votingPowerOfNFT(id), "full weight on sMUSD");
        assertEq(locker.locked(), 1 ether);
        assertEq(address(locker).balance, 0, "nothing left loose");
        _assertBacked();
    }

    function test_depositTopsUpTheSameRung() public {
        _deposit(alice, 1 ether);
        (uint256 id,) = _rung(_epoch(4));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _deposit(bob, 0.5 ether);
        (uint256 again, uint256 amount) = _rung(_epoch(4));
        assertEq(again, id, "one rung per week");
        assertEq(amount, 1.5 ether);
        assertEq(voter.votes(id, savings), ve.votingPowerOfNFT(id), "poked to its new size");
        assertEq(locker.totalSupply(), 1.5 ether);
        _assertBacked();
    }

    function test_depositGuards() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(BtcLocker.TooSmall.selector);
        locker.deposit{value: 1e13}(alice);

        vm.prank(stranger);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.setPaused(true);
        address g = makeAddr("guardian2");
        locker.setGuardian(g);
        vm.prank(g);
        locker.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(BtcLocker.Paused.selector);
        locker.deposit{value: 1 ether}(alice);
        vm.prank(g);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.setPaused(false);
        locker.setPaused(false);
        _deposit(alice, 1 ether);

        // A gauge Mezo kills stops new locks
        vm.prank(team);
        voter.killGauge(gauge);
        assertFalse(locker.live());
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(BtcLocker.Paused.selector);
        locker.deposit{value: 1 ether}(bob);
    }

    function test_feesOnlyOwnerAndCapped() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        locker.setFees(0, 0, stranger);
        vm.expectRevert(BtcLocker.BadLocker.selector);
        locker.setFees(3001, 0, treasury);
        vm.expectRevert(BtcLocker.BadLocker.selector);
        locker.setFees(0, 1001, treasury);
        locker.setFees(3000, 1000, carol);
        assertEq(locker.boostBps(), 3000);
        assertEq(locker.feeBps(), 1000);
        assertEq(locker.treasury(), carol);
    }

    /* veBTC lock deposits */

    function test_depositLockMergesIntoItsWeek() public {
        _deposit(alice, 1 ether);
        (uint256 rung,) = _rung(_epoch(4));
        uint256 id = _veLock(erin, 0.4 ether, MAX_LOCK);
        assertEq(ve.locked(id).end, _epoch(4));
        vm.prank(erin);
        locker.depositLock(id, erin);
        assertEq(locker.balanceOf(erin), 0.4 ether, "fveBTC for the whole lock");
        assertEq(ve.ownerOf(id), address(0), "merged and burned");
        (, uint256 amount) = _rung(_epoch(4));
        assertEq(amount, 1.4 ether);
        assertEq(uint256(int256(ve.locked(rung).amount)), 1.4 ether);
        assertEq(ve.locked(rung).end, _epoch(4), "end unchanged");
        _assertBacked();
    }

    function test_depositLockExtendsToTheNextRung() public {
        _deposit(alice, 1 ether);
        uint256 id = _veLock(erin, 0.3 ether, 2 weeks);
        assertEq(ve.locked(id).end, _epoch(2));
        vm.prank(erin);
        locker.depositLock(id, bob);
        assertEq(locker.balanceOf(bob), 0.3 ether, "receiver gets the fveBTC");
        (, uint256 amount) = _rung(_epoch(4));
        assertEq(amount, 1.3 ether, "joined the only rung, two weeks later");
        _assertBacked();
    }

    function test_depositLockRefusals() public {
        uint256 id = _veLock(erin, 0.2 ether, MAX_LOCK);
        vm.prank(erin);
        vm.expectRevert(BtcLocker.NoRung.selector);
        locker.depositLock(id, erin);

        _deposit(alice, 1 ether);
        vm.prank(bob);
        vm.expectRevert();
        locker.depositLock(id, bob);

        vm.prank(erin);
        voter.vote(id, _list(savings), _one());
        vm.prank(erin);
        vm.expectRevert(BtcLocker.Voted.selector);
        locker.depositLock(id, erin);

        uint256 perm = _veLock(erin, 0.2 ether, MAX_LOCK);
        vm.prank(erin);
        ve.lockPermanent(perm);
        vm.prank(erin);
        vm.expectRevert(BtcLocker.BadLock.selector);
        locker.depositLock(perm, erin);
    }

    /* Weekly cycle */

    function test_rollStreamsFeesAndPaysTheCuts() public {
        _deposit(alice, 1 ether);
        _depositMezo(carol, 10e18);
        locker.addBoostGauge(_epoch(4) / WEEK % 4, gaugeFactory);
        mezoLocker.boost();
        _nextWeek(1);
        assertGt(locker.boostShare(), 1500, "the boost adds more than the 15% cap");
        locker.roll();

        uint256 income = musd.balanceOf(address(locker));
        assertGt(income, 0, "E0 fees and bribes claimed in MUSD");
        uint256 cut = income * 1500 / BPS;
        uint256 fee = income * 500 / BPS;
        assertEq(locker.earned(musd, address(mezoLocker)), cut, "fveMEZO cut credited");
        assertEq(locker.earned(musd, treasury), fee, "treasury fee credited");
        assertEq(locker.owedTotal(musd), income, "all of it owed");
        assertEq(locker.earned(musd, alice), 0, "streamed, not paid at once");

        vm.warp(vm.getBlockTimestamp() + 7 days);
        uint256 rest = income - cut - fee;
        assertApproxEqAbs(locker.earned(musd, alice), rest, 1e6, "a week streams it all");
        vm.prank(alice);
        (, uint256 paid) = locker.claim();
        assertEq(musd.balanceOf(alice), paid);
        assertApproxEqAbs(paid, rest, 1e6);

        mezoLocker.harvest();
        assertEq(musd.balanceOf(address(mezoLocker)), cut, "cut pulled");
        vm.warp(vm.getBlockTimestamp() + 7 days);
        assertApproxEqAbs(mezoLocker.earned(musd, carol), cut, 1e6, "fveMEZO streamed the cut");
        vm.prank(treasury);
        locker.claim();
        assertEq(musd.balanceOf(treasury), fee);
        _assertBacked();
    }

    function test_noCutWithoutFveMezo() public {
        _deposit(alice, 1 ether);
        _nextWeek(1);
        locker.roll();
        uint256 income = musd.balanceOf(address(locker));
        assertEq(locker.earned(musd, address(mezoLocker)), 0, "no fveMEZO holder to pay");
        assertEq(locker.earned(musd, treasury), income * 500 / BPS);
    }

    function test_maturityPaysQueueAndRelocks() public {
        _deposit(alice, 1 ether);
        _deposit(bob, 1 ether);
        (uint256 id,) = _rung(_epoch(4));
        vm.prank(alice);
        uint256 req = locker.requestRedeem(1 ether);
        assertEq(locker.balanceOf(alice), 0, "burned into the queue");
        assertEq(locker.claimable(req), 0, "waits for a maturity");
        _assertBacked();

        for (uint256 k = 1; k <= 4; k++) {
            _nextWeek(k);
            locker.roll();
        }
        assertEq(ve.ownerOf(id), address(0), "matured rung withdrawn");
        assertEq(locker.filled(), 1 ether, "queue filled first");
        assertEq(locker.claimable(req), 1 ether);
        (uint256 head, uint256 amount) = _rung(_epoch(8));
        assertGt(head, 0, "the rest locked again four weeks out");
        assertEq(amount, 1 ether);
        assertEq(locker.locked(), 1 ether);
        assertGt(locker.owedTotal(btc), 0, "rebates above principal are income");
        _assertBacked();

        uint256 before = alice.balance;
        vm.prank(stranger);
        locker.claimRedeem(req);
        assertEq(alice.balance - before, 1 ether, "paid to its owner");
        assertEq(locker.claimRedeem(req), 0, "nothing twice");
        assertEq(locker.reserved(), 0);
        uint256[] memory ids = locker.requestsOf(alice);
        assertEq(ids.length, 1);
        assertEq(locker.requestCount(), 1);
        _assertBacked();
    }

    function test_pausedLadderPaysExitsAtOnce() public {
        _deposit(alice, 1 ether);
        locker.setPaused(true);
        for (uint256 k = 1; k <= 4; k++) {
            _nextWeek(k);
            locker.roll();
        }
        assertEq(locker.locked(), 0, "nothing locked again while paused");
        assertEq(locker.idle(), 1 ether);
        vm.prank(alice);
        uint256 req = locker.requestRedeem(0.4 ether);
        assertEq(locker.claimable(req), 0.4 ether, "filled from idle at once");
        locker.claimRedeem(req);
        assertEq(alice.balance, 0.4 ether);
        _assertBacked();
    }

    function test_rewardsFollowTransfers() public {
        _deposit(alice, 1 ether);
        _nextWeek(1);
        locker.roll();
        uint256 stream = locker.owedTotal(musd) - locker.earned(musd, treasury);
        vm.warp(vm.getBlockTimestamp() + 3.5 days);
        vm.prank(alice);
        locker.transfer(bob, 1 ether);
        vm.warp(vm.getBlockTimestamp() + 3.5 days);
        assertApproxEqAbs(locker.earned(musd, alice), stream / 2, 1e6, "half the week");
        assertApproxEqAbs(locker.earned(musd, bob), stream / 2, 1e6, "the other half");
    }

    // A stream nobody holds gives its part back, and the next harvest streams it again
    function test_unheldStreamReturnsToIncome() public {
        _deposit(alice, 1 ether);
        _nextWeek(1);
        locker.roll();
        uint256 owedBefore = locker.owedTotal(musd);
        vm.prank(alice);
        locker.requestRedeem(1 ether);
        vm.warp(vm.getBlockTimestamp() + 7 days);
        vm.prank(alice);
        locker.claim();
        _deposit(bob, 1 ether);
        uint256 fee = locker.earned(musd, treasury);
        assertApproxEqAbs(locker.owedTotal(musd), fee, 1e6, "only the fee is still owed");
        uint256 free = musd.balanceOf(address(locker)) - locker.owedTotal(musd);
        assertApproxEqAbs(free, owedBefore - fee, 1e6, "the stream is income again");
        locker.roll();
        vm.warp(vm.getBlockTimestamp() + 7 days);
        // This roll also claims the E1 fees, so bob gets at least the returned stream
        assertGe(locker.earned(musd, bob) + 1e6, free * 9500 / BPS, "streamed to bob");
    }

    function test_onlySelfTendsAndReleases() public {
        _deposit(alice, 1 ether);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.tend(0);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.release(1);
        vm.expectRevert(BtcLocker.NoRung.selector);
        locker.addBoostGauge(_epoch(3) / WEEK % 4, gaugeFactory);
    }

    // BTC sent to the locker is income for holders at the next roll
    function test_btcDonationIsIncome() public {
        _deposit(alice, 1 ether);
        vm.deal(stranger, 0.01 ether);
        vm.prank(stranger);
        (bool ok,) = address(locker).call{value: 0.01 ether}("");
        assertTrue(ok);
        locker.roll();
        assertEq(locker.owedTotal(btc), 0.01 ether, "streamed and credited");
        vm.warp(vm.getBlockTimestamp() + 7 days);
        vm.prank(alice);
        (uint256 paid,) = locker.claim();
        assertApproxEqAbs(paid, 0.0095 ether, 1e6, "less the treasury fee");
        _assertBacked();
    }

    /* fveMEZO */

    function test_mezoDepositOpensPermanentLock() public {
        _depositMezo(carol, 10e18);
        uint256 id = mezoLocker.veMezoId();
        assertGt(id, 0);
        IEarnVe.LockedBalance memory l = IEarnVe(lpVe).locked(id);
        assertTrue(l.isPermanent, "never ends");
        assertEq(uint256(int256(l.amount)), 10e18);
        assertEq(mezoLocker.balanceOf(carol), 10e18);
        _depositMezo(bob, 5e18);
        assertEq(mezoLocker.veMezoId(), id, "one lock");
        assertEq(uint256(int256(IEarnVe(lpVe).locked(id).amount)), 15e18);

        vm.prank(carol);
        vm.expectRevert(MezoLocker.TooSmall.selector);
        mezoLocker.deposit(0, carol);
        locker.setPaused(true);
        vm.prank(carol);
        vm.expectRevert(MezoLocker.Paused.selector);
        mezoLocker.deposit(1, carol);
    }

    function test_mezoLockDeposits() public {
        _mezo(erin, 30e18);
        vm.startPrank(erin);
        IERC20(lp).approve(lpVe, 30e18);
        uint256 plain = IEarnVe(lpVe).createLock(10e18, 52 weeks);
        uint256 perm = IEarnVe(lpVe).createLock(20e18, 52 weeks);
        IEarnVe(lpVe).lockPermanent(perm);
        IVeNft(lpVe).approve(address(mezoLocker), plain);
        IVeNft(lpVe).approve(address(mezoLocker), perm);
        vm.expectRevert(MezoLocker.NoLock.selector);
        mezoLocker.depositLock(plain, erin);
        vm.stopPrank();

        _depositMezo(carol, 1e18);
        uint256 lock = mezoLocker.veMezoId();
        vm.prank(erin);
        mezoLocker.depositLock(plain, erin);
        vm.prank(erin);
        vm.expectRevert(MezoLocker.Permanent.selector);
        mezoLocker.depositLock(perm, erin);
        vm.prank(erin);
        IVeNft(lpVe).unlockPermanent(perm);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(erin);
        mezoLocker.depositLock(perm, erin);
        assertEq(mezoLocker.balanceOf(erin), 30e18, "fveMEZO for both locks");
        assertEq(uint256(int256(IEarnVe(lpVe).locked(lock).amount)), 31e18);
        assertTrue(IEarnVe(lpVe).locked(lock).isPermanent);
        assertEq(IEarnVe(lpVe).ownerOf(plain), address(0));
        assertEq(IEarnVe(lpVe).ownerOf(perm), address(0));
    }

    function test_mezoLockVotedRefused() public {
        _deposit(alice, 1 ether);
        locker.addBoostGauge(_epoch(4) / WEEK % 4, gaugeFactory);
        (uint256 rung,) = _rung(_epoch(4));
        address g = IBoostVoter(lpBooster).boostableTokenIdToGauge(rung);
        _depositMezo(carol, 1e18);
        _mezo(erin, 5e18);
        vm.startPrank(erin);
        IERC20(lp).approve(lpVe, 5e18);
        uint256 id = IEarnVe(lpVe).createLock(5e18, 52 weeks);
        IBoostVoter(lpBooster).vote(id, _list(g), _one());
        IVeNft(lpVe).approve(address(mezoLocker), id);
        vm.expectRevert(MezoLocker.Voted.selector);
        mezoLocker.depositLock(id, erin);
        vm.stopPrank();
    }

    function test_boostLiftsEveryRungEvenly() public {
        _deposit(alice, 1 ether);
        vm.warp(_epoch(1) + 2 hours);
        _deposit(bob, 0.5 ether);
        (uint256 a,) = _rung(_epoch(4));
        (uint256 b,) = _rung(_epoch(5));
        assertGt(b, 0, "a second rung opened the next week");
        locker.addBoostGauge(_epoch(4) / WEEK % 4, gaugeFactory);
        locker.addBoostGauge(_epoch(5) / WEEK % 4, gaugeFactory);

        vm.expectRevert(MezoLocker.NoLock.selector);
        mezoLocker.boost();
        _depositMezo(carol, 1e18);
        // A large veMEZO lock voting nowhere keeps the boost under its 5x cap
        _mezo(erin, 100e18);
        vm.startPrank(erin);
        IERC20(lp).approve(lpVe, 100e18);
        IEarnVe(lpVe).createLock(100e18, 52 weeks);
        vm.stopPrank();
        uint256 before = voter.votes(a, savings);
        vm.prank(stranger);
        mezoLocker.boost();
        uint256 boostA = IBoostVoter(lpBooster).getBoost(a);
        uint256 boostB = IBoostVoter(lpBooster).getBoost(b);
        assertGt(boostA, 1e18, "boosted");
        assertLt(boostA, 5e18, "under the cap");
        assertApproxEqRel(boostA, boostB, 0.01e18, "same boost for both");
        assertGt(voter.votes(a, savings), before, "the Voter weight follows");
        assertEq(voter.votes(a, savings), ve.votingPowerOfNFT(a));

        vm.expectRevert();
        mezoLocker.boost();
    }

    // The epoch's one vote waits for every live rung's gauge, so an early call cannot skip a new rung
    function test_boostWaitsForGaugesAndTheRoll() public {
        _deposit(alice, 1 ether);
        locker.addBoostGauge(_epoch(4) / WEEK % 4, gaugeFactory);
        _depositMezo(carol, 1e18);

        vm.warp(_epoch(1) + 2 hours);
        _deposit(bob, 1 ether);
        (uint256 b,) = _rung(_epoch(5));
        vm.prank(stranger);
        vm.expectRevert(MezoLocker.NotReady.selector);
        mezoLocker.boost();
        locker.addBoostGauge(_epoch(5) / WEEK % 4, gaugeFactory);
        mezoLocker.boost();
        assertGt(IBoostVoter(lpBooster).getBoost(b), 1e18, "the new rung is boosted too");

        // Past the first rung's end, boost waits until the roll has released it
        _nextWeek(4);
        vm.expectRevert(MezoLocker.NotReady.selector);
        mezoLocker.boost();
        locker.roll();
        locker.addBoostGauge(_epoch(8) / WEEK % 4, gaugeFactory);
        mezoLocker.boost();
    }

    function test_boostWithoutRungs() public {
        _depositMezo(carol, 1e18);
        mezoLocker.boost();
        assertEq(IEarnVe(lpVe).voted(mezoLocker.veMezoId()), false, "nothing to vote for");
    }

    // fveMEZO is paid for the boost it delivers, a dust deposit that boosts nothing earns nothing
    function test_cutFollowsDeliveredBoost() public {
        _deposit(alice, 1 ether);
        _depositMezo(stranger, 1);
        assertEq(locker.boostShare(), 0, "no boost yet");
        _nextWeek(1);
        locker.roll();
        assertEq(locker.earned(musd, address(mezoLocker)), 0, "dust fveMEZO takes no cut");

        // A real veMEZO lock boosts the rung, its share of the weight caps the cut
        locker.addBoostGauge(_epoch(4) / WEEK % 4, gaugeFactory);
        _mezo(erin, 1000e18);
        vm.startPrank(erin);
        IERC20(lp).approve(lpVe, 1000e18);
        IEarnVe(lpVe).createLock(1000e18, 52 weeks);
        vm.stopPrank();
        _depositMezo(carol, 1e18);
        mezoLocker.boost();
        uint256 share = locker.boostShare();
        assertGt(share, 0, "the boost adds weight");
        assertLt(share, 1500, "a small boost, under the 15% cap");

        uint256 owed = locker.owedTotal(musd);
        uint256 credited = locker.earned(musd, address(mezoLocker));
        _nextWeek(2);
        share = locker.boostShare();
        locker.roll();
        uint256 income = locker.owedTotal(musd) - owed;
        assertGt(income, 0);
        assertEq(
            locker.earned(musd, address(mezoLocker)) - credited, income * share / BPS, "cut is the share"
        );
    }

    // A lock brought in before Mezo's weekly rebate update waits, so its rebate is never burned
    function test_depositLockWaitsForTheRebate() public {
        _deposit(alice, 1 ether);
        uint256 id = _veLock(erin, 0.5 ether, MAX_LOCK);
        vm.warp(_epoch(1) + 1 minutes);
        _mezoWeek(false);
        vm.warp(_epoch(1) + 2 hours);
        vm.prank(erin);
        vm.expectRevert(BtcLocker.RebatePending.selector);
        locker.depositLock(id, erin);

        _mezoRebates();
        uint256 rebate = distributor.claimable(id);
        assertGt(rebate, 0);
        vm.prank(erin);
        locker.depositLock(id, erin);
        assertEq(locker.balanceOf(erin), 0.5 ether + rebate, "the rebate is credited too");
        _assertBacked();
    }

    // A lock about to end joins the longest rung, so it votes at full weight like any new BTC
    function test_depositLockJoinsTheLongestRung() public {
        _deposit(alice, 1 ether);
        uint256 id = _veLock(erin, 0.4 ether, MAX_LOCK);
        _nextWeek(1);
        _deposit(bob, 0.1 ether);
        (uint256 head,) = _rung(_epoch(5));
        assertGt(head, 0);
        vm.prank(erin);
        locker.depositLock(id, erin);
        (, uint256 amount) = _rung(_epoch(5));
        assertGt(locker.balanceOf(erin), 0.4 ether, "its rebate came along");
        assertEq(amount, 0.1 ether + locker.balanceOf(erin), "merged four weeks out");
        assertEq(ve.locked(head).end, _epoch(5));
        _assertBacked();
    }

    // A stream nobody held goes back to income once, without a second fee
    function test_returnedStreamIsChargedOnce() public {
        _deposit(alice, 1 ether);
        _nextWeek(1);
        locker.roll();
        uint256 fee = locker.earned(musd, treasury);
        uint256 owed = locker.owedTotal(musd);
        vm.prank(alice);
        locker.requestRedeem(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _deposit(bob, 1 ether);
        assertGt(owed - locker.owedTotal(musd), 0, "a day of stream came back");
        locker.roll();
        assertEq(locker.earned(musd, treasury), fee, "no fee on it again");
    }

    // A bribe in a token the streams don't carry goes to the treasury instead of burning with the rung
    function test_otherBribeTokensAreSwept() public {
        _deposit(alice, 1 ether);
        vm.prank(team);
        IWhitelist(address(voter)).whitelistToken(savings, true);
        vm.startPrank(whale);
        musd.approve(savings, 100e18);
        ISavings(savings).deposit(100e18);
        IERC20(savings).approve(address(bribe), 100e18);
        bribe.notifyRewardAmount(savings, 100e18);
        vm.stopPrank();
        _nextWeek(1);
        locker.roll();
        uint256 held = IERC20(savings).balanceOf(address(locker));
        assertGt(held, 0, "claimed from the full bribe list");
        vm.prank(stranger);
        locker.sweep(IERC20(savings));
        assertEq(IERC20(savings).balanceOf(treasury), held);

        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.sweep(btc);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.sweep(musd);
        vm.expectRevert(BtcLocker.NotAllowed.selector);
        locker.sweep(IERC20(lp));
    }

    function test_endedVeMezoRefused() public {
        _depositMezo(carol, 1e18);
        _mezo(erin, 5e18);
        vm.startPrank(erin);
        IERC20(lp).approve(lpVe, 5e18);
        uint256 id = IEarnVe(lpVe).createLock(5e18, 1 weeks);
        IVeNft(lpVe).approve(address(mezoLocker), id);
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 2 weeks);
        vm.prank(erin);
        vm.expectRevert(MezoLocker.Ended.selector);
        mezoLocker.depositLock(id, erin);
    }

    // Income under a tenth of what a stream still owes joins it without moving its end
    function test_smallTopUpKeepsTheEnd() public {
        _deposit(alice, 1 ether);
        _nextWeek(1);
        locker.roll();
        (,, uint64 finish,) = locker.streams(musd);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(whale);
        musd.transfer(address(locker), 1);
        locker.roll();
        (,, uint64 after_,) = locker.streams(musd);
        assertEq(after_, finish, "one wei cannot stretch the payout");
    }

    // MEZO bribes on the gauge are claimed and go into the veMEZO lock
    function test_mezoBribesFeedTheLock() public {
        _deposit(alice, 1 ether);
        _depositMezo(carol, 1e18);
        vm.prank(team);
        IWhitelist(address(voter)).whitelistToken(lp, true);
        _mezo(stranger, 100e18);
        vm.startPrank(stranger);
        IERC20(lp).approve(address(bribe), 100e18);
        bribe.notifyRewardAmount(lp, 100e18);
        vm.stopPrank();

        _nextWeek(1);
        locker.roll();
        uint256 sent = IERC20(lp).balanceOf(address(mezoLocker));
        assertGt(sent, 0, "the rung's part of the bribe reached fveMEZO");
        mezoLocker.harvest();
        assertEq(IERC20(lp).balanceOf(address(mezoLocker)), 0);
        uint256 lock = mezoLocker.veMezoId();
        assertEq(uint256(int256(IEarnVe(lpVe).locked(lock).amount)), 1e18 + sent, "locked for good");
    }

    function test_harvestWithoutHolders() public {
        mezoLocker.harvest();
        assertEq(mezoLocker.owedTotal(musd), 0);
    }
}
