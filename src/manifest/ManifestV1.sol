// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@forge/console2.sol";

contract ManifestV1 is ERC721Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Emitted when the owner withdraws available funds
    event CreatorWithdraw(address indexed account, uint256 tokensTransferred);

    /// @dev Emitted when a subscriber purchases additional time
    event SubscriptionFunded(address indexed account, uint256 tokensTransferred, uint256 timeRemaining);

    /// @dev Emitted when a subscriber cancels and reclaims their remaining time and tokens
    event SubscriptionCanceled(address indexed account, uint256 tokensTransferred, uint256 timeReclaimed);

    // The subscription struct which holds the state of a subscription for an account
    struct Subscription {
        uint256 tokenId;
        uint256 secondsPurchased;
        uint256 timeOffset;
    }

    // The cost of one second in denominated token (wei or other base unit)
    uint256 private _tokensPerSecond;
    uint256 private _withdrawn;
    uint256 private _tokenCounter;
    string private _baseUri;

    IERC20 private _token;
    bool private _erc20;

    // IERC20 private _token;

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
        _baseUri = baseUri;
        _tokensPerSecond = tokensPerSecond;
        _token = IERC20(erc20TokenAddr);
        _erc20 = erc20TokenAddr != address(0);
    }

    /////////////////////////
    // Consumer Calls
    /////////////////////////

    function purchase(uint256 amount) external payable {
        address account = msg.sender;
        require(msg.value == amount, "Err: incorrect amount");
        _purchase(account, amount);
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
        emit SubscriptionFunded(account, amount, sub.secondsPurchased - sub.timeOffset);
    }

    function cancelSubscription(uint256 tokenId) external payable {
        _cancel(_ownerOf(tokenId));
    }

    function cancelSubscription() external {
        _cancel(msg.sender);
    }

    function _cancel(address account) internal {
        uint256 balance = timeBalanceOf(account);
        require(balance > 0, "NoActiveSubscription");
        _subscriptions[account].secondsPurchased -= balance;

        uint256 tokens = balance * _tokensPerSecond;

        emit SubscriptionCanceled(account, tokens, balance);
        (bool sent,) = payable(account).call{value: tokens}("");
        require(sent, "Failed to transfer Ether");
    }

    /////////////////////////
    // Creator Calls
    /////////////////////////

    // withdrawEarnings?
    function withdraw() external payable onlyOwner {
        uint256 balance = creatorBalance();
        require(balance > 0, "No Balance");
        _withdrawn += balance;

        emit CreatorWithdraw(msg.sender, balance);
        (bool sent,) = payable(msg.sender).call{value: balance}("");
        require(sent, "Failed to transfer Ether");
    }

    function pausePurchases() external onlyOwner {}

    // function setTokensPerSecond(uint256 tokensPerSecond) external onlyOwner {
    //     _tokensPerSecond = tokensPerSecond;
    // }

    function _nextTokenId() internal returns (uint256) {
        _tokenCounter += 1;
        return _tokenCounter;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    ////////////////////////
    // Informational
    ////////////////////////

    function timeValue(uint256 amount) public view returns (uint256) {
        return amount / _tokensPerSecond;
    }

    function creatorBalance() public view returns (uint256) {
        return creatorEarnings() - _withdrawn;
    }

    function creatorEarnings() public view returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 1; i <= _tokenCounter; i++) {
            address account = _ownerOf(i);
            value += (_subscriptions[account].secondsPurchased - timeBalanceOf(account));
        }
        return value * _tokensPerSecond;
    }

    //////////////////////
    // Overrides
    //////////////////////

    // balanceOf is the number of tokens at time of call
    function balanceOf(address account) public view override returns (uint256) {
        return timeBalanceOf(account) * _tokensPerSecond;
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
}
