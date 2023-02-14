// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    bool private _transferReturn;

    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
        _transferReturn = true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        super.transfer(to, amount);
        return _transferReturn;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        super.transferFrom(from, to, amount);
        return _transferReturn;
    }

    function setTransferReturn(bool retVal) external {
        _transferReturn = retVal;
    }
}
