// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a beneficiary, and allocating payouts to depositors as the beneficiary returns funds.
 *
 * The primary purpose of this contract is financing a trusted beneficiary, with the expectation of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the beneficiary, and change the state of the contract to allow for payouts to occur.
 *
 * Payouts are two things:
 * 1. Eth sent to the contract by the beneficiary as ROI
 * 2. Funding accounts withdrawing their balance of payout
 *
 * If the fund target is not met in the fund raise window, the raise fails, and all depositors can
 * withdraw their initial investment.
 */
contract CrowdFinancingV1 is ReentrancyGuard {
    // Emitted when an address deposits funds to the contract
    event Deposit(address indexed account, uint256 weiAmount);

    // Emitted when an account withdraws their initial allocation or payouts
    event Withdraw(address indexed account, uint256 weiAmount);

    // Emitted when the entirety of deposits is transferred to the beneficiary
    event Transfer(address indexed account, uint256 weiAmount);

    // Emitted when the targets are not met, and time has elapsed (calling processFunds)
    event Fail();

    // Emitted when eth is transferred to the contract, for depositers to withdraw their share
    event Payout(address indexed account, uint256 weiAmount);

    enum State {
        FUNDING,
        FAILED,
        FUNDED
    }

    // The current state of the contract
    State private _state;

    // The address of the beneficiary
    address payable private immutable _beneficiary;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will lock and funders will not be able to withdrawal
    uint256 private _fundTargetMin;

    // The maximum fund target. If a transfer from a funder causes totalFunds to exeed
    // this value, the transaction will revert.
    uint256 private _fundTargetMax;

    // The minimum wei an account can deposit
    uint256 private _fundAmountMin;

    // The maximum wei an account can deposit
    uint256 private _fundAmountMax;

    // The expiration timestamp for the fund
    uint256 private _expirationTimestamp;

    // The total amount deposited for all accounts
    uint256 private _depositTotal;

    // The total amount withdrawn for all accounts
    uint256 private _withdrawTotal;

    mapping(address => uint256) private _deposits;

    // If the campaign is successful, then we track withdraw
    mapping(address => uint256) private _withdraws;

    constructor(
        address payable beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 fundAmountMin,
        uint256 fundAmountMax,
        uint256 expirationTimestamp
    ) {
        require(beneficiary != address(0), "Beneficiary is the zero address");
        require(
            expirationTimestamp > block.timestamp && expirationTimestamp <= block.timestamp + 7776000,
            "Invalid expiration timestamp"
        );
        require(fundTargetMin < fundTargetMax, "Invalid fund targets");
        require(fundAmountMin < fundAmountMax, "Invalid fund amounts");
        require(fundAmountMin < fundTargetMax, "Invalid fund/target amounts");

        _beneficiary = beneficiary;
        _fundTargetMin = fundTargetMin;
        _fundTargetMax = fundTargetMax;
        _fundAmountMin = fundAmountMin;
        _fundAmountMax = fundAmountMax;
        _expirationTimestamp = block.timestamp + expirationTimestamp;

        _depositTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;
    }

    ///////////////////////////////////////////
    // Phase 1: Deposits
    ///////////////////////////////////////////

    /**
     * Deposit eth into the contract track the deposit for calculating payout.
     *
     * Emits a {Deposit} event if the target was not met
     *
     * Requirements:
     *
     * - `msg.value` must be >= minimum fund amount and <= maximum fund amount
     * - deposit total must not exeed max fund target
     * - state must equal FUNDING
     */
    function deposit() public payable {
        require(depositAllowed(), "Deposits are not allowed");

        uint256 amount = msg.value;
        address account = msg.sender;
        uint256 total = _deposits[account] + amount;

        require(total >= _fundAmountMin, "Deposit amount is too low");
        require(total <= _fundAmountMax, "Deposit amount is too high");

        _deposits[account] += amount;
        _depositTotal += amount;

        emit Deposit(account, amount);
    }

    /**
     * @return true if deposits are allowed
     */
    function depositAllowed() public view returns (bool) {
        return _depositTotal <= _fundTargetMax && _state == State.FUNDING;
    }

    /**
     * @return the total amount of deposits for a given account
     */
    function depositAmount(address account) public view returns (uint256) {
        return _deposits[account];
    }

    /**
     * @return the total amount of deposits for all accounts
     */
    function depositTotal() public view returns (uint256) {
        return _depositTotal;
    }

    ///////////////////////////////////////////
    // Phase 2: Transfer or Fail
    ///////////////////////////////////////////

    /*
    * Transfer funds to the beneficiary and change the state
    *
    * Emits a {Transfer} event if the target was met and funds transfered
    * Emits a {Fail} event if the target was not met
    */
    function processFunds() public {
        require(_state == State.FUNDING, "Raise isn't funded");
        require(expired(), "Raise window is not expired");

        if (fundTargetMet()) {
            _beneficiary.transfer(_depositTotal);
            _state = State.FUNDED;
            emit Transfer(_beneficiary, _depositTotal);
        } else {
            _state = State.FAILED;
            emit Fail();
        }
    }

    function expiresAt() public view returns (uint256) {
        return _expirationTimestamp;
    }

    function expired() public view returns (bool) {
        return block.timestamp >= _expirationTimestamp;
    }

    function fundTargetMet() public view returns (bool) {
        return _depositTotal >= _fundTargetMin;
    }

    ///////////////////////////////////////////
    // Phase 3: Payouts / Refunds / Withdraws
    ///////////////////////////////////////////

    /**
     * @dev Only allow transfers once funded
     *
     * Emits a {Payout} event.
     */
    receive() external payable {
        require(_state == State.FUNDED, "Cannot accept payment");
        emit Payout(msg.sender, msg.value);
    }

    /**
     * @return The total amount of wei paid back by the beneficiary
     */
    function payoutTotal() public view returns (uint256) {
        return address(this).balance + _withdrawTotal;
    }

    /**
     * @return The total wei withdrawn for a given account
     */
    function withdrawsOf(address account) public view returns (uint256) {
        return _withdraws[account];
    }

    /**
     * @return true if the contract allows withdraws
     */
    function withdrawAllowed() public view returns (bool) {
        return state() == State.FUNDED || state() == State.FAILED;
    }

    /**
     * @return The payout balance for the given account
     */
    function payoutBalance(address account) public view returns (uint256) {
        uint256 accountPayout = ((_deposits[account] * 1e18) / _depositTotal) * (payoutTotal() / 1e18);
        return accountPayout - withdrawsOf(account);
    }

    /**
     * Withdraw available funds to the sender, if withdraws are allowed, and
     * the sender has a deposit balance (failed), or a payout balance (funded)
     *
     * Emits a {Withdraw} event.
     */
    function withdraw() public nonReentrant {
        require(withdrawAllowed(), "Withdraw not allowed");
        address account = msg.sender;
        if (state() == State.FUNDED) {
            withdrawPayout(account);
        } else if (state() == State.FAILED) {
            withdrawDeposit(account);
        }
    }

    /**
     * @dev withdraw the initial deposit for hte given account
     */
    function withdrawDeposit(address account) private {
        uint256 amount = _deposits[account];
        require(amount > 0, "No balance");
        payable(account).transfer(amount);
        _deposits[account] = 0;
        emit Withdraw(account, amount);
    }

    /**
     * @dev withdraw the available payout balance for the given account
     */
    function withdrawPayout(address account) private {
        uint256 amount = payoutBalance(account);
        require(amount > 0, "No balance");
        payable(account).transfer(amount);
        _withdraws[account] += amount;
        _withdrawTotal += amount;
        emit Withdraw(account, amount);
    }

    ///////////////////////////////////////////
    // Utility Functons
    ///////////////////////////////////////////

    /**
     * @return The current state of financing
     */
    function state() public view returns (State) {
        return _state;
    }
}
