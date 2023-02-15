// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 *
 * @title Crowd Financing with Payback
 * @author Dan Simpson
 *
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a beneficiary, and allocating payouts to depositors as the beneficiary returns funds.
 *
 * The primary purpose of this contract is financing a trusted beneficiary with the possibility of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the beneficiary, minus optional fee, and change the state of the contract to allow for payouts to occur.
 *
 * If the fund target is not met in the fund raise window, the raise fails, and all depositors can
 * withdraw their initial investment.
 *
 * Timing and processing:
 * Processing can only occur after the fund raise window expires OR the fund target max is met.
 *
 * The minimum campaign duration is 30 minutes, and the max duration is 90 days. The window is reasonable
 * for many scenarios, and if more time is required, many campaigns can be created in sequence. Locking
 * funds beyond 90 days seems unecessary and risky.
 *
 * Deposits:
 * Accounts deposit tokens by first creating an allowance in the token contract, and then
 * calling the depositTokens function, which will transfer the tokens if all constraints
 * are satisfied.
 *
 * For ETH campaigns, a depositer calls depositEth with a given ETH value.
 *
 * Payouts:
 * The beneficiary makes payments by invoking the yieldTokens or yieldEth functions which works
 * similar to the deposit function.
 *
 * As the payout balance accrues, depositors can invoke the withdraw function to transfer their
 * payout balance.
 *
 * ERC20 Compliant
 *
 * All deposits are tracked and used to calculate ERC20 total supply. Depositors can transfer
 * their deposit balance to another account using ERC20 functionality. Transfers of deposit tokens will
 * also transfer future withdraw capability to the receiver. This allows for account transfer and
 * makes liquidity possible.
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
contract CrowdFinancingV1 is Initializable, ReentrancyGuardUpgradeable, IERC20 {
    // Guard to gate ERC20 specific functions
    modifier erc20Only() {
        require(_erc20, "erc20 only fn called");
        _;
    }

    // Guard to gate ETH specific functions
    modifier ethOnly() {
        require(!_erc20, "ETH only fn called");
        _;
    }

    // Guard to ensure yields are allowed
    modifier yieldGuard(uint256 amount) {
        require(_state == State.FUNDED, "Cannot accept payment");
        require(amount > 0, "Amount is 0");
        _;
    }

    // Guard to ensure deposits are allowed
    modifier depositGuard(uint256 amount) {
        require(depositAllowed(), "Deposits are not allowed");
        uint256 total = _deposits[msg.sender] + amount;
        require(total >= _minDeposit, "Deposit amount is too low");
        require(total <= _maxDeposit, "Deposit amount is too high");
        _;
    }

    // Max campaign duration: 90 Days
    uint256 private constant MAX_DURATION_SECONDS = 7776000;

    // Min campaign duration: 30 minutes
    uint256 private constant MIN_DURATION_SECONDS = 1800;

    // Allow a campaign to be deployed where the start time is up to one minute in the past
    uint256 private constant PAST_START_TOLERANCE_SECONDS = 60;

    // Maximum fee basis points
    uint16 private constant MAX_FEE_BIPS = 2500;

    // Maximum basis points
    uint16 private constant MAX_BIPS = 10_000;

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

    // ERC20 allowances
    mapping(address => mapping(address => uint256)) private _allowances;

    // Fee related items

    // The optional address of the fee collector
    address private _feeCollector;

    // The fee in basis points, transferred to the fee collector when
    // processing a successful raise
    uint16 private _feeUpfrontBips;

    // The fee in basis points, used to dilute the cap table when
    // processing a succesful raise
    uint16 private _feePayoutBips;

    // Track the number of tokens sent via makePayment
    uint256 private _payoutTotal;

    // Flag indicating the contract works with ERC20 tokens rather than eth
    bool private _erc20;

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
     * @param tokenAddr the address of the ERC20 token used for payments, or 0 address for native token (ETH)
     * @param feeCollectorAddr the address of the fee collector, or the 0 address if no fees are collected
     * @param feeUpfrontBips the upfront fee in basis points, calculated during processing
     * @param feePayoutBips the payout fee in basis points. Dilutes the cap table for fee collection
     */
    function initialize(
        address beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 startTimestamp,
        uint256 endTimestamp,
        address tokenAddr,
        address feeCollectorAddr,
        uint16 feeUpfrontBips,
        uint16 feePayoutBips
    ) external initializer {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(startTimestamp + PAST_START_TOLERANCE_SECONDS >= block.timestamp, "Invalid start time");
        require(startTimestamp + MIN_DURATION_SECONDS <= endTimestamp, "Invalid time range");
        require(
            endTimestamp > block.timestamp && (endTimestamp - startTimestamp) < MAX_DURATION_SECONDS, "Invalid end time"
        );
        require(fundTargetMin > 0, "Min target must be > 0");
        require(fundTargetMin <= fundTargetMax, "Min target must be <= Max");
        require(minDeposit > 0, "Min deposit must be > 0");
        require(minDeposit <= maxDeposit, "Min deposit must be <= Max");
        require(minDeposit <= fundTargetMax, "Min deposit must be <= Target Max");
        require(minDeposit < (fundTargetMax - fundTargetMin), "Min deposit must be < (fundTargetMax - fundTargetMin)");
        require(feeUpfrontBips <= MAX_FEE_BIPS, "Upfront fee too high");
        require(feePayoutBips <= MAX_FEE_BIPS, "Payout fee too high");

        if (feeCollectorAddr != address(0)) {
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
        _erc20 = tokenAddr != address(0);

        _feeCollector = feeCollectorAddr;
        _feeUpfrontBips = feeUpfrontBips;
        _feePayoutBips = feePayoutBips;

        _depositTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;

        __ReentrancyGuard_init();
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
    function depositTokens(uint256 amount) external erc20Only depositGuard(amount) nonReentrant {
        _addDeposit(msg.sender, _transferSafe(msg.sender, amount));
    }

    function depositEth() external payable ethOnly depositGuard(msg.value) {
        _addDeposit(msg.sender, msg.value);
    }

    function _addDeposit(address account, uint256 amount) private {
        _deposits[account] += amount;
        _depositTotal += amount;
        emit Deposit(account, amount);
    }

    /**
     * @return true if deposits are allowed
     */
    function depositAllowed() public view returns (bool) {
        return _state == State.FUNDING && !fundTargetMaxMet() && started() && !expired();
    }

    /**
     * @param account the address of a depositor
     *
     * @return the percentage of ownership represented as parts per million
     */
    function ownershipPPM(address account) external view returns (uint256) {
        return (_deposits[account] * 1_000_000) / _depositTotal;
    }

    /**
     * @param account the address of a depositor
     *
     * @return the total amount of deposits for a given account
     */
    function depositedAmount(address account) external view returns (uint256) {
        return _deposits[account];
    }

    /**
     * @return the total deposit amount for all accounts
     */
    function depositTotal() external view returns (uint256) {
        return _depositTotal;
    }

    ///////////////////////////////////////////
    // Phase 2: Transfer or Fail
    ///////////////////////////////////////////

    /**
     * @notice Transfer funds to the beneficiary and change the state
     *
     * Emits a {Transfer} event if the target was met and funds transferred
     * Emits a {Fail} event if the target was not met
     */
    function processFunds() external {
        require(_state == State.FUNDING, "Funds already processed");
        require(expired() || fundTargetMaxMet(), "More time/funds required");

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
                if (_erc20) {
                    require(_token.transfer(_feeCollector, feeAmount), "ERC20: Fee transfer failed");
                } else {
                    payable(_feeCollector).transfer(feeAmount);
                }
            }

            emit Transfer(_beneficiary, transferAmount);
            if (_erc20) {
                require(_token.transfer(_beneficiary, transferAmount), "ERC20: Transfer failed");
            } else {
                payable(_beneficiary).transfer(transferAmount);
            }
        } else {
            _state = State.FAILED;
            emit Fail();
        }
    }

    /**
     * @dev Dilutes shares by allocating units to the fee collector, allowing for
     * withdraws to occur as payouts progress
     */
    function allocateFeePayout() private returns (uint256) {
        if (_feeCollector == address(0) || _feePayoutBips == 0) {
            return 0;
        }
        uint256 feeAllocation = (_depositTotal * _feePayoutBips) / (MAX_BIPS);

        _deposits[_feeCollector] += feeAllocation;
        _depositTotal += feeAllocation;

        return feeAllocation;
    }

    /**
     * @dev Caclulates a fee to transfer to the fee collector upon processing
     */
    function calculateUpfrontFee() private view returns (uint256) {
        if (_feeCollector == address(0) || _feeUpfrontBips == 0) {
            return 0;
        }
        return (_depositTotal * _feeUpfrontBips) / (MAX_BIPS);
    }

    /**
     * @return true if the minimum fund target is met
     */
    function fundTargetMet() public view returns (bool) {
        return _depositTotal >= _fundTargetMin;
    }

    /**
     * @return true if the maxmimum fund target is met
     */
    function fundTargetMaxMet() public view returns (bool) {
        return _depositTotal >= _fundTargetMax;
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
    function yieldTokens(uint256 amount) external erc20Only yieldGuard(amount) nonReentrant {
        _addPayout(msg.sender, _transferSafe(msg.sender, amount));
    }

    /**
     * Yield ETH to depositors pro-rata
     */
    function yieldEth() external payable ethOnly yieldGuard(msg.value) nonReentrant {
        _addPayout(msg.sender, msg.value);
    }

    function _addPayout(address from, uint256 amount) private {
        emit Payout(from, amount);
        _payoutTotal += amount;
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
        return state() == State.FUNDED || state() == State.FAILED || (expired() && !fundTargetMet());
    }

    /**
     * @return The total amount of tokens paid back to a given depositor
     */
    function payoutsMadeTo(address account) private view returns (uint256) {
        if (_depositTotal == 0) {
            return 0;
        }
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
    function withdraw() external {
        require(withdrawAllowed(), "Withdraw not allowed");

        // Set the state to failed
        if (expired() && state() == State.FUNDING && !fundTargetMet()) {
            _state = State.FAILED;
            emit Fail();
        }

        address account = msg.sender;
        if (state() == State.FUNDED) {
            withdrawPayout(account);
        } else {
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

        if (_erc20) {
            require(_token.transfer(account, amount), "ERC20 transfer failed");
        } else {
            payable(account).transfer(amount);
        }
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

        if (_erc20) {
            require(_token.transfer(account, amount), "ERC20 transfer failed");
        } else {
            payable(account).transfer(amount);
        }
    }

    ///////////////////////////////////////////
    // Utility Functons
    ///////////////////////////////////////////

    /**
     * Token transfer function which leverages allowance. Additionally, it accounts
     * for tokens which take fees on transfer. Fetch the balance of this contract
     * before and after transfer, to determine the real amount of tokens transferred.
     *
     * Note this contract is not compatible with tokens that rebase
     *
     * @return the amount of tokens transferred after fees
     */
    function _transferSafe(address account, uint256 amount) private returns (uint256) {
        uint256 allowed = _token.allowance(msg.sender, address(this));
        require(amount <= allowed, "Amount exceeds token allowance");
        uint256 priorBalance = _token.balanceOf(address(this));
        require(_token.transferFrom(account, address(this), amount), "ERC20 transfer failed");
        uint256 postBalance = _token.balanceOf(address(this));
        return postBalance - priorBalance;
    }

    ///////////////////////////////////////////
    // IERC20 Implementation
    ///////////////////////////////////////////

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256) {
        return _depositTotal;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _deposits[account];
    }

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _deposits[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _deposits[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _deposits[to] += amount;
        }

        // Transfer partial withdraws to balance payouts
        if (_state == State.FUNDED) {
            uint256 fromWithdraws = _withdraws[from];
            uint256 withdrawAmount = ((fromBalance - amount) * fromWithdraws) / fromBalance;
            unchecked {
                _withdraws[from] = fromWithdraws - withdrawAmount;
                _withdraws[to] += withdrawAmount;
            }
        }

        emit Transfer(from, to, amount);
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    ///////////////////////////////////////////
    // Public/External Views
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
    function minimumDeposit() external view returns (uint256) {
        return _minDeposit;
    }

    /**
     * @return the maximum deposit in tokens
     */
    function maximumDeposit() external view returns (uint256) {
        return _maxDeposit;
    }

    /**
     * @return the unix timestamp in seconds when the funding phase starts
     */
    function startsAt() external view returns (uint256) {
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
    function expiresAt() external view returns (uint256) {
        return _expirationTimestamp;
    }

    /**
     * @return true if the funding phase expired
     */
    function expired() public view returns (bool) {
        return block.timestamp >= _expirationTimestamp;
    }

    /**
     * @return the address of the beneficiary
     */
    function beneficiaryAddress() external view returns (address) {
        return _beneficiary;
    }

    /**
     * @return true if the contract is ERC20 denominated
     */
    function erc20Denominated() public view returns (bool) {
        return _erc20;
    }

    /**
     * @return the address of the token
     */
    function tokenAddress() external view returns (address) {
        return address(_token);
    }

    /**
     * @return the current token balance of the contract
     */
    function tokenBalance() public view returns (uint256) {
        return _token.balanceOf(address(this));
    }

    /**
     * @return the minimum fund target for the round to be considered successful
     */
    function minimumFundTarget() external view returns (uint256) {
        return _fundTargetMin;
    }

    /**
     * @return the maximum fund target
     */
    function maximumFundTarget() external view returns (uint256) {
        return _fundTargetMax;
    }

    /**
     * @return the upfront fee BIPs
     */
    function upfrontFeeBips() external view returns (uint16) {
        return _feeUpfrontBips;
    }

    /**
     * @return the payout fee BIPs
     */
    function payoutFeeBips() external view returns (uint16) {
        return _feePayoutBips;
    }

    /**
     * @return the fee collector address
     */
    function feeCollector() external view returns (address) {
        return _feeCollector;
    }
}
