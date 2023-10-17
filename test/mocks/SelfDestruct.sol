// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract SelfDestruct {
    function destroy(address recipient) public payable {
        selfdestruct(payable(recipient));
    }
}
