// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "src/tokens/ERC20Token.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";

import "@forge/Test.sol";
import "@forge/console2.sol";

abstract contract BaseTest is Test {
    event Purchase(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timePurchased, uint256 expiresAt
    );
    event Refund(address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timeReclaimed);
    event Grant(address indexed account, uint256 tokenId, uint256 secondsGranted, uint256 expiresAt);

    event Withdraw(address indexed account, uint256 tokensTransferred);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event FeeTransfer(address indexed from, address indexed to, uint256 tokensTransferred);
    event FeeCollectorChange(address indexed from, address indexed to);

    modifier prank(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    modifier withFees() {
        stp = createETHManifest(1, 500);
        _;
    }

    modifier erc20() {
        stp = createERC20Manifest();
        _;
    }

    address internal creator = 0xB4c79DAB8f259C7AEE6e5B2Aa729821764227E8A;
    address internal fees = 0xB4C79DAB8f259c7Aee6E5b2AA729821764227e7A;
    address internal alice = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal bob = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal charlie = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;

    SubscriptionNFTV1 internal stp;

    function mint(address account, uint256 amount) internal prank(account) {
        if (stp.erc20Address() != address(0)) {
            token().approve(address(stp), amount);
            stp.mint(amount);
        } else {
            stp.mint{value: amount}(amount);
        }
    }

    function list(address account) internal pure returns (address[] memory) {
        address[] memory subscribers = new address[](1);
        subscribers[0] = account;
        return subscribers;
    }

    function withdraw() internal prank(creator) {
        stp.withdraw();
    }

    function token() internal view returns (ERC20Token) {
        return ERC20Token(stp.erc20Address());
    }

    function createERC20Manifest() public virtual returns (SubscriptionNFTV1) {
        ERC20Token _token = new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
        _token.transfer(alice, 1e20);
        _token.transfer(bob, 1e20);
        _token.transfer(charlie, 1e20);
        _token.transfer(creator, 1e20);

        SubscriptionNFTV1 m = new SubscriptionNFTV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        m.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, 2, 0, address(0), address(_token));
        return m;
    }

    function createETHManifest(uint256 minPurchase, uint16 feeBps) public virtual returns (SubscriptionNFTV1) {
        SubscriptionNFTV1 m = new SubscriptionNFTV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        if (feeBps > 0) {
            m.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, minPurchase, feeBps, fees, address(0));
        } else {
            m.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, minPurchase, 0, address(0), address(0));
        }
        return m;
    }

    function testIgnore() internal {}
}
