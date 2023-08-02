// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/contracts/utils/StringsUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@forge/console2.sol";

contract SubscriptionNFTV1 is ERC721Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using StringsUpgradeable for uint256;

    /// @dev Maximum fee basis points (12.5%)
    uint16 private constant _MAX_FEE_BIPS = 1250;

    /// @dev Maximum basis points (100%)
    uint16 private constant _MAX_BIPS = 10000;

    /// @dev guard to ensure the purchase amount is valid
    modifier validAmount(uint256 amount) {
        require(amount >= _minimumPurchase, "Amount must be >= minimum purchase");
        _;
    }

    /// @dev Emitted when the owner withdraws available funds
    event CreatorWithdraw(address indexed account, uint256 tokensTransferred);

    /// @dev Emitted when a subscriber purchases time
    event SubscriptionFunded(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timePurchased, uint256 expiresAt
    );

    event SubscriptionGranted(address indexed account, uint256 tokenId, uint256 secondsGranted, uint256 expiresAt);

    /// @dev Emitted when the creator refunds a subscribers remaining time
    event SubscriptionRefund(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timeReclaimed
    );

    /// @dev Emitted when the fees are transferred to the recipient
    event FeeRecipientTransfer(address indexed from, address indexed to, uint256 tokensTransferred);

    /// @dev Emitted when the fee recipient is updated
    event FeeRecipientChange(address indexed from, address indexed to);

    /// @dev The subscription struct which holds the state of a subscription for an account
    struct Subscription {
        uint256 tokenId;
        uint256 secondsPurchased;
        uint256 secondsGranted;
        uint256 grantOffset;
        uint256 purchaseOffset;
    }

    /// @dev The metadata URI for the contract
    string private _contractURI;

    /// @dev The metadata URI for the tokens
    string private _tokenURI;

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

    /// @dev The fee basis points (10000 = 100%, max = _MAX_FEE_BIPS)
    uint16 private _feeBps;

    /// @dev The fee recipient address
    address private _feeRecipient;

    /// @dev Flag which determines if the contract is erc20 denominated
    bool private _erc20;

    /// @dev The subscription state for each account
    mapping(address => Subscription) private _subscriptions;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        mintFor(msg.sender, msg.value);
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory contractUri,
        string memory tokenUri,
        address owner,
        uint256 tokensPerSecond,
        uint256 minimumPurchase,
        uint16 feeBps,
        address feeRecipient,
        address erc20TokenAddr
    ) public initializer {
        require(owner != address(0), "Owner address cannot be 0x0");
        require(tokensPerSecond > 0, "Tokens per second must be > 0");
        require(feeBps <= _MAX_FEE_BIPS, "Fee bps too high");
        if (feeRecipient != address(0)) {
            require(feeBps > 0, "Fees required when fee recipient is present");
        }

        __ERC721_init(name, symbol);
        _transferOwnership(owner);
        __Pausable_init_unchained();
        _contractURI = contractUri;
        _tokenURI = tokenUri;
        _tokensPerSecond = tokensPerSecond;
        _minimumPurchase = minimumPurchase;
        _feeBps = feeBps;
        _feeRecipient = feeRecipient;
        _token = IERC20(erc20TokenAddr);
        _erc20 = erc20TokenAddr != address(0);
    }

    /////////////////////////
    // Subscriber Calls
    /////////////////////////

    function mint(uint256 numTokens) external payable {
        mintFor(msg.sender, numTokens);
    }

    function mintFor(address account, uint256 numTokens) public payable whenNotPaused validAmount(numTokens) {
        uint256 finalAmount = _transferIn(account, numTokens);
        _purchaseTime(account, finalAmount);
    }

    function _purchaseTime(address account, uint256 amount) internal {
        Subscription memory sub = _fetchSubscription(account);

        // Adjust offset to account for existing time
        if (block.timestamp > sub.purchaseOffset + sub.secondsPurchased) {
            // TODO: test revert on large purchase
            sub.purchaseOffset = block.timestamp - sub.secondsPurchased;
        }

        uint256 tv = timeValue(amount);
        sub.secondsPurchased += tv;
        _subscriptions[account] = sub;
        emit SubscriptionFunded(account, sub.tokenId, amount, tv, subscriptionExpiresAt(sub));
    }

    function _fetchSubscription(address account) internal returns (Subscription memory) {
        Subscription memory sub = _subscriptions[account];
        if (sub.tokenId == 0) {
            _tokenCounter += 1;
            sub = Subscription(_tokenCounter, 0, 0, block.timestamp, block.timestamp);
            _safeMint(account, sub.tokenId);
        }
        return sub;
    }

    // cancelSubscription
    // stopAutoRenew
    // startAutoRenew

    /////////////////////////
    // Creator Calls
    /////////////////////////

    function withdraw() external {
        withdrawTo(msg.sender);
    }

    function withdrawTo(address account) public onlyOwner {
        uint256 balance = creatorBalance();
        require(balance > 0, "No Balance");
        emit CreatorWithdraw(account, balance);
        _transferOutAndAllocateFees(account, balance);
    }

    // Refund all accounts
    function refund(address[] memory accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _refund(accounts[i]);
        }
    }

    function _refund(address account) internal {
        Subscription memory sub = _subscriptions[account];
        if (sub.secondsPurchased == 0) {
            return;
        }

        uint256 balance = refundableBalanceOf(account);
        sub.secondsPurchased -= balance;
        sub.secondsGranted = 0;
        _subscriptions[account] = sub;
        uint256 tokens = balance * _tokensPerSecond;
        emit SubscriptionRefund(account, sub.tokenId, tokens, balance);
        _transferOut(account, tokens);
    }

    function updateMetadata(string memory contractUri, string memory tokenUri) external onlyOwner {
        _contractURI = contractUri;
        _tokenURI = tokenUri;
    }

    // TODO: Account for mismatch between tokens in and time
    function grantTime(address[] memory accounts, uint256 secondsToAdd) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantTime(accounts[i], secondsToAdd);
        }
    }

    function _grantTime(address account, uint256 secondsGranted) internal {
        Subscription memory sub = _fetchSubscription(account);
        // Adjust offset to account for existing time
        if (block.timestamp > sub.grantOffset + sub.secondsGranted) {
            // TODO: test revert on large purchase
            sub.grantOffset = block.timestamp - sub.secondsGranted;
        }

        sub.secondsGranted += secondsGranted;
        _subscriptions[account] = sub;

        emit SubscriptionGranted(account, sub.tokenId, secondsGranted, subscriptionExpiresAt(sub));
    }

    function _grantTimeRemaining(Subscription memory sub) internal view returns (uint256) {
        uint256 expiresAt = sub.grantOffset + sub.secondsGranted;
        if (expiresAt <= block.timestamp) {
            return 0;
        }
        return expiresAt - block.timestamp;
    }

    function _purchaseTimeRemaining(Subscription memory sub) internal view returns (uint256) {
        uint256 expiresAt = sub.purchaseOffset + sub.secondsPurchased;
        if (expiresAt <= block.timestamp) {
            return 0;
        }
        return expiresAt - block.timestamp;
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

    function feeSchedule() external view returns (address feeRecipient, uint16 feeBps) {
        return (_feeRecipient, _feeBps);
    }

    function feeBalance() external view returns (uint256 balance) {
        return _feeBalance;
    }

    function transferFees() external {
        require(_feeBalance > 0, "No fees to collect");
        uint256 balance = _feeBalance;
        _feeBalance = 0;
        _transferOut(_feeRecipient, balance);
        emit FeeRecipientTransfer(msg.sender, _feeRecipient, balance);
    }

    function updateFeeRecipient(address newRecipient) external {
        require(msg.sender == _feeRecipient, "Unauthorized");
        _feeRecipient = newRecipient;
        emit FeeRecipientChange(msg.sender, newRecipient);
    }

    ////////////////////////
    // Transfers
    ////////////////////////

    function _transferIn(address from, uint256 amount) internal returns (uint256) {
        uint256 finalAmount = amount;
        if (_erc20) {
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
        if (_erc20) {
            uint256 balance = _token.balanceOf(address(this));
            require(balance >= amount, "Insufficient Balance");
            _token.safeTransfer(to, amount);
        } else {
            (bool sent,) = payable(to).call{value: amount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    function _allocateFees(uint256 amount) internal returns (uint256) {
        uint256 fee = (amount * _feeBps) / _MAX_BIPS;
        _feeBalance += fee;
        return amount - fee;
    }

    ////////////////////////
    // Informational
    ////////////////////////

    function timeValue(uint256 amount) public view returns (uint256 numSeconds) {
        return amount / _tokensPerSecond;
    }

    function creatorBalance() public view returns (uint256 balance) {
        return _tokensIn - _tokensOut;
    }

    function totalCreatorEarnings() public view returns (uint256 total) {
        return _tokensIn;
    }

    function subscriptionOf(address account)
        public
        view
        returns (uint256 tokenId, uint256 refundableAmount, uint256 expiresAt)
    {
        Subscription memory sub = _subscriptions[account];
        return (sub.tokenId, sub.secondsPurchased, subscriptionExpiresAt(sub));
    }

    function subscriptionExpiresAt(Subscription memory sub) public view returns (uint256 numSeconds) {
        return block.timestamp + _purchaseTimeRemaining(sub) + _grantTimeRemaining(sub);
    }

    function erc20Address() public view returns (address) {
        return address(_token);
    }

    function refundableBalanceOf(address account) public view returns (uint256 numSeconds) {
        Subscription memory sub = _subscriptions[account];
        return _purchaseTimeRemaining(sub);
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        bytes memory str = bytes(_tokenURI);
        uint256 len = str.length;
        if (len == 0) {
            return "";
        }

        if (str[len - 1] == "/") {
            return string(abi.encodePacked(_tokenURI, tokenId.toString()));
        }

        return _tokenURI;
    }

    //////////////////////
    // Overrides
    //////////////////////

    function balanceOf(address account) public view override returns (uint256 numSeconds) {
        Subscription memory sub = _subscriptions[account];
        return _purchaseTimeRemaining(sub) + _grantTimeRemaining(sub);
    }

    /**
     * An address may only have one subscription.
     */
    function _beforeTokenTransfer(address from, address to, uint256, /* tokenId */ uint256 /* batchSize */ )
        internal
        override
    {
        if (from == address(0)) {
            return;
        }

        require(_subscriptions[to].tokenId == 0, "Cannot transfer to existing subscribers");
        if (to != address(0)) {
            _subscriptions[to] = _subscriptions[from];
        }

        delete _subscriptions[from];
    }
}
