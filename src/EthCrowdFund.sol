pragma solidity ^0.8.17;

contract EthCrowdFund {
    event Funded(address indexed payee, uint256 weiAmount);
    event Refunded(address indexed payee, uint256 weiAmount);

    event Locked(address indexed payee, uint256 weiAmount);
    event Resolve(address indexed payee, uint256 weiAmount);

    enum State {FUNDING, LOCKED, COMPLETE}

    // mapping(address => uint256) private funds;

    // address private facilitator;
    // address private beneficiary;

    // // Controllers can
    // address[] private controllers;

    // uint256 fundTarget;
    // uint256 totalFunds;

    // constructor(
    //     address[] facilitator,
    //     address[] controllers,
    //     uint256 fundTarget,
    //     uint256 minFund,
    //     uint256 maxFund
    // ) {
    //     facilitator = facilitator;
    //     _controllers = controllers;
    //     totalFunds = 0;
    // }

    // receive() external payable {
    //   // reject
    // }

    // withdraw() public {
    //   require();
    //   uint256 amount = funds[msg.sender];
    //   msg.sender.sendValue(amount);

    //     emit Withdrawn(payee, payment);

    //   // msg.sender
    //           uint256 amount = msg.value;
    //     _deposits[payee] += amount;
    //     emit Deposited(payee, amount);
    // }
}
