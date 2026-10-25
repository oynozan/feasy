// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

// Mezo's BTC precompile as mezod's precompile/erc20 runs it, balances are native and skip receive()
contract Btc {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function name() external pure returns (string memory) {
        return "BTC";
    }

    function symbol() external pure returns (string memory) {
        return "BTC";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address account) external view returns (uint256) {
        return account.balance;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "spender address cannot be empty");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (amount > 0 && msg.sender != from) {
            require(allowance[from][msg.sender] >= amount, "authorization does not exist");
            allowance[from][msg.sender] -= amount;
        }
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        if (amount > 0) {
            require(from.balance >= amount, "insufficient funds");
            vm.deal(from, from.balance - amount);
            vm.deal(to, to.balance + amount);
        }
        emit Transfer(from, to, amount);
    }
}
