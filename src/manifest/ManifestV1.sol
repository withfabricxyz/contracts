// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@forge/console2.sol";

contract ManifestV1 is ERC721Upgradeable, OwnableUpgradeable {


    // We need to support a baseUri for the tokenURI
    // Maybe: We should support mint on behalf of (so we could support monthly credit card payments, etc)
    // We need to allow the creator to update the cost of time (maybe, if this isn't terribly hard)
    // We should allow pausing of subscriptions
    // Support ERC20 and ETH
    // Allowances for ERC20
    // revert on receive

    struct Subscription {
      uint256 tokenId;
      uint256 commited;
      uint64 credits;
      uint64 start;
    }

    // we need something that allows for fast computation of funds streamed

    uint256 private _tokensPerSecond;

    uint256 private _withdrawn;

    uint256 private _committed;
    uint256 private _time;
    uint256 private _ratio;

    uint256 private _tokenCounter;

    string private _baseUri;

    // IERC20 private _token;

    mapping(address => Subscription) private _subscriptions;

    constructor() {
      _disableInitializers();
    }

    function initialize(address creator, string memory baseUri, uint256 tokensPerSecond) public initializer {
      __ERC721_init("Manifest", "MANIFEST");
      _baseUri = baseUri;
      _tokensPerSecond = tokensPerSecond;
      _transferOwnership(creator);
    }

    function purchaseFor(address account, uint256 amount) external payable {
    }

    function purchase(uint256 amount) external payable {
        address account = msg.sender;
        require(msg.value == amount, "Err: incorrect amount");
        _purchase(account, amount);
    }

    function withdraw() external payable onlyOwner {
      uint256 balance = creatorBalance();
      require(balance > 0, "No Balance");
      _withdrawn += balance;
      (bool sent,) = payable(msg.sender).call{value: balance}("");
      require(sent, "Failed to transfer Ether");
    }

    function creatorEarnings() public view returns (uint256) {
      uint256 value = 0;
      for(uint256 i = 1; i <= _tokenCounter; i++) {
        address account = _ownerOf(i);
        value += (_subscriptions[account].credits - balanceOf(account));
      }
      return value * _tokensPerSecond;
    }

    function creatorBalance() public view returns (uint256) {
      return creatorEarnings() - _withdrawn;
    }

    /////////////////////////
    // Cancellation
    /////////////////////////

    function cancelSubscription(uint256 tokenId) external payable {
      _cancel(_ownerOf(tokenId));
    }

    function cancelSubscription() external {
      _cancel(msg.sender);
    }

    function _cancel(address account) internal {
      uint256 balance = balanceOf(account);
      require(balance > 0, "NoActiveSubscription");

      // TODO: This broken for price changes
      _subscriptions[account].credits -= uint64(balance);
      uint256 refund = balance * _tokensPerSecond;
      // _committed -= refund;
      // _committedTime -= balance;
      (bool sent,) = payable(account).call{value: refund}("");
      require(sent, "Failed to transfer Ether");
    }

    function pause() external onlyOwner {
      // pause purchases
    }

    function updatePrice(uint256 tokensPerSecond) external onlyOwner {
        _tokensPerSecond = tokensPerSecond;
    }

    function _nextTokenId() internal returns (uint256) {
        _tokenCounter += 1;
        return _tokenCounter;
    }

    function _purchase(address account, uint256 amount) internal {
        Subscription memory sub = _subscriptions[account];

        uint64 tv = timeValue(amount);
        uint64 time = uint64(block.timestamp);

        if(sub.tokenId == 0) {
          sub = Subscription(_nextTokenId(), amount, tv, time);
          _subscriptions[account] = sub;
          _safeMint(account, sub.tokenId);
        } else {
          // NAIVE! TODO (Deal with multiple price points)
          // TODO: More tests
          if(time > sub.start + sub.credits) {
            sub.start = time - sub.credits;
          }

          sub.commited += amount;
          sub.credits += tv;
          _subscriptions[account] = sub;
        }

        // TODO:
        // _committed += amount;
        // _time += tv;
        // _ratio += (amount / _committed) / _time;
        // slide time
    }

    function timeValue(uint256 amount) public view returns (uint64) {
        return uint64(amount / _tokensPerSecond);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    //////////////////////
    // Overrides
    //////////////////////

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0) && balanceOf(owner) > 0, "ERC721: invalid token ID");
        return owner;
    }

    function balanceOf(address account) public view override returns (uint256) {
      Subscription memory sub = _subscriptions[account];
      uint256 expiresAt = sub.start + sub.credits;
      if(expiresAt <= block.timestamp) {
        return 0;
      }
      return expiresAt - block.timestamp;
    }

    function subscriptionOf(address account) public view returns (uint256 tokenId, uint256 commited, uint64 credits, uint64 start) {
      Subscription memory sub = _subscriptions[account];
      return (sub.tokenId, sub.commited, sub.credits, sub.start);
    }

}

// interface IERC5643 {
//     /// @notice Emitted when a subscription expiration changes
//     /// @dev When a subscription is canceled, the expiration value should also be 0.
//     event SubscriptionUpdate(uint256 indexed tokenId, uint64 expiration);

//     /// @notice Renews the subscription to an NFT
//     /// Throws if `tokenId` is not a valid NFT
//     /// @param tokenId The NFT to renew the subscription for
//     /// @param duration The number of seconds to extend a subscription for
//     function renewSubscription(uint256 tokenId, uint64 duration)
//         external
//         payable;

//     /// @notice Cancels the subscription of an NFT
//     /// @dev Throws if `tokenId` is not a valid NFT
//     /// @param tokenId The NFT to cancel the subscription for
//     function cancelSubscription(uint256 tokenId) external payable;

//     /// @notice Gets the expiration date of a subscription
//     /// @dev Throws if `tokenId` is not a valid NFT
//     /// @param tokenId The NFT to get the expiration date of
//     /// @return The expiration date of the subscription
//     function expiresAt(uint256 tokenId) external view returns (uint64);

//     /// @notice Determines whether a subscription can be renewed
//     /// @dev Throws if `tokenId` is not a valid NFT
//     /// @param tokenId The NFT to get the expiration date of
//     /// @return The renewability of a the subscription
//     function isRenewable(uint256 tokenId) external view returns (bool);
// }