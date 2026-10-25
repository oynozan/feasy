// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SleeveBase as Base, IGaugeLike} from "./SleeveBase.sol";

interface IBoostViews {
    function ve() external view returns (address);
    function boostableVe() external view returns (address);
    function getBoost(uint256 id) external view returns (uint256);
}

// The local Mezo Earn stack reads the way veBTC, the Pools Voter and the sMUSD gauge do on testnet
contract WiringTest is Base {
    function test_wiringMirrorsTestnet() public view {
        assertEq(uint256(vm.load(address(ve), bytes32(uint256(82)))), MAX_LOCK, "maxLockTime slot");
        assertEq(ve.token(), BTC, "veBTC token");
        assertEq(ve.voter(), address(voter), "veBTC voter");
        assertEq(ve.distributor(), address(distributor), "veBTC distributor");
        assertEq(ve.booster(), booster, "veBTC booster");
        assertEq(ve.team(), team, "veBTC team");
        assertEq(voter.ve(), address(ve), "voter ve");
        assertEq(voter.governor(), team, "governor");
        assertEq(voter.emergencyCouncil(), team, "emergency council");
        assertEq(voter.splitter(), address(eco), "voter splitter");
        assertEq(voter.gauges(savings), gauge, "sMUSD gauge");
        assertTrue(voter.isAlive(gauge), "gauge alive");
        assertEq(voter.gaugeToFees(gauge), address(fees), "fees reward");
        assertEq(voter.gaugeToBribe(gauge), address(bribe), "bribe reward");
        assertTrue(fees.isReward(address(musd)), "fees pay MUSD");
        assertEq(IGaugeLike(gauge).stakingToken(), savings, "gauge stakes sMUSD");
        assertEq(IGaugeLike(gauge).feesVotingReward(), address(fees), "gauge fee sink");
        assertEq(IGaugeLike(gauge).totalSupply(), STAKED, "sMUSD staked");
        assertEq(distributor.depositor(), address(chainFee), "distributor depositor");
        assertEq(eco.needle(), 90, "pools voter share");
        assertEq(chainFee.activePeriod(), E0, "rebate period of E0");
        assertEq(eco.activePeriod(), E0, "emission period of E0");
        assertEq(IBoostViews(booster).boostableVe(), address(ve), "booster boosts veBTC");
        assertEq(IBoostViews(booster).ve(), veMezo, "booster votes with veMEZO");
        assertEq(IBoostViews(booster).getBoost(daveLock), 1e18, "no veMEZO votes, 1x boost");
        assertGt(fees.tokenRewardsPerEpoch(address(musd), E0), 0, "E0 fees posted by distribute");
        assertEq(voter.votes(daveLock, savings), 1 ether, "a permanent 1 BTC lock votes for sMUSD");
        assertTrue(sleeve.live(), "sleeve sees Mezo Earn as live");
        assertEq(address(sleeve.voter()), address(voter), "sleeve voter");
        assertEq(address(sleeve.ve()), address(ve), "sleeve veBTC");
        assertEq(sleeve.gauge(), gauge, "sleeve gauge");
        assertEq(address(sleeve.fees()), address(fees), "sleeve fees");
        assertEq(address(sleeve.bribe()), address(bribe), "sleeve bribe");
        assertEq(address(sleeve.distributor()), address(distributor), "sleeve distributor");
        assertEq(BTC.code.length > 0, true, "BTC stand-in in place");
        assertEq(MEZO.code.length, 0, "no MEZO stand-in");
    }
}
