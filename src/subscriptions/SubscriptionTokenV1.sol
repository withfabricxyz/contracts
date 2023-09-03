// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/contracts/utils/StringsUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title Subscription Token
 * @author Fabric Inc.
 * @notice An NFT contract which allows users to mint time and access token gated content while time remains.
 * @dev The balanceOf function returns the number of seconds remaining in the subscription. Token gated systems leverage
 *      the balanceOf function to determine if a user has the token, and if no time remains, the balance is 0. NFT holders
 *      can mint additional time at any point. The creator/owner of the contract can withdraw the funds at any point. There are
 *      additional functionalities for granting time, refunding accounts, fees, etc. This contract is designed to be used with
 *      Clones, but is not designed to be upgradeable. Added functionality will come with new versions.
 */

contract SubscriptionTokenV1 is
    ERC721Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using StringsUpgradeable for uint256;

    /// @dev The number of reward halvings
    uint256 private constant _NUM_REWARD_HALVINGS = 6;

    /// @dev The starting reward multiplier for subscriber rewards
    uint256 private constant _STARTING_REWARD_MULTIPLIER = 2 ** _NUM_REWARD_HALVINGS;

    /// @dev The number of seconds until the reward multipler is halved
    uint256 private constant _REWARD_MULTIPLIER_HALVING_SECONDS = 30 days;

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
    event Withdraw(address indexed account, uint256 tokensTransferred);

    /// @dev Emitted when a subscriber purchases time
    event Purchase(
        address indexed account,
        uint256 indexed tokenId,
        uint256 tokensTransferred,
        uint256 timePurchased,
        uint256 expiresAt
    );

    /// @dev Emitted when a subscriber is granted time by the creator
    event Grant(address indexed account, uint256 indexed tokenId, uint256 secondsGranted, uint256 expiresAt);

    /// @dev Emitted when the creator refunds a subscribers remaining time
    event Refund(address indexed account, uint256 indexed tokenId, uint256 tokensTransferred, uint256 timeReclaimed);

    /// @dev Emitted when the fees are transferred to the collector
    event FeeTransfer(address indexed from, address indexed to, uint256 tokensTransferred);

    /// @dev Emitted when the fee collector is updated
    event FeeCollectorChange(address indexed from, address indexed to);

    /// @dev Emitted when a reward is paid out
    event Reward(uint256 indexed tokenId, address indexed referrer, uint256 indexed referralId, uint256 rewardAmount);

    /// @dev Emitted when a new referral code is created
    event RewardCreated(uint256 id, uint16 rewardBpsMin, uint16 rewardBpsMax);

    /// @dev Emitted when a referral code is deleted
    event RewardDestroyed(uint256 id);

    /// @dev The subscription struct which holds the state of a subscription for an account
    struct Subscription {
        uint256 tokenId;
        uint256 secondsPurchased;
        uint256 secondsGranted;
        uint256 grantOffset;
        uint256 purchaseOffset;
        uint256 rewardPoints;
        uint256 rewardWithdrawn;
    }

    struct ReferralCode {
        uint16 rewardBpsMin;
        uint16 rewardBpsMax;
    }

    /// @dev The metadata URI for the contract
    string private _contractURI;

    /// @dev The metadata URI for the tokens. Note: if it ends with /, then we append the tokenId
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

    /// @dev The fee collector address
    address private _feeCollector;

    /// @dev Flag which determines if the contract is erc20 denominated
    bool private _erc20;

    /// @dev The block timestamp of the contract deployment
    uint256 private _deployBlockTime;

    /// @dev The subscription state for each account
    mapping(address => Subscription) private _subscriptions;

    /// @dev The collection or referral codes for referral rewards
    mapping(uint256 => ReferralCode) private _referralCodes;

    ////////////////////////////////////

    constructor() {
        _disableInitializers();
    }

    /// @dev Fallback function to mint time for native token contracts
    receive() external payable {
        mintFor(msg.sender, msg.value);
    }

    /**
     * @dev Initialize acts as the constructor, as this contract is intended to work with proxy contracts.
     *
     * @param name the name of the collection
     * @param symbol the symbol of the collection
     * @param contractUri the metadata URI for the collection
     * @param tokenUri the metadata URI for the tokens
     * @param owner the owner address, for owner only functionality
     * @param tokensPerSecond the number of base tokens required for a single second of time
     * @param minimumPurchaseSeconds the minimum number of seconds an account can purchase
     * @param feeBps the fee in basis points, allocated to the fee collector on withdrawal
     * @param feeRecipient the fee collector address
     * @param erc20TokenAddr the address of the ERC20 token used for purchases, or the 0x0 for native
     */
    function initialize(
        string memory name,
        string memory symbol,
        string memory contractUri,
        string memory tokenUri,
        address owner,
        uint256 tokensPerSecond,
        uint256 minimumPurchaseSeconds,
        uint16 feeBps,
        address feeRecipient,
        address erc20TokenAddr
    ) public initializer {
        require(owner != address(0), "Owner address cannot be 0x0");
        require(tokensPerSecond > 0, "Tokens per second must be > 0");
        require(minimumPurchaseSeconds > 0, "Min purchase seconds must be > 0");
        require(feeBps <= _MAX_FEE_BIPS, "Fee bps too high");
        if (feeRecipient != address(0)) {
            require(feeBps > 0, "Fees required when fee recipient is present");
        }

        __ERC721_init(name, symbol);
        _transferOwnership(owner);
        __Pausable_init_unchained();
        __ReentrancyGuard_init();
        _contractURI = contractUri;
        _tokenURI = tokenUri;
        _tokensPerSecond = tokensPerSecond;
        _minimumPurchase = minimumPurchaseSeconds * tokensPerSecond;
        _feeBps = feeBps;
        _feeCollector = feeRecipient;
        _token = IERC20(erc20TokenAddr);
        _erc20 = erc20TokenAddr != address(0);
        _deployBlockTime = block.timestamp;
    }

    /////////////////////////
    // Subscriber Calls
    /////////////////////////

    /**
     * @notice Mint or renew a subscription for sender
     * @param numTokens the amount of ERC20 tokens or native tokens to transfer
     */
    function mint(uint256 numTokens) external payable {
        mintFor(msg.sender, numTokens);
    }

    /**
     * @notice Mint or renew a subscription for sender, with referral rewards for a referrer
     * @param numTokens the amount of ERC20 tokens or native tokens to transfer
     * @param referralCode the referral code to use for rewards
     * @param referrer the referrer address and reward recipient
     */
    function mintWithReferral(uint256 numTokens, uint256 referralCode, address referrer) external payable {
        mintWithReferralFor(msg.sender, numTokens, referralCode, referrer);
    }

    /////////////////////////
    // Creator Calls
    /////////////////////////

    /**
     * @notice Withdraw available funds as the owner
     */
    function withdraw() external {
        withdrawTo(msg.sender);
    }

    /**
     * @notice Withdraw available funds and transfer fees as the owner
     */
    function withdrawAndTransferFees() external {
        withdrawTo(msg.sender);
        if (_feeBalance > 0) {
            _transferFees();
        }
    }

    /**
     * @notice Withdraw available funds as the owner to a different account
     * @param account the account to transfer funds to
     */
    function withdrawTo(address account) public onlyOwner {
        uint256 balance = creatorBalance();
        require(balance > 0, "No Balance");
        _transferToCreator(account, balance);
    }

    /**
     * @notice Refund one or more accounts remaining purchased time
     * @dev This refunds accounts using creator balance, and can also transfer in to top up the fund. Any excess value is withdrawable, but subject to fees.
     * @param numTokensIn an optional amount of tokens to transfer in before refunding
     * @param accounts the list of accounts to refund
     */
    function refund(uint256 numTokensIn, address[] memory accounts) external payable onlyOwner {
        if (numTokensIn > 0) {
            _transferIn(msg.sender, numTokensIn);
        } else if (msg.value > 0) {
            revert("Unexpected value transfer");
        }
        require(canRefund(accounts), "Insufficient balance for refund");
        for (uint256 i = 0; i < accounts.length; i++) {
            _refund(accounts[i]);
        }
    }

    /**
     * @notice Refund all remaining purchased time for accounts
     * @param accounts the list of accounts to refund
     * @return the total number of refundable tokens
     */
    function refundableTokenBalanceOfAll(address[] memory accounts) public view returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < accounts.length; i++) {
            amount += refundableBalanceOf(accounts[i]);
        }
        return amount * _tokensPerSecond;
    }

    /**
     * @notice Can the refund be processed for the given accounts with the current balance
     * @param accounts the list of accounts to refund
     * @return true if the refund can be processed
     */
    function canRefund(address[] memory accounts) public view returns (bool) {
        return creatorBalance() >= refundableTokenBalanceOfAll(accounts);
    }

    /**
     * @notice Update the contract metadata
     * @param contractUri the collection metadata URI
     * @param tokenUri the token metadata URI
     */
    function updateMetadata(string memory contractUri, string memory tokenUri) external onlyOwner {
        _contractURI = contractUri;
        _tokenURI = tokenUri;
    }

    /**
     * @notice Grant time to a list of accounts, so they can access content without paying
     * @param accounts the list of accounts to grant time to
     * @param secondsToAdd the number of seconds to grant for each account
     */
    function grantTime(address[] memory accounts, uint256 secondsToAdd) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantTime(accounts[i], secondsToAdd);
        }
    }

    /**
     * @notice Pause minting to allow for upgrades or shutting down the subscription
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause to resume subscription minting
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /////////////////////////
    // Sponsored Calls
    /////////////////////////

    /**
     * @notice Mint or renew a subscription for a specific account
     * @param account the account to mint or renew time for
     * @param numTokens the amount of ERC20 tokens or native tokens to transfer
     */
    function mintFor(address account, uint256 numTokens) public payable whenNotPaused validAmount(numTokens) {
        uint256 finalAmount = _transferIn(msg.sender, numTokens);
        _purchaseTime(account, finalAmount);
    }

    /**
     * @notice Mint or renew a subscription for a specific account, with referral rewards for a referrer
     * @param account the account to mint or renew time for
     * @param numTokens the amount of ERC20 tokens or native tokens to transfer
     * @param referralCode the referral code to use for rewards
     * @param referrer the referrer address and reward recipient
     */
    function mintWithReferralFor(address account, uint256 numTokens, uint256 referralCode, address referrer)
        public
        payable
        whenNotPaused
        validAmount(numTokens)
    {
        // Transfer all here
        uint256 finalAmount = _transferIn(msg.sender, numTokens);

        uint256 tokenId = _purchaseTime(account, finalAmount);

        // Calculate rewards and transfer rewards out
        uint256 rewardAmount = _rewardAmount(finalAmount, referralCode);
        if (rewardAmount > 0) {
            _transferOut(referrer, rewardAmount);
            emit Reward(tokenId, referrer, referralCode, rewardAmount);
        }
    }

    /**
     * @notice Transfer any available fees to the fee collector
     */
    function transferFees() external {
        require(_feeBalance > 0, "No fees to collect");
        _transferFees();
    }

    /**
     * @notice Transfer all balances to the creator and fee collector (if applicable)
     * @dev This is a way for EOAs to pay gas fees on behalf of the creator (automation, etc)
     */
    function transferAllBalances() external {
        _transferAllBalances(owner());
    }

    /**
     * @notice Reconcile the ERC20 balance of the contract with the internal state
     * @dev The prevents lost funds if ERC20 tokens are transferred directly to the contract account
     */
    function reconcileERC20Balance() external {
        require(_erc20, "Only for ERC20 tokens");
        uint256 balance = _token.balanceOf(address(this));
        uint256 expectedBalance = _tokensIn - _tokensOut;
        require(balance > expectedBalance, "Tokens already reconciled");
        _tokensIn += balance - expectedBalance;
    }

    /////////////////////////
    // Fee Management
    /////////////////////////

    /**
     * @notice Fetch the current fee schedule
     * @return feeCollector the feeCollector address
     * @return feeBps the fee basis points
     */
    function feeSchedule() external view returns (address feeCollector, uint16 feeBps) {
        return (_feeCollector, _feeBps);
    }

    /**
     * @notice Fetch the accumulated fee balance
     * @return balance the accumulated fees which have not yet been transferred
     */
    function feeBalance() external view returns (uint256 balance) {
        return _feeBalance;
    }

    /**
     * @notice Update the fee collector address. Can be set to 0x0 to disable fees.
     * @param newCollector the new fee collector address
     */
    function updateFeeRecipient(address newCollector) external {
        require(msg.sender == _feeCollector, "Unauthorized");
        // Give tokens back to creator and set fee rate to 0
        if (newCollector == address(0)) {
            _feeBalance = 0;
            _feeBps = 0;
        }
        _feeCollector = newCollector;
        emit FeeCollectorChange(msg.sender, newCollector);
    }

    /////////////////////////
    // Referral Rewards
    /////////////////////////

    /**
     * @notice Create a referral code for giving rewards to referrers on mint
     * @dev It's possible to create a spread here for variable rewards
     * @param code the unique integer code for the referral
     * @param minBps the minimum reward basis points
     * @param maxBps the maximum reward basis points
     */
    function createReferralCode(uint256 code, uint16 minBps, uint16 maxBps) external onlyOwner {
        require(maxBps <= _MAX_BIPS, "maxBps too high");
        require(minBps <= maxBps, "minBps > maxBps");
        ReferralCode memory existing = _referralCodes[code];
        require(existing.rewardBpsMin == existing.rewardBpsMax && existing.rewardBpsMin == 0, "Referral code exists");
        _referralCodes[code] = ReferralCode(minBps, maxBps);
        emit RewardCreated(code, minBps, maxBps);
    }

    /**
     * @notice Delete a referral code
     * @param code the unique integer code for the referral
     */
    function deleteReferralCode(uint256 code) external onlyOwner {
        delete _referralCodes[code];
        emit RewardDestroyed(code);
    }

    /**
     * @notice Fetch the reward basis points for a given referral code
     * @param code the unique integer code for the referral
     * @return minBps the minimum reward basis points
     * @return maxBps the maximum reward basis points
     */
    function referralRewards(uint256 code) external view returns (uint16 minBps, uint16 maxBps) {
        ReferralCode memory existing = _referralCodes[code];
        return (existing.rewardBpsMin, existing.rewardBpsMax);
    }

    ////////////////////////
    // Core Internal Logic
    ////////////////////////

    /// @dev Add time to a given account (transfer happens before this is called)
    function _purchaseTime(address account, uint256 amount) internal returns (uint256) {
        Subscription memory sub = _fetchSubscription(account);

        // Adjust offset to account for existing time
        if (block.timestamp > sub.purchaseOffset + sub.secondsPurchased) {
            sub.purchaseOffset = block.timestamp - sub.secondsPurchased;
        }

        uint256 tv = timeValue(amount);
        sub.secondsPurchased += tv;
        sub.rewardPoints += amount * rewardMultiplier();
        _subscriptions[account] = sub;
        emit Purchase(account, sub.tokenId, amount, tv, _subscriptionExpiresAt(sub));
        return sub.tokenId;
    }

    /// @dev Get or create a new subscription (and mint)
    function _fetchSubscription(address account) internal returns (Subscription memory) {
        Subscription memory sub = _subscriptions[account];
        if (sub.tokenId == 0) {
            _tokenCounter += 1;
            sub = Subscription(_tokenCounter, 0, 0, block.timestamp, block.timestamp, 0, 0);
            _safeMint(account, sub.tokenId);
        }
        return sub;
    }

    /// @dev Allocate fees to the fee collector for a given amount of tokens
    function _allocateFees(uint256 amount) internal returns (uint256) {
        uint256 fee = (amount * _feeBps) / _MAX_BIPS;
        _feeBalance += fee;
        return amount - fee;
    }

    /// @dev Transfer tokens into the contract, either native or ERC20
    function _transferIn(address from, uint256 amount) internal nonReentrant returns (uint256) {
        require(amount > 0, "Transfer amount must be > 0");
        uint256 finalAmount = amount;
        if (_erc20) {
            // Handle tokens which take fees
            require(msg.value == 0, "Native tokens not accepted for ERC20 subscriptions");
            uint256 preBalance = _token.balanceOf(from);
            uint256 allowance = _token.allowance(from, address(this));
            require(preBalance >= amount && allowance >= amount, "Insufficient Balance or Allowance");
            _token.safeTransferFrom(from, address(this), amount);
            uint256 postBalance = _token.balanceOf(from);
            finalAmount = preBalance - postBalance;
        } else {
            require(msg.value == amount, "Purchase amount must match value sent");
        }
        _tokensIn += finalAmount;
        return finalAmount;
    }

    /// @dev Transfer tokens to the creator, after allocating fees
    function _transferToCreator(address to, uint256 amount) internal {
        uint256 finalAmount = _allocateFees(amount);
        emit Withdraw(to, finalAmount);
        _transferOut(to, finalAmount);
    }

    /// @dev Transfer tokens out of the contract, either native or ERC20
    function _transferOut(address to, uint256 amount) internal nonReentrant {
        require(amount > 0, "Transfer amount must be > 0");
        _tokensOut += amount;
        if (_erc20) {
            _token.safeTransfer(to, amount);
        } else {
            (bool sent,) = payable(to).call{value: amount}("");
            require(sent, "Failed to transfer Ether");
        }
    }

    /// @dev Transfer fees to the fee collector
    function _transferFees() internal {
        uint256 balance = _feeBalance;
        _feeBalance = 0;
        _transferOut(_feeCollector, balance);
        emit FeeTransfer(msg.sender, _feeCollector, balance);
    }

    /// @dev Transfer all remaining balances to the creator and fee collector (if applicable)
    function _transferAllBalances(address balanceRecipient) internal {
        uint256 balance = creatorBalance();
        if (balance > 0) {
            _transferToCreator(balanceRecipient, balance);
        }

        // Transfer out all remaining funds
        if (_feeBalance > 0) {
            _transferFees();
        }
    }

    /// @dev Grant time to a given account
    function _grantTime(address account, uint256 numSeconds) internal {
        Subscription memory sub = _fetchSubscription(account);
        // Adjust offset to account for existing time
        if (block.timestamp > sub.grantOffset + sub.secondsGranted) {
            sub.grantOffset = block.timestamp - sub.secondsGranted;
        }

        sub.secondsGranted += numSeconds;
        _subscriptions[account] = sub;

        emit Grant(account, sub.tokenId, numSeconds, _subscriptionExpiresAt(sub));
    }

    /// @dev The amount of granted time remaining for a given subscription
    function _grantTimeRemaining(Subscription memory sub) internal view returns (uint256) {
        uint256 expiresAt = sub.grantOffset + sub.secondsGranted;
        if (expiresAt <= block.timestamp) {
            return 0;
        }
        return expiresAt - block.timestamp;
    }

    /// @dev The amount of purchased time remaining for a given subscription
    function _purchaseTimeRemaining(Subscription memory sub) internal view returns (uint256) {
        uint256 expiresAt = sub.purchaseOffset + sub.secondsPurchased;
        if (expiresAt <= block.timestamp) {
            return 0;
        }
        return expiresAt - block.timestamp;
    }

    /// @dev Refund the remaining time for the given accounts subscription, and clear grants
    function _refund(address account) internal {
        Subscription memory sub = _subscriptions[account];
        if (sub.secondsPurchased == 0 && sub.secondsGranted == 0) {
            return;
        }

        sub.secondsGranted = 0;
        uint256 balance = refundableBalanceOf(account);
        uint256 tokens = balance * _tokensPerSecond;
        if (balance > 0) {
            sub.secondsPurchased -= balance;
            _transferOut(account, tokens);
        }
        _subscriptions[account] = sub;
        emit Refund(account, sub.tokenId, tokens, balance);
    }

    /// @dev Compute the reward amount for a given token amount and referral code
    function _rewardAmount(uint256 tokenAmount, uint256 referralCode) internal view returns (uint256) {
        ReferralCode memory code = _referralCodes[referralCode];
        if (code.rewardBpsMin == 0 && code.rewardBpsMax == 0) {
            return 0;
        }

        uint256 rewardBps;
        uint256 delta = code.rewardBpsMax - code.rewardBpsMin;
        if (delta == 0) {
            rewardBps = code.rewardBpsMin;
        } else {
            // Psuedo random value between min and max (variable reward). This is weak, but acceptable given the nature
            // of these rewards. The amount of tokens transferred will never be less than the minimum reward. If a miner
            // is the referrer, then rewards could be biased towards the max reward. Creators should opt to use a fixed
            // reward if they are concerned about this.
            rewardBps = code.rewardBpsMin
                + uint256(keccak256(abi.encode(block.difficulty, msg.sender, tokenAmount, _tokensOut))) % delta;
        }

        return (tokenAmount * rewardBps) / _MAX_BIPS;
    }

    /// @dev The timestamp when the subscription expires
    function _subscriptionExpiresAt(Subscription memory sub) internal view returns (uint256 numSeconds) {
        return block.timestamp + _purchaseTimeRemaining(sub) + _grantTimeRemaining(sub);
    }

    ////////////////////////
    // Informational
    ////////////////////////

    // TODO: Should this go to 0 to reduce the probability of overflow over time? Y2K problem?
    function rewardMultiplier() public view returns (uint256 multiplier) {
        uint256 halvings = (block.timestamp - _deployBlockTime) / _REWARD_MULTIPLIER_HALVING_SECONDS;
        if (halvings >= _NUM_REWARD_HALVINGS) {
            return 1;
        }
        return _STARTING_REWARD_MULTIPLIER / (2 ** halvings);
    }

    /**
     * @notice The amount of time exchanged for the given number of tokens
     * @param numTokens the number of tokens to exchange for time
     * @return numSeconds the number of seconds purchased
     */
    function timeValue(uint256 numTokens) public view returns (uint256 numSeconds) {
        return numTokens / _tokensPerSecond;
    }

    /**
     * @notice The creators withdrawable balance
     * @return balance the number of tokens available for withdraw
     */
    function creatorBalance() public view returns (uint256 balance) {
        return _tokensIn - _tokensOut - _feeBalance;
    }

    /**
     * @notice The sum of all deposited tokens over time. Fees and refunds are not accounted for.
     * @return total the total number of tokens deposited
     */
    function totalCreatorEarnings() public view returns (uint256 total) {
        return _tokensIn;
    }

    /**
     * @notice Relevant subscription information for a given account
     * @return tokenId the tokenId for the account
     * @return refundableAmount the number of seconds which can be refunded
     * @return rewardPoints the number of reward points earned
     * @return expiresAt the timestamp when the subscription expires
     */
    function subscriptionOf(address account)
        public
        view
        returns (uint256 tokenId, uint256 refundableAmount, uint256 rewardPoints, uint256 expiresAt)
    {
        Subscription memory sub = _subscriptions[account];

        uint256 expires = _subscriptionExpiresAt(sub);
        if (expires <= block.timestamp) {
            expires = 0;
        }

        return (sub.tokenId, sub.secondsPurchased, sub.rewardPoints, expires);
    }

    /**
     * @notice The ERC-20 address used for purchases, or 0x0 for native
     * @return ERC20 address or 0x0 for native
     */
    function erc20Address() public view returns (address) {
        return address(_token);
    }

    /**
     * @notice The refundable time balance for a given account
     * @param account the account to check
     * @return numSeconds the number of seconds which can be refunded
     */
    function refundableBalanceOf(address account) public view returns (uint256 numSeconds) {
        Subscription memory sub = _subscriptions[account];
        return _purchaseTimeRemaining(sub);
    }

    /**
     * @notice The contract metadata URI for NFT aggregators
     * @return the contract metadata URI
     */
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice The base token URI for generating token metadata
     * @return the base token URI
     */
    function baseTokenURI() public view returns (string memory) {
        return _tokenURI;
    }

    /**
     * @notice The number of tokens required for a single second of time
     * @return the number of tokens required for a single second of time
     */
    function tps() external view returns (uint256) {
        return _tokensPerSecond;
    }

    /**
     * @notice The minimum number of seconds required for a purchase
     * @return the minimum number of seconds required for a purchase
     */
    function minPurchaseSeconds() external view returns (uint256) {
        return _minimumPurchase / _tokensPerSecond;
    }

    /**
     * @notice Fetch the metadata URI for a given token
     * @dev If _tokenURI ends with a / then the tokenId is appended
     * @param tokenId the tokenId to fetch the metadata URI for
     * @return the metadata URI for the given tokenId
     */
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

    /**
     * @notice Override the default balanceOf behavior to account for time remaining
     * @param account the account to fetch the balance of
     * @return numSeconds the number of seconds remaining in the subscription
     */
    function balanceOf(address account) public view override returns (uint256 numSeconds) {
        Subscription memory sub = _subscriptions[account];
        return _purchaseTimeRemaining(sub) + _grantTimeRemaining(sub);
    }

    /**
     * @notice Renounce ownership of the contract, transferring all remaining funds to the creator and fee collector
     *         and pausing the contract to prevent further inflows.
     */
    function renounceOwnership() public override onlyOwner {
        _transferAllBalances(msg.sender);
        _pause();
        _transferOwnership(address(0));
    }

    /// @dev Transfers may occur if the destination does not have a subscription
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
