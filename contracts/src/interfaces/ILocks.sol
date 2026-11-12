// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVeBTC, IVeMezo} from "./IMezo.sol";

// Mezo Earn's VotingEscrow lock record, the same layout for veBTC and veMEZO
struct LockedBalance {
    int128 amount;
    uint256 end;
    bool isPermanent;
    uint256 boost;
}

// The veBTC calls a locker makes beyond the vault's sleeve
interface IVeBTCLocks is IVeBTC {
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function unboostedVotingPowerOfNFT(uint256 tokenId) external view returns (uint256);
}

// The veMEZO calls a locker makes beyond the vault's booster
interface IVeMezoLocks is IVeMezo {
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function voted(uint256 tokenId) external view returns (bool);
    function distributor() external view returns (address);
}
