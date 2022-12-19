// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 *
 * @title Crowd Financing with Payback
 * @author Dan Simpson
 *
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a beneficiary, and allocating payouts to depositors as the beneficiary returns funds.
 *
 * The primary purpose of this contract is financing a trusted beneficiary with the expectation of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the beneficiary, minus optional fee, and change the state of the contract to allow for payouts to occur.
 *
 * If the fund target is not met in the fund raise window, the raise fails, and all depositors can
 * withdraw their initial investment.
 *
 * Deposits:
 * Accounts deposit tokens by first creating an allowance in the token contract, and then
 * calling the deposit function, which will transfer the entire allowance if all contraints
 * are satisfied.
 *
 * Payouts:
 * The beneficiary makes payments by invoking the makePayment
 * function which works similar to the deposit function.
 *
 * As the payout balance accrues, depositors can invoke the withdraw function to transfer their
 * payout balance.
 *
 * Fees:
 * The contract can be initialized with an optional fee collector address with options for two
 * kinds of fees, in basis points. A value of 250 would mean 2.5%.
 *
 * Type A Fee: Upon processing, a percentage of the total deposit amount is carved out and sent
 * to the fee collector. The remaining balance is sent to the beneficiary.
 * Type B Fee: Upon processing, the fee collector is added to the cap table as a depositor with a
 * value commensurate with the fee, and the total deposits is also increased by that amount.
 *
 */
