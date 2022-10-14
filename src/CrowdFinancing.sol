pragma solidity ^0.8.17;

contract CrowdFinancing {

    event Deposited(address indexed payee, uint256 weiAmount);
    event Withdrawal(address indexed payee, uint256 weiAmount);
    event Transfer(address indexed payee, uint256 weiAmount);
    event TargetMet(address indexed payee, uint256 weiAmount);

    enum State {
      FUNDING,
      FAILED,
      FUNDED
    }

    // Terms
    // Deposit -> Person funds the campaign
    // Withdraw -> Depositor withdraws their balance (failed, or drip)
    // Transfer -> contract to beneficiary


    // The current state of the raise
    State private _state;

    // The address of the beneficiary
    address payable private immutable _beneficiary;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will lock and funders will not be able to withdrawal
    uint256 private _fundTargetMin;

    // The maximum fund target. If a transfer from a funder causes totalFunds to exeed
    // this value, the transaction will revert.
    uint256 private _fundTargetMax;

    // The minimum eth a funder can send
    uint256 private _fundAmountMin;

    // The maximum eth a funder can send
    uint256 private _fundAmountMax;

    // The total amount raised
    uint256 private _amountRaised;

    // The total amount returned
    uint256 private _amountReturned;

    mapping(address => uint256) private _deposits;

    // If the campaign is successful, then we track withdraw
    mapping(address => uint256) private _withdrawals;

    constructor(
        address payable beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 fundAmountMin,
        uint256 fundAmountMax
    ) {
      require(beneficiary != address(0), "Beneficiary is the zero address");
        _beneficiary = beneficiary;
        _fundTargetMin = fundTargetMin;
        _fundTargetMax = fundTargetMax;
        _fundAmountMin = fundAmountMin;
        _fundAmountMax = fundAmountMax;
        _amountRaised = 0;
        _state = State.FUNDING;
    }

    function state() public view returns (State) {
      return _state;
    }

    function amountRaised() public view returns (uint256) {
      return _amountRaised;
    }

    function amountFunded(address depositor) public view returns (uint256) {
      return _deposits[depositor];
    }

    function deposit() public payable {
        require(_amountRaised <= _fundTargetMax, "Deposit limit reached");
        require(msg.value > 0, "Deposit requires funds");

        uint256 amount = msg.value;
        address sender = msg.sender;
        uint256 total  = _deposits[sender] + amount;

        require(total >= _fundAmountMin, "Deposit amount is too low");
        require(total <= _fundAmountMax, "Deposit amount is too high");

        _deposits[sender] += amount;
        _amountRaised += amount;

        emit Deposited(sender, amount);
    }

    function depositsOf(address payee) public view returns (uint256) {
      return _deposits[payee];
    }

    function fundTargetMet() public view returns (bool) {
      return _amountRaised >= _fundTargetMin;
    }

    function withdrawalAllowed() public view returns (bool) {
      return state() == State.FUNDED || state() == State.FAILED;
    }

}
