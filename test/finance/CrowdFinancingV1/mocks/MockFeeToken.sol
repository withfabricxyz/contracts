// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Test token which charges 50% fee on transfer
contract MockFeeToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        super.transfer(to, amount >> 1);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        super.transferFrom(from, to, amount >> 1);
        return true;
    }
}
