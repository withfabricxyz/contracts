// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 *
 * @title Crowd Financing with Optional Yield
 * @author Fabric Inc.
 *
 * A minimal contract for accumulating funds from many accounts, transferring the balance
 * to a recipient, and allocating payouts to depositors as the recipient returns funds.
 *
 * The primary purpose of this contract is financing a trusted recipient with the possibility of ROI.
 * If the fund target is met within the fund raising window, then processing the funds will transfer all
 * raised funds to the recipient, minus optional fee, and change the state of the contract to allow for payouts to occur.
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
 * calling the contributeERC20 function, which will transfer the tokens if all constraints
 * are satisfied.
 *
 * For ETH campaigns, a depositer calls contributeEth with a given ETH value.
 *
 * Payouts:
 * The recipient makes payments by invoking the yieldERC20 or yieldEth functions which works
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
 * to the fee collector. The remaining balance is sent to the recipient.
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
    modifier contributionGuard(uint256 amount) {
        require(isContributionAllowed(), "Deposits are not allowed");
        uint256 total = _contributions[msg.sender] + amount;
        require(total >= _minContribution, "Deposit amount is too low");
        require(total <= _maxContribution, "Deposit amount is too high");
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

    /// @notice Emitted when the funds are transferred to the recipient and when
    /// fees are transferred to the fee collector, if specified
    event TransferDeposits(address indexed account, uint256 numTokens);

    /// @notice Emitted on processing if time has elapsed and the target was not met
    event Fail();

    /// @notice Emitted when makePayment is invoked by the recipient
    event Payout(address indexed account, uint256 numTokens);

    enum State {
        FUNDING,
        FAILED,
        FUNDED
    }

    // The current state of the contract
    State private _state;

    // The address of the recipient
    address private _recipientAddress;

    // The token used for payments
    IERC20 private _token;

    // The minimum fund target to meet. Once funds meet or exceed this value the
    // contract will transfer funds upon processing
    uint256 private _goalMin;

    // The maximum fund target. If a transfer from a funder causes totalFunds to exceed
    // this value, the transaction will revert.
    uint256 private _goalMax;

    // The minimum tokens an account can deposit
    uint256 private _minContribution;

    // The maximum tokens an account can deposit
    uint256 private _maxContribution;

    // The starting timestamp for the fund
    uint256 private _startTimestamp;

    // The expiration timestamp for the fund
    uint256 private _endTimestamp;

    // The total amount deposited for all accounts
    uint256 private _contributionTotal;

    // The total amount withdrawn for all accounts
    uint256 private _withdrawTotal;

    // The mapping from account to what that account has deposited
    mapping(address => uint256) private _contributions;

    // The mapping from account to what that account has withdrawn
    mapping(address => uint256) private _withdraws;

    // ERC20 allowances
    mapping(address => mapping(address => uint256)) private _allowances;

    // Fee related items

    // The optional address of the fee collector
    address private _feeCollector;

    // The fee in basis points, transferred to the fee collector when
    // processing a successful raise
    uint16 private _feeTransferBips;

    // The fee in basis points, used to dilute the cap table when
    // processing a succesful raise
    uint16 private _feeYieldBips;

    // Track the number of tokens sent via makePayment
    uint256 private _yieldTotal;

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
     * @param recipient the address of the recipient, where funds are transferred when conditions are met
     * @param minGoal the minimum funding goal for the financing round
     * @param maxGoal the maximum funding goal for the financing round
     * @param minContribution the minimum contribution an account can make
     * @param maxContribution the maximum contribution an account can make
     * @param startTimestamp the UNIX time in seconds denoting when contributions can start
     * @param endTimestamp the UNIX time in seconds denoting when contributions are no longer allowed
     * @param erc20TokenAddr the address of the ERC20 token used for payments, or 0 address for native token (ETH)
     * @param feeRecipientAddr the address of the fee recipient, or the 0 address if no fees are collected
     * @param feeTransferBips the transfer fee in basis points, collected during the transfer call
     * @param feeYieldBips the yield fee in basis points. Dilutes the cap table for the fee recipient.
     */
    function initialize(
        address recipient,
        uint256 minGoal,
        uint256 maxGoal,
        uint256 minContribution,
        uint256 maxContribution,
        uint256 startTimestamp,
        uint256 endTimestamp,
        address erc20TokenAddr,
        address feeRecipientAddr,
        uint16 feeTransferBips,
        uint16 feeYieldBips
    ) external initializer {
        require(recipient != address(0), "Invalid recipient address");
        require(startTimestamp + PAST_START_TOLERANCE_SECONDS >= block.timestamp, "Invalid start time");
        require(startTimestamp + MIN_DURATION_SECONDS <= endTimestamp, "Invalid time range");
        require(
            endTimestamp > block.timestamp && (endTimestamp - startTimestamp) < MAX_DURATION_SECONDS, "Invalid end time"
        );
        require(minGoal > 0, "Min target must be > 0");
        require(minGoal <= maxGoal, "Min target must be <= Max");
        require(minContribution > 0, "Min deposit must be > 0");
        require(minContribution <= maxContribution, "Min deposit must be <= Max");
        require(minContribution <= maxGoal, "Min deposit must be <= Target Max");
        require(minContribution < (maxGoal - minGoal), "Min deposit must be < (maxGoal - minGoal)");
        require(feeTransferBips <= MAX_FEE_BIPS, "Upfront fee too high");
        require(feeYieldBips <= MAX_FEE_BIPS, "Payout fee too high");

        if (feeRecipientAddr != address(0)) {
            require(feeTransferBips > 0 || feeYieldBips > 0, "Fees required when fee collector is present");
        } else {
            require(feeTransferBips == 0 && feeYieldBips == 0, "Fees must be 0 when there is no fee collector");
        }

        _recipientAddress = recipient;
        _goalMin = minGoal;
        _goalMax = maxGoal;
        _minContribution = minContribution;
        _maxContribution = maxContribution;
        _startTimestamp = startTimestamp;
        _endTimestamp = endTimestamp;
        _token = IERC20(erc20TokenAddr);
        _erc20 = erc20TokenAddr != address(0);

        _feeCollector = feeRecipientAddr;
        _feeTransferBips = feeTransferBips;
        _feeYieldBips = feeYieldBips;

        _contributionTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;

        __ReentrancyGuard_init();
    }

    ///////////////////////////////////////////
    // Phase 1: Deposits
    ///////////////////////////////////////////

    /**
     * @notice Deposit ERC20 tokens into the contract
     *
     * @param amount the amount of ERC20 tokens to deposit
     *
     * Emits a {Deposit} event
     *
     * Requirements:
     *
     * - `amount` must be within range of min and max deposit for account
     * - `amount` must not cause max goal to be exceeded
     * - `amount` must be approved for transfer by the caller
     * - deposits must be allowed
     */
    function contributeERC20(uint256 amount) external erc20Only contributionGuard(amount) nonReentrant {
        _addContribution(msg.sender, _transferSafe(msg.sender, amount));
    }

    /**
     * @notice Deposit ETH into the contract
     *
     * Emits a {Deposit} event
     *
     * Requirements:
     *
     * - `msg.value` must be within range of min and max deposit for account
     * - `msg.value` must not cause max goal to be exceeded
     * - deposits must be allowed
     */
    function contributeEth() external payable ethOnly contributionGuard(msg.value) {
        _addContribution(msg.sender, msg.value);
    }

    /**
     * @notice Add a deposit to the account and update totals
     *
     * @param account the account to add the deposit to
     * @param amount the amount of the deposit
     *
     * Emits a {Deposit} event
     */
    function _addContribution(address account, uint256 amount) private {
        _contributions[account] += amount;
        _contributionTotal += amount;
        emit Deposit(account, amount);
    }

    /**
     * @return true if deposits are allowed
     */
    function isContributionAllowed() public view returns (bool) {
        return _state == State.FUNDING && !isGoalMaxMet() && isStarted() && !isEnded();
    }

    ///////////////////////////////////////////
    // Phase 2: Transfer or Fail
    ///////////////////////////////////////////

    /**
     * @notice Check if the goal was met and funds can be transferred
     */
    function isTransferAllowed() public view returns (bool) {
        return ((isEnded() && isGoalMinMet()) || isGoalMaxMet()) && _state == State.FUNDING;
    }

    /**
     * @notice Transfer funds to the recipient and change the state
     *
     * Emits a {Transfer} event if the target was met and funds transferred
     */
    function transferBalanceToRecipient() external {
        require(isTransferAllowed(), "Transfer not allowed");

        _state = State.FUNDED;

        uint256 feeAmount = calculateUpfrontFee();
        uint256 transferAmount = _contributionTotal - feeAmount;

        // This can mutate _contributionTotal, so that withdraws don't over withdraw
        allocateYieldFee();

        // If any upfront fee is present, pay that out to the collector now, so the funds
        // are not available for depositors to withdraw
        if (feeAmount > 0) {
            emit TransferDeposits(_feeCollector, feeAmount);
            if (_erc20) {
                require(_token.transfer(_feeCollector, feeAmount), "ERC20: Fee transfer failed");
            } else {
                // TODO: Call
                payable(_feeCollector).transfer(feeAmount);
            }
        }

        emit TransferDeposits(_recipientAddress, transferAmount);
        if (_erc20) {
            require(_token.transfer(_recipientAddress, transferAmount), "ERC20: Transfer failed");
        } else {
            // TODO: Call
            payable(_recipientAddress).transfer(transferAmount);
        }
    }

    /**
     * @dev Dilutes supply by allocating tokens to the fee collector, allowing for
     * withdraws of yield
     */
    function allocateYieldFee() private returns (uint256) {
        if (_feeCollector == address(0) || _feeYieldBips == 0) {
            return 0;
        }
        uint256 feeAllocation = (_contributionTotal * _feeYieldBips) / (MAX_BIPS);

        _contributions[_feeCollector] += feeAllocation;
        _contributionTotal += feeAllocation;

        return feeAllocation;
    }

    /**
     * @dev Caclulates a fee to transfer to the fee collector upon processing
     */
    function calculateUpfrontFee() private view returns (uint256) {
        if (_feeCollector == address(0) || _feeTransferBips == 0) {
            return 0;
        }
        return (_contributionTotal * _feeTransferBips) / (MAX_BIPS);
    }

    /**
     * @return true if the minimum goal was met
     */
    function isGoalMinMet() public view returns (bool) {
        return _contributionTotal >= _goalMin;
    }

    /**
     * @return true if the maximum goal was met
     */
    function isGoalMaxMet() public view returns (bool) {
        return _contributionTotal >= _goalMax;
    }

    ///////////////////////////////////////////
    // Phase 3: Yield / Refunds / Withdraws
    ///////////////////////////////////////////

    /**
     * @notice The only way to make payments to contributors
     *
     * @param amount the amount of tokens to payout
     *
     * Emits a {Payout} event.
     */
    function yieldERC20(uint256 amount) external erc20Only yieldGuard(amount) nonReentrant {
        _addPayout(msg.sender, _transferSafe(msg.sender, amount));
    }

    /**
     * Yield ETH to contributors pro-rata
     */
    function yieldEth() external payable ethOnly yieldGuard(msg.value) nonReentrant {
        _addPayout(msg.sender, msg.value);
    }

    function _addPayout(address from, uint256 amount) private {
        emit Payout(from, amount);
        _yieldTotal += amount;
    }

    /**
     * @return The total amount of tokens paid back by the recipient
     */
    function yieldTotal() public view returns (uint256) {
        return _yieldTotal;
    }

    /**
     * @param account the address of a contributor
     *
     * @return The total tokens withdrawn for a given account
     */
    function withdrawsOf(address account) public view returns (uint256) {
        return _withdraws[account];
    }

    /**
     * @return true if the contract allows withdraws
     */
    function isWithdrawAllowed() public view returns (bool) {
        return state() == State.FUNDED || state() == State.FAILED || (isEnded() && !isGoalMinMet());
    }

    /**
     * @return The total amount of tokens paid back to a given contributor
     */
    function payoutsMadeTo(address account) private view returns (uint256) {
        if (_contributionTotal == 0) {
            return 0;
        }
        return (_contributions[account] * yieldTotal()) / _contributionTotal;
    }

    /**
     * @param account the address of a contributor
     *
     * @return The withdrawable amount of tokens for a given account, attributable to yield
     */
    function yieldBalanceOf(address account) public view returns (uint256) {
        return payoutsMadeTo(account) - withdrawsOf(account);
    }

    /**
     * @param account the address of a contributor
     *
     * @return The total amount of tokens earned by the given account through yield
     */
    function yieldTotalOf(address account) public view returns (uint256) {
        uint256 _payout = payoutsMadeTo(account);
        if (_payout <= _contributions[account]) {
            return 0;
        }
        return _payout - _contributions[account];
    }

    /**
     * @notice Withdraw available funds to the caller if withdraws are allowed and
     * the caller has a contribution balance (failed), or a yield balance (funded)
     *
     * Emits a {Withdraw} event.
     */
    function withdraw() external {
        require(isWithdrawAllowed(), "Withdraw not allowed");

        // Set the state to failed
        if (isEnded() && _state == State.FUNDING && !isGoalMinMet()) {
            _state = State.FAILED;
            emit Fail();
        }

        address account = msg.sender;
        if (_state == State.FUNDED) {
            withdrawYieldBalance(account);
        } else {
            withdrawContribution(account);
        }
    }

    /**
     * @dev Withdraw the initial contribution for the given account
     */
    function withdrawContribution(address account) private {
        uint256 amount = _contributions[account];
        require(amount > 0, "No balance");
        _contributions[account] = 0;
        emit Withdraw(account, amount);

        if (_erc20) {
            require(_token.transfer(account, amount), "ERC20 transfer failed");
        } else {
            payable(account).transfer(amount);
        }
    }

    /**
     * @dev @ithdraw the available yield balance for the given account
     */
    function withdrawYieldBalance(address account) private {
        uint256 amount = yieldBalanceOf(account);
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
     * @return The amount of tokens transferred after fees
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
     * @dev Returns the amount of tokens in existence, minted via contribution.
     */
    function totalSupply() external view returns (uint256) {
        return _contributionTotal;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`, minted via contribution.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _contributions[account];
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

        uint256 fromBalance = _contributions[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _contributions[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _contributions[to] += amount;
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
     * @return The allowed contribution range for the given account
     */
    function contributionRangeFor(address account) external view returns (uint256, uint256) {
        uint256 balance = _contributions[account];
        if (balance >= _maxContribution) {
            return (0, 0);
        }
        int256 minContribution = int256(_minContribution) - int256(balance);
        if (minContribution <= 0) {
            minContribution = 1;
        }
        return (uint256(minContribution), _maxContribution - balance);
    }

    /**
     * @return The current state of the campaign
     */
    function state() public view returns (State) {
        return _state;
    }

    /**
     * @return The minimum allowed deposit of ERC20 tokens or WEI
     */
    function minAllowedContribution() external view returns (uint256) {
        return _minContribution;
    }

    /**
     * @return The maximum allowed deposit of ERC20 tokens or WEI
     */
    function maxAllowedContribution() external view returns (uint256) {
        return _maxContribution;
    }

    /**
     * @return The unix timestamp in seconds when the time window for deposits starts
     */
    function startsAt() external view returns (uint256) {
        return _startTimestamp;
    }

    /**
     * @return true if the time window for deposits has started
     */
    function isStarted() public view returns (bool) {
        return block.timestamp >= _startTimestamp;
    }

    /**
     * @return The unix timestamp in seconds when the deposit window ends
     */
    function endsAt() external view returns (uint256) {
        return _endTimestamp;
    }

    /**
     * @return The if the time window for deposits has closed
     */
    function isEnded() public view returns (bool) {
        return block.timestamp >= _endTimestamp;
    }

    /**
     * @return The address of the recipient
     */
    function recipientAddress() external view returns (address) {
        return _recipientAddress;
    }

    /**
     * @return true if the contract is ETH denominated
     */
    function isEthDenominated() public view returns (bool) {
        return !_erc20;
    }

    /**
     * @return The address of the ERC20 Token, or 0x0 if ETH
     */
    function erc20Address() external view returns (address) {
        return address(_token);
    }

    /**
     * @return The minimum goal amount as ERC20 tokens or WEI
     */
    function goalMin() external view returns (uint256) {
        return _goalMin;
    }

    /**
     * @return The maximum goal amount as ERC20 tokens or WEI
     */
    function goalMax() external view returns (uint256) {
        return _goalMax;
    }

    /**
     * @return The transfer fee as basis points
     */
    function transferFeeBips() external view returns (uint16) {
        return _feeTransferBips;
    }

    /**
     * @return The yield fee as basis points
     */
    function yieldFeeBips() external view returns (uint16) {
        return _feeYieldBips;
    }

    /**
     * @return The address where the fees are transferred to, or 0x0 if no fees are collected
     */
    function feeRecipientAddress() external view returns (address) {
        return _feeCollector;
    }
}
