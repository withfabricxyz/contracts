// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 *
 * Each instance of a Crowdfinancing Contract represents a single campaign with a goal
 * of raising funds for a specific purpose. The contract is deployed by the creator through
 * the CrowdFinancingV1Factory contract. The creator specifies the recipient address, the
 * token to use for payments, the minimum and maximum funding goals, the minimum and maximum
 * contribution amounts, and the start and end times.
 *
 * The campaign is deemed successful if the minimum funding goal is met by the end time, or the
 * maximum funding goal is met before the end time.
 *
 * If the campaign is successful funds can be transferred to the recipient address. If the
 * campaign is not successful the funds can be withdrawn by the contributors.
 *
 * @title Crowd Financing with Optional Yield
 * @author Fabric Inc.
 *
 */
contract CrowdFinancingV1 is Initializable, ReentrancyGuardUpgradeable, IERC20 {
    /// @dev Guard to gate ERC20 specific functions
    modifier erc20Only() {
        require(_erc20, "erc20 only fn called");
        _;
    }

    /// @dev Guard to gate ETH specific functions
    modifier ethOnly() {
        require(!_erc20, "ETH only fn called");
        _;
    }

    /// @dev Guard to ensure yields are allowed
    modifier yieldGuard(uint256 amount) {
        require(_state == State.FUNDED, "Cannot accept payment");
        require(amount > 0, "Amount is 0");
        _;
    }

    /// @dev Guard to ensure contributions are allowed
    modifier contributionGuard(uint256 amount) {
        require(isContributionAllowed(), "Contributions are not allowed");
        uint256 total = _contributions[msg.sender] + amount;
        require(total >= _minContribution, "Contribution amount is too low");
        require(total <= _maxContribution, "Contribution amount is too high");
        require(_contributionTotal + amount <= _goalMax, "Contribution amount exceeds max goal");
        _;
    }

    /// @dev If transfer doesn't occur within the TRANSFER_WINDOW, the campaign can be unlocked
    /// and put into a failed state for withdraws. This is to prevent a campaign from being
    /// locked forever if the recipient addresses are compromised.
    uint256 private constant TRANSFER_WINDOW = 90 days;

    /// @dev Max campaign duration: 90 Days
    uint256 private constant MAX_DURATION_SECONDS = 90 days;

    /// @dev Min campaign duration: 30 minutes
    uint256 private constant MIN_DURATION_SECONDS = 30 minutes;

    /// @dev Allow a campaign to be deployed where the start time is up to one minute in the past
    uint256 private constant PAST_START_TOLERANCE_SECONDS = 60;

    /// @dev Maximum fee basis points (12.5%)
    uint16 private constant MAX_FEE_BIPS = 1250;

    /// @dev Maximum basis points
    uint16 private constant MAX_BIPS = 10_000;

    /// @dev Emitted when an account contributes funds to the contract
    event Contribution(address indexed account, uint256 numTokens);

    /// @dev Emitted when an account withdraws their initial contribution or yield balance
    event Withdraw(address indexed account, uint256 numTokens);

    /// @dev Emitted when the funds are transferred to the recipient and when
    /// fees are transferred to the fee collector, if specified
    event TransferContributions(address indexed account, uint256 numTokens);

    /// @dev Emitted when the campaign is marked as failed
    event Fail();

    /// @dev Emitted when yieldEth or yieldERC20 are called
    event Payout(address indexed account, uint256 numTokens);

    /// @dev A state enum to track the current state of the campaign
    enum State {
        FUNDING,
        FAILED,
        FUNDED
    }

    /// @dev The current state of the contract
    State private _state;

    /// @dev The address of the recipient in the event of a successful campaign
    address private _recipientAddress;

    /// @dev The token used for funding (optional)
    IERC20 private _token;

    /// @dev The minimum funding goal to meet for a successful campaign
    uint256 private _goalMin;

    /// @dev The maximum funding goal. If this goal is met, funds can be transferred early
    uint256 private _goalMax;

    /// @dev The minimum tokens an account can contribute
    uint256 private _minContribution;

    /// @dev The maximum tokens an account can contribute
    uint256 private _maxContribution;

    /// @dev The start timestamp for the campaign
    uint256 private _startTimestamp;

    /// @dev The end timestamp for the campaign
    uint256 private _endTimestamp;

    /// @dev The total amount contributed by all accounts
    uint256 private _contributionTotal;

    /// @dev The total amount withdrawn by all accounts
    uint256 private _withdrawTotal;

    /// @dev The mapping from account to balance (contributions or transfers)
    mapping(address => uint256) private _contributions;

    /// @dev The mapping from account to withdraws
    mapping(address => uint256) private _withdraws;

    /// @dev ERC20 allowances
    mapping(address => mapping(address => uint256)) private _allowances;

    // Fee related items

    /// @dev The optional address of the fee recipient
    address private _feeRecipient;

    /// @dev The transfer fee in basis points, sent to the fee recipient upon transfer
    uint16 private _feeTransferBips;

    /// @dev The yield fee in basis points, used to dilute the cap table upon transfer
    uint16 private _feeYieldBips;

    /// @dev Track the number of tokens sent via yield calls
    uint256 private _yieldTotal;

    /// @dev Flag indicating the contract works with ERC20 tokens rather than ETH
    bool private _erc20;

    /// @dev This contract is intended for use with proxies, so we prevent direct
    ///      initialization. This contract will fail to function properly without a proxy
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize acts as the constructor, as this contract is intended to work with proxy contracts.
     *
     * @param recipient the address of the recipient, where funds are transferred when conditions are met
     * @param minGoal the minimum funding goal for the financing round
     * @param maxGoal the maximum funding goal for the financing round
     * @param minContribution the minimum initial contribution an account can make
     * @param maxContribution the maximum contribution an account can make
     * @param startTimestamp the UNIX time in seconds denoting when contributions can start
     * @param endTimestamp the UNIX time in seconds denoting when contributions are no longer allowed
     * @param erc20TokenAddr the address of the ERC20 token used for funding, or the 0 address for native token (ETH)
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
        require(minGoal > 0, "Min goal must be > 0");
        require(minGoal <= maxGoal, "Min goal must be <= Max goal");
        require(minContribution > 0, "Min contribution must be > 0");
        require(minContribution <= maxContribution, "Min contribution must be <= Max contribution");
        require(
            minContribution < (maxGoal - minGoal) || minContribution == 1,
            "Min contribution must be < (maxGoal - minGoal) or 1"
        );
        require(feeTransferBips <= MAX_FEE_BIPS, "Transfer fee too high");
        require(feeYieldBips <= MAX_FEE_BIPS, "Yield fee too high");

        if (feeRecipientAddr != address(0)) {
            require(feeTransferBips > 0 || feeYieldBips > 0, "Fees required when fee recipient is present");
        } else {
            require(feeTransferBips == 0 && feeYieldBips == 0, "Fees must be 0 when there is no fee recipient");
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

        _feeRecipient = feeRecipientAddr;
        _feeTransferBips = feeTransferBips;
        _feeYieldBips = feeYieldBips;

        _contributionTotal = 0;
        _withdrawTotal = 0;
        _state = State.FUNDING;

        __ReentrancyGuard_init();
    }

    ///////////////////////////////////////////
    // Contributions
    ///////////////////////////////////////////

    /**
     * @notice Contribute ERC20 tokens into the contract
     *
     *         #### Events
     *         - Emits a {Contribution} event
     *         - Emits a {Transfer} event (ERC20)
     *
     *         #### Requirements
     *         - `amount` must be within range of min and max contribution for account
     *         - `amount` must not cause max goal to be exceeded
     *         - `amount` must be approved for transfer by the caller
     *         - contributions must be allowed
     *         - the contract must be configured to work with ERC20 tokens
     *
     * @param amount the amount of ERC20 tokens to contribute
     *
     */
    function contributeERC20(uint256 amount) external erc20Only nonReentrant {
        _addContribution(msg.sender, _transferSafe(msg.sender, amount));
    }

    /**
     * @notice Contribute ETH into the contract
     *
     *         #### Events
     *         - Emits a {Contribution} event
     *         - Emits a {Transfer} event (ERC20)
     *
     *         #### Requirements
     *         - `msg.value` must be within range of min and max contribution for account
     *         - `msg.value` must not cause max goal to be exceeded
     *         - contributions must be allowed
     *         - the contract must be configured to work with ETH
     */
    function contributeEth() external payable ethOnly {
        _addContribution(msg.sender, msg.value);
    }

    /**
     * @dev Add a contribution to the account and update totals
     *
     * @param account the account to add the contribution to
     * @param amount the amount of the contribution
     */
    function _addContribution(address account, uint256 amount) private contributionGuard(amount) {
        _contributions[account] += amount;
        _contributionTotal += amount;
        emit Contribution(account, amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @return true if contributions are allowed
     */
    function isContributionAllowed() public view returns (bool) {
        return _state == State.FUNDING && !isGoalMaxMet() && isStarted() && !isEnded();
    }

    ///////////////////////////////////////////
    // Transfer
    ///////////////////////////////////////////

    /**
     * @return true if the goal was met and funds can be transferred
     */
    function isTransferAllowed() public view returns (bool) {
        return ((isEnded() && isGoalMinMet()) || isGoalMaxMet()) && _state == State.FUNDING;
    }

    /**
     * @notice Transfer funds to the recipient and change the state
     *
     *         #### Events
     *         Emits a {TransferContributions} event if the target was met and funds transferred
     */
    function transferBalanceToRecipient() external {
        require(isTransferAllowed(), "Transfer not allowed");

        _state = State.FUNDED;

        uint256 feeAmount = _calculateTransferFee();
        uint256 transferAmount = _contributionTotal - feeAmount;

        // This can mutate _contributionTotal, so that withdraws don't over withdraw
        _allocateYieldFee();

        // If any transfer fee is present, pay that out to the fee recipient
        if (feeAmount > 0) {
            emit TransferContributions(_feeRecipient, feeAmount);
            if (_erc20) {
                SafeERC20.safeTransfer(_token, _feeRecipient, feeAmount);
            } else {
                (bool sent,) = payable(_feeRecipient).call{value: feeAmount}("");
                require(sent, "Failed to transfer Ether");
            }
        }

        emit TransferContributions(_recipientAddress, transferAmount);
        if (_erc20) {
            SafeERC20.safeTransfer(_token, _recipientAddress, transferAmount);
        } else {
            (bool sent,) = payable(_recipientAddress).call{value: transferAmount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    /**
     * @dev Dilutes supply by allocating tokens to the fee collector, allowing for
     *      withdraws of yield
     */
    function _allocateYieldFee() private returns (uint256) {
        if (_feeYieldBips == 0) {
            return 0;
        }
        uint256 feeAllocation = ((_contributionTotal * _feeYieldBips) / (MAX_BIPS - _feeYieldBips));

        _contributions[_feeRecipient] += feeAllocation;
        _contributionTotal += feeAllocation;

        return feeAllocation;
    }

    /**
     * @dev Calculates a fee to transfer to the fee collector
     */
    function _calculateTransferFee() private view returns (uint256) {
        if (_feeTransferBips == 0) {
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
    // Unlocking Funds After Failed Transfer
    ///////////////////////////////////////////

    /**
     * @notice In the event that a transfer fails due to recipient contract behavior, the campaign
     *         can be unlocked (marked as failed) to allow contributors to withdraw their funds. This can only
     *         occur if the state of the campaign is FUNDING and the transfer window
     *         has expired. Note: Recipient should invoke transferBalanceToRecipient immediately upon success
     *         to prevent this function from being callable. This is a safety mechanism to prevent
     *         permanent loss of funds.
     *
     *         #### Events
     *         - Emits {Fail} event
     */
    function unlockFailedFunds() external {
        require(isUnlockAllowed(), "Funds cannot be unlocked");
        _state = State.FAILED;
        emit Fail();
    }

    ///////////////////////////////////////////
    // Phase 3: Yield / Refunds / Withdraws
    ///////////////////////////////////////////

    /**
     * @notice Yield ERC20 tokens to all campaign token holders in proportion to their token balance
     *
     *         #### Requirements
     *         - `amount` must be greater than 0
     *         - `amount` must be approved for transfer for the contract
     *
     *         #### Events
     *         - Emits {Payout} event with amount = `amount`
     *
     * @param amount the amount of tokens to payout
     */
    function yieldERC20(uint256 amount) external erc20Only yieldGuard(amount) nonReentrant {
        _trackYield(msg.sender, _transferSafe(msg.sender, amount));
    }

    /**
     * @notice Yield ETH to all token holders in proportion to their balance
     *
     *         #### Requirements
     *         - `msg.value` must be greater than 0
     *
     *         #### Events
     *         - Emits {Payout} event with amount = `msg.value`
     */
    function yieldEth() external payable ethOnly yieldGuard(msg.value) nonReentrant {
        _trackYield(msg.sender, msg.value);
    }

    /**
     * @dev Emit a Payout event and increase yield total
     */
    function _trackYield(address from, uint256 amount) private {
        emit Payout(from, amount);
        _yieldTotal += amount;
    }

    /**
     * @return The total amount of tokens/wei paid back by the recipient
     */
    function yieldTotal() public view returns (uint256) {
        return _yieldTotal;
    }

    /**
     * @param account the address of a contributor or token holder
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
    function _payoutsMadeTo(address account) private view returns (uint256) {
        if (_contributionTotal == 0) {
            return 0;
        }
        return (_contributions[account] * yieldTotal()) / _contributionTotal;
    }

    /**
     * @param account the address of a token holder
     *
     * @return The withdrawable amount of tokens for a given account, attributable to yield
     */
    function yieldBalanceOf(address account) public view returns (uint256) {
        return _payoutsMadeTo(account) - withdrawsOf(account);
    }

    /**
     * @param account the address of a contributor
     *
     * @return The total amount of tokens earned by the given account through yield
     */
    function yieldTotalOf(address account) public view returns (uint256) {
        uint256 _payout = _payoutsMadeTo(account);
        if (_payout <= _contributions[account]) {
            return 0;
        }
        return _payout - _contributions[account];
    }

    /**
     * @notice Withdraw all available funds to the caller if withdraws are allowed and
     *         the caller has a contribution balance (campaign failed), or a yield balance (campaign succeeded)
     *
     *         #### Events
     *         - Emits a {Withdraw} event with amount = the amount withdrawn
     *         - Emits a {Transfer} event representing a token burn if the campaign failed
     */
    function withdraw() external {
        require(isWithdrawAllowed(), "Withdraw not allowed");

        // Set the state to failed
        if (_state == State.FUNDING) {
            _state = State.FAILED;
            emit Fail();
        }

        address account = msg.sender;
        if (_state == State.FUNDED) {
            _withdrawYieldBalance(account);
        } else {
            _withdrawContribution(account);
        }
    }

    /**
     * @dev Withdraw the initial contribution for the given account
     */
    function _withdrawContribution(address account) private {
        uint256 amount = _contributions[account];
        require(amount > 0, "No balance");
        _contributions[account] = 0;
        _contributionTotal -= amount;
        emit Withdraw(account, amount);
        emit Transfer(account, address(0), amount);

        if (_erc20) {
            SafeERC20.safeTransfer(_token, account, amount);
        } else {
            (bool sent,) = payable(account).call{value: amount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    /**
     * @dev Withdraw the available yield balance for the given account
     */
    function _withdrawYieldBalance(address account) private {
        uint256 amount = yieldBalanceOf(account);
        require(amount > 0, "No balance");
        _withdraws[account] += amount;
        _withdrawTotal += amount;
        emit Withdraw(account, amount);

        if (_erc20) {
            SafeERC20.safeTransfer(_token, account, amount);
        } else {
            (bool sent,) = payable(account).call{value: amount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    ///////////////////////////////////////////
    // Utility Functions
    ///////////////////////////////////////////

    /**
     * @dev Token transfer function which leverages allowance. Additionally, it accounts
     *      for tokens which take fees on transfer. Fetch the balance of this contract
     *      before and after transfer, to determine the real amount of tokens transferred.
     *
     * @notice this contract is not compatible with tokens that rebase
     *
     * @return The amount of tokens transferred after fees
     */
    function _transferSafe(address account, uint256 amount) private returns (uint256) {
        uint256 allowed = _token.allowance(msg.sender, address(this));
        require(amount <= allowed, "Amount exceeds token allowance");
        uint256 priorBalance = _token.balanceOf(address(this));
        SafeERC20.safeTransferFrom(_token, account, address(this), amount);
        uint256 postBalance = _token.balanceOf(address(this));
        return postBalance - priorBalance;
    }

    ///////////////////////////////////////////
    // IERC20 Implementation
    ///////////////////////////////////////////

    /**
     * @inheritdoc IERC20
     * @dev Contributions mint tokens and increase the total supply
     */
    function totalSupply() external view returns (uint256) {
        return _contributionTotal;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _contributions[account];
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * See ERC20._transfer
     * @dev The primary difference here is that we also need to adjust withdraws
     *      to prevent over-withdrawal of yield/contribution
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
            uint256 withdrawAmount = (amount * fromWithdraws) / fromBalance;
            unchecked {
                _withdraws[from] = fromWithdraws - withdrawAmount;
                _withdraws[to] += withdrawAmount;
            }
        }

        emit Transfer(from, to, amount);
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// See ERC20._spendAllowance
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /// See ERC20._approve
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /// See ERC20.increaseAllowance
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /// See ERC20.decreaseAllowance
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    ///////////////////////////////////////////
    // Public/External Views
    ///////////////////////////////////////////

    /**
     * @dev The values can be 0, indicating the account is not allowed to contribute.
     *      This method is helpful for preflight checks to ensure the amount is within the range.
     *
     * @return min The minimum contribution for the account
     * @return max The maximum contribution for the account
     */
    function contributionRangeFor(address account) external view returns (uint256 min, uint256 max) {
        uint256 balance = _contributions[account];
        if (balance >= _maxContribution || isGoalMaxMet()) {
            return (0, 0);
        }
        int256 minContribution = int256(_minContribution) - int256(balance);
        if (minContribution <= 0) {
            minContribution = 1;
        }
        uint256 remainingGoal = _goalMax - _contributionTotal;
        // If the remaining goal is less than the minimum contribution, then the account cannot contribute
        // This can lead to a gap between the supply and max goal, but existing contributors can top it off if
        // they are anxious to transfer early
        if (remainingGoal < uint256(minContribution)) {
            return (0, 0);
        }

        return (uint256(minContribution), Math.min(_maxContribution - balance, remainingGoal));
    }

    /**
     * @return The current state of the campaign
     */
    function state() public view returns (State) {
        return _state;
    }

    /**
     * @return The minimum allowed contribution of ERC20 tokens or WEI
     */
    function minAllowedContribution() external view returns (uint256) {
        return _minContribution;
    }

    /**
     * @return The maximum allowed contribution of ERC20 tokens or WEI
     */
    function maxAllowedContribution() external view returns (uint256) {
        return _maxContribution;
    }

    /**
     * @return The unix timestamp in seconds when the time window for contribution starts
     */
    function startsAt() external view returns (uint256) {
        return _startTimestamp;
    }

    /**
     * @return true if the time window for contribution has started
     */
    function isStarted() public view returns (bool) {
        return block.timestamp >= _startTimestamp;
    }

    /**
     * @return The unix timestamp in seconds when the contribution window ends
     */
    function endsAt() external view returns (uint256) {
        return _endTimestamp;
    }

    /**
     * @return true if the time window for contribution has closed
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
        return _feeRecipient;
    }

    /**
     * @return true if the funds are unlockable, which means the campaign succeeded, but transfer
     *              failed to occur within the transfer window
     */
    function isUnlockAllowed() public view returns (bool) {
        return _state == State.FUNDING && block.timestamp >= _endTimestamp + TRANSFER_WINDOW;
    }
}
