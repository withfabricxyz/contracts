// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

library SubLib {
    struct InitParams {
        string name;
        string symbol;
        string contractUri;
        string tokenUri;
        address owner;
        uint256 tokensPerSecond;
        uint256 minimumPurchaseSeconds;
        uint16 rewardBps;
        uint16 feeBps;
        address feeRecipient;
        address erc20TokenAddr;
    }
}
