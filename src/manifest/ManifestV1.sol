// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@forge/console2.sol";

contract ManifestV1 is ERC721Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Emitted when the owner withdraws available funds
    event CreatorWithdraw(address indexed account, uint256 tokensTransferred);

    /// @dev Emitted when a subscriber purchases time
    event SubscriptionFunded(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timePurchased
    );

    /// @dev Emitted when the creator refunds a subscribers remaining time
    event SubscriptionRefund(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timeReclaimed
    );

    // The subscription struct which holds the state of a subscription for an account
    struct Subscription {
        uint256 tokenId;
        uint256 secondsPurchased;
        uint256 timeOffset;
    }

    string private _baseUri;

    // The cost of one second in denominated token (wei or other base unit)
    uint256 private _tokensPerSecond;
    IERC20 private _token;

    uint256 private _tokensIn;
    uint256 private _tokensOut;
    uint256 private _tokenCounter;

    mapping(address => Subscription) private _subscriptions;

    constructor() {
        _disableInitializers();
    }

    // TODO: Native Token Guard
    receive() external payable {
        _purchase(msg.sender, msg.value);
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory baseUri,
        address owner,
        uint256 tokensPerSecond,
        address erc20TokenAddr
    ) public initializer {
        __ERC721_init(name, symbol);
        _transferOwnership(owner);
        __Pausable_init_unchained();
        _baseUri = baseUri;
        _tokensPerSecond = tokensPerSecond;
        _token = IERC20(erc20TokenAddr);
    }

    /////////////////////////
    // Consumer Calls
    /////////////////////////

    function purchase(uint256 amount) external payable {
        purchaseFor(msg.sender, amount);
    }

    function purchaseFor(address account, uint256 amount) public payable whenNotPaused {
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
        emit SubscriptionFunded(account, sub.tokenId, amount, tv);
    }

    /////////////////////////
    // Creator Calls
    /////////////////////////

    // withdrawEarnings?
    function withdraw() external payable onlyOwner {
        uint256 balance = creatorBalance();
        require(balance > 0, "No Balance");
        emit CreatorWithdraw(msg.sender, balance);
        _transferOut(msg.sender, balance);
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
