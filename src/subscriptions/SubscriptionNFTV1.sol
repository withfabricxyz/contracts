// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@forge/console2.sol";

// TODO: Transfer Behavior
// TODO: Subscription detail (token id)

contract SubscriptionNFTV1 is ERC721Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Maximum fee basis points (12.5%)
    uint16 private constant MAX_FEE_BIPS = 1250;

    /// @dev Maximum basis points (100%)
    uint16 private constant MAX_BIPS = 10000;

    /// @dev guard to ensure the purchase amount is valid
    modifier validAmount(uint256 amount) {
        require(amount >= _minimumPurchase, "Amount must be >= minimum purchase");
        _;
    }

    /// @dev Emitted when the owner withdraws available funds
    event CreatorWithdraw(address indexed account, uint256 tokensTransferred);

    /// @dev Emitted when a subscriber purchases time
    event SubscriptionFunded(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timePurchased, uint64 expiresAt
    );

    /// @dev Emitted when the creator refunds a subscribers remaining time
    event SubscriptionRefund(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timeReclaimed
    );

    /// @dev The subscription struct which holds the state of a subscription for an account
    struct Subscription {
        uint256 tokenId;
        uint256 secondsPurchased;
        uint256 timeOffset; // expiresAt?
    }

    string private _baseUri;

    /// @dev The cost of one second in denominated token (wei or other base unit)
    uint256 private _tokensPerSecond;

    /// @dev The minimum number of tokens accepted for a time purchase
    uint256 private _minimumPurchase;

    /// @dev The token contract address, or 0x0 for native tokens
    IERC20 private _token;

    /// @dev The total number of tokens transferred in
    uint256 private _tokensIn;

    /// @dev The total number of tokens transferred out
    uint256 private _tokensOut;

    /// @dev The token counter for mint id generation
    uint256 private _tokenCounter;

    /// @dev The total number of tokens allocated for the fee collector
    uint256 private _feeBalance;

    /// @dev The fee basis points (10000 = 100%, max = MAX_FEE_BIPS)
    uint16 private _feeBps;

    /// @dev The fee recipient address
    address private _feeRecipient;

    /// @dev The subscription state for each account
    mapping(address => Subscription) private _subscriptions;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        purchaseFor(msg.sender, msg.value);
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory baseUri,
        address owner,
        uint256 tokensPerSecond,
        uint256 minimumPurchase,
        uint16 feeBps,
        address feeRecipient,
        address erc20TokenAddr
    ) public initializer {
        require(owner != address(0), "Owner address cannot be 0x0");
        require(tokensPerSecond > 0, "Tokens per second must be > 0");
        require(feeBps <= MAX_FEE_BIPS, "Fee bps too high");
        if (feeRecipient != address(0)) {
            require(feeBps > 0, "Fees required when fee recipient is present");
        }

        __ERC721_init(name, symbol);
        _transferOwnership(owner);
        __Pausable_init_unchained();
        _baseUri = baseUri;
        _tokensPerSecond = tokensPerSecond;
        _minimumPurchase = minimumPurchase;
        _feeBps = feeBps;
        _feeRecipient = feeRecipient;
        _token = IERC20(erc20TokenAddr);
    }

    /////////////////////////
    // Consumer Calls
    /////////////////////////

    function purchase(uint256 amount) external payable {
        purchaseFor(msg.sender, amount);
    }

    function purchaseFor(address account, uint256 amount) public payable whenNotPaused validAmount(amount) {
        uint256 finalAmount = _transferIn(account, amount);
        _purchase(account, finalAmount);
    }

    function _purchase(address account, uint256 amount) internal {
        Subscription memory sub = _subscriptions[account];

        uint256 tv = timeValue(amount);
        uint256 time = block.timestamp;

        if (sub.tokenId == 0) {
            sub = Subscription(_nextTokenId(), tv, time);
            _subscriptions[account] = sub;
            _safeMint(account, sub.tokenId);
        } else {
            if (time > sub.timeOffset + sub.secondsPurchased) {
                sub.timeOffset = time - sub.secondsPurchased;
            }
            sub.secondsPurchased += tv;
            _subscriptions[account] = sub;
        }
        emit SubscriptionFunded(account, sub.tokenId, amount, tv, uint64(sub.timeOffset + sub.secondsPurchased));
    }

    /////////////////////////
    // Creator Calls
    /////////////////////////

    // withdrawEarnings?
    function withdraw() external {
        transferEarnings(msg.sender);
    }

    function transferEarnings(address account) public onlyOwner {
        uint256 balance = creatorBalance();
        require(balance > 0, "No Balance");
        emit CreatorWithdraw(account, balance);
        _transferOutAndAllocateFees(account, balance);
    }

    function refund(address account) external onlyOwner {
        Subscription memory sub = _subscriptions[account];
        require(sub.secondsPurchased > 0, "NoActiveSubscription");
        uint256 balance = timeBalanceOf(account);
        sub.secondsPurchased -= balance;
        _subscriptions[account] = sub;
        uint256 tokens = balance * _tokensPerSecond;
        emit SubscriptionRefund(account, sub.tokenId, tokens, balance);
        _transferOut(account, tokens);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /////////////////////////
    // Fee Management
    /////////////////////////

    function feeBps() external view returns (uint16) {
        return _feeBps;
    }

    function feeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    function feeBalance() external view returns (uint256) {
        return _feeBalance;
    }

    function transferFees() external {
        uint256 balance = _feeBalance;
        require(balance > 0, "No fees to collect");
        _feeBalance = 0;
        // TODO: Emit
        _transferOut(_feeRecipient, balance);
    }

    ////////////////////////
    // Transfers
    ////////////////////////

    function _transferIn(address from, uint256 amount) internal returns (uint256) {
        uint256 finalAmount = amount;
        if (isERC20()) {
            require(msg.value == 0, "Native tokens not accepted for ERC20 subscriptions");
            uint256 balance = _token.balanceOf(from);
            uint256 allowance = _token.allowance(from, address(this));
            require(balance >= amount && allowance >= amount, "Insufficient Balance or Allowance");
            _token.safeTransferFrom(from, address(this), amount);
        } else {
            require(msg.value == amount, "Purchase amount must match value sent");
        }
        _tokensIn += finalAmount;
        return finalAmount;
    }

    function _transferOutAndAllocateFees(address to, uint256 amount) internal {
        uint256 finalAmount = _allocateFees(amount);
        _transferOut(to, finalAmount);
    }

    function _transferOut(address to, uint256 amount) internal {
        _tokensOut += amount;
        if (isERC20()) {
            uint256 balance = _token.balanceOf(address(this));
            require(balance >= amount, "Insufficient Balance");
            _token.safeTransfer(to, amount);
        } else {
            (bool sent,) = payable(to).call{value: amount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    function _allocateFees(uint256 amount) internal returns (uint256) {
        uint256 fee = (amount * _feeBps) / MAX_BIPS;
        _feeBalance += fee;
        return amount - fee;
    }

    ////////////////////////
    // Informational
    ////////////////////////

    function timeValue(uint256 amount) public view returns (uint256) {
        return amount / _tokensPerSecond;
    }

    function creatorBalance() public view returns (uint256) {
        return _tokensIn - _tokensOut;
    }

    function creatorEarnings() public view returns (uint256) {
        return _tokensIn;
    }

    // The number of seconds remaining on the subscription for an account
    function timeBalanceOf(address account) public view returns (uint256) {
        Subscription memory sub = _subscriptions[account];
        uint256 expiresAt = sub.timeOffset + sub.secondsPurchased;
        if (expiresAt <= block.timestamp) {
            return 0;
        }
        return expiresAt - block.timestamp;
    }

    function subscriptionOf(address account)
        public
        view
        returns (uint256 tokenId, uint256 secondsPurchased, uint256 timeOffset)
    {
        Subscription memory sub = _subscriptions[account];
        return (sub.tokenId, sub.secondsPurchased, sub.timeOffset);
    }

    function isERC20() public view returns (bool) {
        return address(_token) != address(0);
    }

    function erc20Address() public view returns (address) {
        return address(_token);
    }

    //////////////////////
    // Overrides
    //////////////////////

    // balanceOf is the number of tokens at time of call
    function balanceOf(address account) public view override returns (uint256) {
        return timeBalanceOf(account) * _tokensPerSecond;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    //////////////////////
    // Misc
    //////////////////////

    function _nextTokenId() internal returns (uint256) {
        _tokenCounter += 1;
        return _tokenCounter;
    }
}
