// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a beneficiary, and allocating payouts to depositors as the beneficiary returns funds.
 *
 * The primary purpose of this contract is financing a trusted beneficiary, with the expectation of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the beneficiary, and change the state of the contract to allow for payouts to occur.
 *
 * Payouts are two things:
 * 1. ERC20 tokens sent to the contract by the beneficiary as ROI
 * 2. Funding accounts withdrawing their balance of payout in tokens
 *
 * If the fund target is not met in the fund raise window, the raise fails, and all depositors can
 * withdraw their initial investment.
 */
contract ERC20CrowdFinancingV1 is Initializable {
    // Emitted when an address deposits funds to the contract
    event Deposit(address indexed account, uint256 numTokens);

    // Emitted when an account withdraws their initial allocation or payouts
    event Withdraw(address indexed account, uint256 numTokens);

    // Emitted when the entirety of deposits is transferred to the beneficiary
    event Transfer(address indexed account, uint256 numTokens);

    // Emitted when the targets are not met, and time has elapsed (calling processFunds)
    event Fail();

    // Emitted when eth is transferred to the contract, for depositers to withdraw their share
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

    address private _token;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will lock and funders will not be able to withdraw
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

    mapping(address => uint256) private _deposits;

    // If the campaign is successful, then we track withdraw
    mapping(address => uint256) private _withdraws;


    // Fee related items
    address private _feeCollector;
    uint256 private _feeUpfrontBips;
    uint256 private _feePayoutBips;
    uint256 private _feesAvailable;
    uint256 private _feesCollected;


    // This contract is intended for use with proxies, so we prevent
    // direct initialization. This contract will fail to function and any interaction
    // with the contract involving deposits, etc, will revert.
    constructor() {
        _disableInitializers();
    }

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
        require(startTimestamp < endTimestamp, "Start must precede end");
        require(endTimestamp > block.timestamp && (endTimestamp - startTimestamp) < 7776000, "Invalid end time");
        require(fundTargetMin > 0, "Min target must be >= 0");
        require(fundTargetMin <= fundTargetMax, "Min target must be <= Max");
        require(minDeposit <= maxDeposit, "Min deposit must be <= Max");
        require(minDeposit <= fundTargetMax, "Min deposit must be <= Target Max");


        _beneficiary = beneficiary;
        _fundTargetMin = fundTargetMin;
        _fundTargetMax = fundTargetMax;
        _minDeposit = minDeposit;
        _maxDeposit = maxDeposit;
        _startTimestamp = startTimestamp;
        _expirationTimestamp = endTimestamp;
        _token = tokenAddr;

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
     * Deposit tokens into the contract track the deposit for calculating payout.
     *
     * Emits a {Deposit} event if the target was not met
     *
     * Requirements:
     *
     * - `msg.value` must be >= minimum fund amount and <= maximum fund amount
     * - deposit total must not exceed max fund target
     * - state must equal FUNDING
     */
    function deposit() public {
        require(depositAllowed(), "Deposits are not allowed");

        address account = msg.sender;
        uint256 amount = IERC20(_token).allowance(account, address(this));
        uint256 total = _deposits[account] + amount;

        require(total >= _minDeposit, "Deposit amount is too low");
        require(total <= _maxDeposit, "Deposit amount is too high");

        _deposits[account] += amount;
        _depositTotal += amount;
        emit Deposit(account, amount);

        require(IERC20(_token).transferFrom(msg.sender, address(this), amount), "ERC20 transfer failed");
    }

    /**
     * @return true if deposits are allowed
     */
    function depositAllowed() public view returns (bool) {
        return _depositTotal < _fundTargetMax && _state == State.FUNDING && started() && !expired();
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
            if(feeAmount > 0) {
              emit Transfer(_feeCollector, feeAmount);
              require(IERC20(_token).transfer(_feeCollector, feeAmount), "ERC20 Fee transfer failed");
            }

            emit Transfer(_beneficiary, transferAmount);
            require(IERC20(_token).transfer(_beneficiary, transferAmount), "ERC20 transfer failed");
        } else {
            _state = State.FAILED;
            emit Fail();
        }
    }

    function allocateFeePayout() private {
      if(_feeCollector == address(0) || _feePayoutBips == 0) {
        return;
      }
      uint256 feeAllocation = (_depositTotal * _feePayoutBips) / (10_000);

      // TODO: There must be better math for getting this very close
      feeAllocation += (feeAllocation * _feePayoutBips) / (10_000);

      _deposits[_feeCollector] = feeAllocation;
      _depositTotal += feeAllocation;
    }

    function calculateUpfrontFee() private view returns (uint256) {
      if(_feeCollector == address(0) || _feeUpfrontBips == 0) {
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
     * @dev Alternative means of paying out via approve + transferFrom
     *
     * Emits a {Payout} event.
     */
    function payout() external {
        require(_state == State.FUNDED, "Cannot accept payment");
        uint256 amount = IERC20(_token).allowance(msg.sender, address(this));
        emit Payout(msg.sender, amount);
        require(IERC20(_token).transferFrom(msg.sender, address(this), amount), "ERC20 transfer failed");
    }

    /**
     * @return The total amount of tokens paid back by the beneficiary
     */
    function payoutTotal() public view returns (uint256) {
        if (state() != State.FUNDED) {
            return 0;
        }
        return tokenBalance() + _withdrawTotal;
    }

    /**
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
     * @return The payout balance for the given account
     */
    function payoutBalance(address account) public view returns (uint256) {
        // Multiply by 1e18 to maximize precision. Note, this can be slightly lossy
        uint256 depositPayoutTotal = (_deposits[account] * 1e18 * payoutTotal()) / (_depositTotal * 1e18);
        return depositPayoutTotal - withdrawsOf(account);
    }

    /**
     * Withdraw available funds to the sender, if withdraws are allowed, and
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
     * @dev withdraw the initial deposit for hte given account
     */
    function withdrawDeposit(address account) private {
        uint256 amount = _deposits[account];
        require(amount > 0, "No balance");
        _deposits[account] = 0;
        emit Withdraw(account, amount);
        require(IERC20(_token).transfer(msg.sender, amount), "ERC20 transfer failed");
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
        require(IERC20(_token).transfer(msg.sender, amount), "ERC20 transfer failed");
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
     * @return the address of the beneficiary
     */
    function tokenAddress() public view returns (address) {
        return _token;
    }

    /**
     * @return the address of the beneficiary
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
     * @return the maximum fund target for the round to be considered successful
     */
    function maximumFundTarget() public view returns (uint256) {
        return _fundTargetMax;
    }
}