contract ERC20CrowdFinancingV1 is Initializable {
    // Max campaign duration: 90 Days
    uint private constant MAX_DURATION_SECONDS = 7776000;

    // Min campaign duration: 30 minutes
    uint private constant MIN_DURATION_SECONDS = 1800;

    // Allow a campaign to be deployed where the start time is up to one minute in the past
    uint private constant PAST_START_TOLERANCE_SECONDS = 60;

    // Maximum fee basis points
    uint private constant MAX_FEE_BIPS = 2500;

    /// @notice Emitted when an account deposits funds to the contract
    event Deposit(address indexed account, uint256 numTokens);

    /// @notice Emitted when an account withdraws their initial deposit or payout balance
    event Withdraw(address indexed account, uint256 numTokens);

    /// @notice Emitted when the funds are transferred to the beneficiary and when
    /// fees are transferred to the fee collector, if specified
    event Transfer(address indexed account, uint256 numTokens);

    /// @notice Emitted on processing if time has elapsed and the target was not met
    event Fail();

    /// @notice Emitted when makePayment is invoked by the beneficiary
    event Payout(address indexed account, uint256 numTokens);

    enum State {
        FUNDING,
        FAILED,
        FUNDED
    }

    // The current state of the contract
    State private _state;

    // The address of the beneficiary
    address private _beneficiary;

    // The token used for payments
    IERC20 private _token;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will transfer funds upon processing
    uint256 private _fundTargetMin;

    // The maximum fund target. If a transfer from a funder causes totalFunds to exceed
    // this value, the transaction will revert.
    uint256 private _fundTargetMax;

    // The minimum tokens an account can deposit
    uint256 private _minDeposit;

    // The maximum tokens an account can deposit
    uint256 private _maxDeposit;

    // The starting timestamp for the fund
    uint256 private _startTimestamp;

    // The expiration timestamp for the fund
    uint256 private _expirationTimestamp;

    // The total amount deposited for all accounts
    uint256 private _depositTotal;

    // The total amount withdrawn for all accounts
    uint256 private _withdrawTotal;

    // The mapping from account to what that account has deposited
    mapping(address => uint256) private _deposits;

    // The mapping from account to what that account has withdrawn
    mapping(address => uint256) private _withdraws;

    // Fee related items

    // The optional address of the fee collector
    address private _feeCollector;

    // The fee in basis points, transferred to the fee collector when
    // processing a successful raise
    uint256 private _feeUpfrontBips;

    // The fee in basis points, used to dilute the cap table when
    // processing a succesful raise
    uint256 private _feePayoutBips;

    // Track the number of tokens sent via makePayment
    uint256 private _payoutTotal;

    /// @notice This contract is intended for use with proxies, so we prevent direct
    /// initialization. This contract will fail to function properly without a proxy
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize acts as the constructor, as this contract is intended to work with proxy contracts.
     *
     * @param beneficiary the address of the beneficiary, where funds are sent on success
     * @param fundTargetMin the minimum funding amount acceptible for successful financing
     * @param fundTargetMax the maximum funding amount accepted for the financing round
     * @param minDeposit the minimum deposit an account can make in one deposit
     * @param maxDeposit the maximum deposit an account can make in one or more deposits
     * @param startTimestamp the UNIX time in seconds denoting when deposits can start
     * @param endTimestamp the UNIX time in seconds denoting when deposits are no longer allowed
     * @param tokenAddr the address of the ERC20 token used for payments
     * @param feeCollector the address of the fee collector, or the 0 address if no fees are collected
     * @param feeUpfrontBips the upfront fee in basis points, calculated during processing
     * @param feePayoutBips the payout fee in basis points. Dilutes the cap table for fee collection
     */
    function initialize(
        address payable beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 startTimestamp,
        uint256 endTimestamp,
        address tokenAddr,
        address feeCollector,
        uint256 feeUpfrontBips,
        uint256 feePayoutBips
    ) public initializer {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(tokenAddr != address(0), "Invalid token address");
        require(startTimestamp + PAST_START_TOLERANCE_SECONDS >= block.timestamp, "Invalid start time");
        require(startTimestamp + MIN_DURATION_SECONDS <= endTimestamp, "Invalid time range");
        require(endTimestamp > block.timestamp && (endTimestamp - startTimestamp) < MAX_DURATION_SECONDS, "Invalid end time");
        require(fundTargetMin > 0, "Min target must be >= 0");
        require(fundTargetMin <= fundTargetMax, "Min target must be <= Max");
        require(minDeposit > 0, "Min deposit must be > 0");
        require(minDeposit <= maxDeposit, "Min deposit must be <= Max");
        require(minDeposit <= fundTargetMax, "Min deposit must be <= Target Max");
        require(minDeposit < (fundTargetMax - fundTargetMin), "Min deposit must be < (fundTargetMax - fundTargetMin)");
        require(feeUpfrontBips <= MAX_FEE_BIPS, "Upfront fee too high");
        require(feePayoutBips <= MAX_FEE_BIPS, "Payout fee too high");

        if (feeCollector != address(0)) {
            require(feeUpfrontBips > 0 || feePayoutBips > 0, "Fees required when fee collector is present");
        } else {
            require(feeUpfrontBips == 0 && feePayoutBips == 0, "Fees must be 0 when there is no fee collector");
        }

        _beneficiary = beneficiary;
        _fundTargetMin = fundTargetMin;
        _fundTargetMax = fundTargetMax;
        _minDeposit = minDeposit;
        _maxDeposit = maxDeposit;
        _startTimestamp = startTimestamp;
        _expirationTimestamp = endTimestamp;
        _token = IERC20(tokenAddr);

        _feeCollector = feeCollector;
        _feeUpfrontBips = feeUpfrontBips;
        _feePayoutBips = feePayoutBips;

        _depositTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;
    }

    ///////////////////////////////////////////
    // Phase 1: Deposits
    ///////////////////////////////////////////

    /**
     * @notice Deposit tokens into the contract and track amount for calculating payout.
     *
     * @param amount the amount of tokens to deposit
     *
     * Emits a {Deposit} event if the target was not met
     *
     * Requirements:
     *
     * - `amount` must be >= minimum deposit amount and <= maximum deposit amount
     * - deposit total must not exceed max fund target
     * - state must equal FUNDING
     * - `amount` must be <= token allowance for the contract
     */
    function deposit(uint256 amount) public {
        require(depositAllowed(), "Deposits are not allowed");

        address account = msg.sender;
        uint256 allowed = _token.allowance(account, address(this));

        require(amount <= allowed, "Deposit amount exeeds token allowance");

        uint256 total = _deposits[account] + amount;

        require(total >= _minDeposit, "Deposit amount is too low");
        require(total <= _maxDeposit, "Deposit amount is too high");

        _deposits[account] += amount;
        _depositTotal += amount;
        emit Deposit(account, amount);

        require(_token.transferFrom(msg.sender, address(this), amount), "ERC20 transfer failed");
    }

    /**
     * @return true if deposits are allowed
     */
    function depositAllowed() public view returns (bool) {
        return _depositTotal < _fundTargetMax && _state == State.FUNDING && started() && !expired();
    }

    /**
     * @param account the address of a depositor
     *
     * @return the percentage of ownership represented as parts per million
     */
    function ownershipPPM(address account) public view returns (uint256) {
        return (_deposits[account] * 1_000_000) / _depositTotal;
    }

    /**
     * @param account the address of a depositor
     *
     * @return the total amount of deposits for a given account
     */
    function depositAmount(address account) public view returns (uint256) {
        return _deposits[account];
    }

    /**
     * @return the total deposit amount for all accounts
     */
    function depositTotal() public view returns (uint256) {
        return _depositTotal;
    }

    ///////////////////////////////////////////
    // Phase 2: Transfer or Fail
    ///////////////////////////////////////////

    /**
     * @notice Transfer funds to the beneficiary and change the state
     *
     * Emits a {Transfer} event if the target was met and funds transfered
     * Emits a {Fail} event if the target was not met
     */
    function processFunds() public {
        require(_state == State.FUNDING, "Funds already processed");
        require(expired(), "Raise window is not expired");

        if (fundTargetMet()) {
            _state = State.FUNDED;

            uint256 feeAmount = calculateUpfrontFee();
            uint256 transferAmount = _depositTotal - feeAmount;

            // This can mutate _depositTotal, so that withdraws don't over withdraw
            allocateFeePayout();

            // If any upfront fee is present, pay that out to the collector now, so the funds
            // are not available for depositors to withdraw
            if (feeAmount > 0) {
                emit Transfer(_feeCollector, feeAmount);
                require(_token.transfer(_feeCollector, feeAmount), "ERC20 Fee transfer failed");
            }

            emit Transfer(_beneficiary, transferAmount);
            require(_token.transfer(_beneficiary, transferAmount), "ERC20 transfer failed");
        } else {
            _state = State.FAILED;
            emit Fail();
        }
    }

    /**
     * @dev Dilutes shares by allocating units to the fee collector, allowing for
     * withdraws to occur as payouts progress
     */
    function allocateFeePayout() private {
        if (_feeCollector == address(0) || _feePayoutBips == 0) {
            return;
        }
        uint256 feeAllocation = (_depositTotal * _feePayoutBips) / (10_000);

        _deposits[_feeCollector] += feeAllocation;
        _depositTotal += feeAllocation;
    }

    /**
     * @dev Caclulates a fee to transfer to the fee collector upon processing
     */
    function calculateUpfrontFee() private view returns (uint256) {
        if (_feeCollector == address(0) || _feeUpfrontBips == 0) {
            return 0;
        }
        return (_depositTotal * _feeUpfrontBips) / (10_000);
    }

    /**
     * @return true if the minimum fund target is met
     */
    function fundTargetMet() public view returns (bool) {
        return _depositTotal >= _fundTargetMin;
    }

    ///////////////////////////////////////////
    // Phase 3: Payouts / Refunds / Withdraws
    ///////////////////////////////////////////

    /**
     * @notice The only way to make payments to depositors
     *
     * @param amount the amount of tokens to payout
     *
     * Emits a {Payout} event.
     */
    function makePayment(uint256 amount) external {
        require(_state == State.FUNDED, "Cannot accept payment");
        require(amount > 0, "Amount is 0");

        uint256 allowed = _token.allowance(msg.sender, address(this));
        require(amount <= allowed, "Payment amount exeeds token allowance");

        emit Payout(msg.sender, amount);
        _payoutTotal += amount;

        require(_token.transferFrom(msg.sender, address(this), amount), "ERC20 transfer failed");
    }

    /**
     * @return The total amount of tokens paid back by the beneficiary
     */
    function payoutTotal() public view returns (uint256) {
        return _payoutTotal;
    }

    /**
     * @param account the address of a depositor
     *
     * @return The total tokens withdrawn for a given account
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
     * @return The total amount of tokens paid back to a given depositor
     */
    function payoutsMadeTo(address account) private view returns (uint256) {
        return (_deposits[account] * payoutTotal()) / _depositTotal;
    }

    /**
     * @param account the address of a depositor
     *
     * @return The payout balance for the given account
     */
    function payoutBalance(address account) public view returns (uint256) {
        return payoutsMadeTo(account) - withdrawsOf(account);
    }

    /**
     * @param account the address of a depositor
     *
     * @return The realized profit for the given account. returns 0 if no profit
     */
    function returnOnInvestment(address account) public view returns (uint256) {
        uint256 _payout = payoutsMadeTo(account);
        if (_payout <= _deposits[account]) {
            return 0;
        }
        return _payout - _deposits[account];
    }

    /**
     * @notice Withdraw available funds to the caller if withdraws are allowed and
     * the sender has a deposit balance (failed), or a payout balance (funded)
     *
     * Emits a {Withdraw} event.
     */
    function withdraw() public {
        require(withdrawAllowed(), "Withdraw not allowed");
        address account = msg.sender;
        if (state() == State.FUNDED) {
            withdrawPayout(account);
        } else if (state() == State.FAILED) {
            withdrawDeposit(account);
        }
    }

    /**
     * @dev withdraw the initial deposit for the given account
     */
    function withdrawDeposit(address account) private {
        uint256 amount = _deposits[account];
        require(amount > 0, "No balance");
        _deposits[account] = 0;
        emit Withdraw(account, amount);
        require(_token.transfer(msg.sender, amount), "ERC20 transfer failed");
    }

    /**
     * @dev withdraw the available payout balance for the given account
     */
    function withdrawPayout(address account) private {
        uint256 amount = payoutBalance(account);
        require(amount > 0, "No balance");
        _withdraws[account] += amount;
        _withdrawTotal += amount;
        emit Withdraw(account, amount);
        require(_token.transfer(msg.sender, amount), "ERC20 transfer failed");
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

    /**
     * @return the minimum deposit in tokens
     */
    function minimumDeposit() public view returns (uint256) {
        return _minDeposit;
    }

    /**
     * @return the maximum deposit in tokens
     */
    function maximumDeposit() public view returns (uint256) {
        return _maxDeposit;
    }

    /**
     * @return the unix timestamp in seconds when the funding phase starts
     */
    function startsAt() public view returns (uint256) {
        return _startTimestamp;
    }

    /**
     * @return true if the funding phase started
     */
    function started() public view returns (bool) {
        return block.timestamp >= _startTimestamp;
    }

    /**
     * @return the unix timestamp in seconds when the funding phase ends
     */
    function expiresAt() public view returns (uint256) {
        return _expirationTimestamp;
    }

    /**
     * @return true if the funding phase exipired
     */
    function expired() public view returns (bool) {
        return block.timestamp >= _expirationTimestamp;
    }

    /**
     * @return the address of the beneficiary
     */
    function beneficiaryAddress() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the address of the token
     */
    function tokenAddress() public view returns (address) {
        return address(_token);
    }

    /**
     * @return the current token balance of the contract
     */
    function tokenBalance() public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /**
     * @return the minimum fund target for the round to be considered successful
     */
    function minimumFundTarget() public view returns (uint256) {
        return _fundTargetMin;
    }

    /**
     * @return the maximum fund target
     */
    function maximumFundTarget() public view returns (uint256) {
        return _fundTargetMax;
    }
}
