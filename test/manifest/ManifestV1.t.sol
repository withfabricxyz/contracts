// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/manifest/ManifestV1.sol";
import "src/tokens/ERC20Token.sol";

contract ManifestV1Test is Test {
    // error NoActiveSubscription(address account);
    event SubscriptionFunded(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timePurchased
    );
    event SubscriptionRefund(
        address indexed account, uint256 tokenId, uint256 tokensTransferred, uint256 timeReclaimed
    );
    event CreatorWithdraw(address indexed account, uint256 tokensTransferred);

    modifier prank(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    modifier erc20() {
        manifest = createERC20Manifest();
        _;
    }

    address internal creator = 0xB4c79DAB8f259C7AEE6e5B2Aa729821764227E8A;
    address internal fees = 0xB4C79DAB8f259c7Aee6E5b2AA729821764227e7A;
    address internal alice = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal bob = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal charlie = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;

    ManifestV1 internal manifest;

    function purchase(address account, uint256 amount) internal prank(account) {
        if (manifest.isERC20()) {
            token().approve(address(manifest), amount);
            manifest.purchase(amount);
        } else {
            manifest.purchase{value: amount}(amount);
        }
    }

    function token() internal view returns (ERC20Token) {
        return ERC20Token(manifest.erc20Address());
    }

    function createERC20Manifest() public virtual returns (ManifestV1) {
        ERC20Token _token = new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
        _token.transfer(alice, 1e20);
        _token.transfer(bob, 1e20);
        _token.transfer(charlie, 1e20);
        _token.transfer(creator, 1e20);

        ManifestV1 m = new ManifestV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        m.initialize("Meow Manifest", "MEOW", "https://art.meow.com/", creator, 2, address(_token));
        return m;
    }

    function createETHManifest() public virtual returns (ManifestV1) {
        ManifestV1 m = new ManifestV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        m.initialize("Meow Manifest", "MEOW", "https://art.meow.com/", creator, 2, address(0));
        return m;
    }

    function setUp() public {
        manifest = new ManifestV1();

        vm.store(address(manifest), bytes32(uint256(0)), bytes32(0));
        manifest.initialize("Meow Manifest", "MEOW", "https://art.meow.com/", creator, 2, address(0));

        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testInit() public {
        assertFalse(manifest.isERC20());
        assertEq(manifest.timeValue(2), 1);
    }

    function testPurchase() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(alice, 1, 1e18, 1e18 / 2);
        manifest.purchase{value: 1e18}(1e18);
        assertEq(address(manifest).balance, 1e18);
        assertEq(manifest.timeBalanceOf(alice), 5e17);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
        assertEq(manifest.tokenURI(1), "https://art.meow.com/1");
    }

    function testPurchaseInvalid() public prank(alice) {
        vm.expectRevert("Purchase amount must match value sent");
        manifest.purchase{value: 1e17}(1e18);
    }

    function testPurchaseFor() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(bob, 1, 1e18, 1e18 / 2);
        manifest.purchaseFor{value: 1e18}(bob, 1e18);
        assertEq(address(manifest).balance, 1e18);
        assertEq(manifest.timeBalanceOf(bob), 5e17);
        assertEq(manifest.timeBalanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(bob);
        assertEq(manifest.ownerOf(tokenId), bob);
    }

    function testNonSub() public {
        assertEq(manifest.timeBalanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.expectRevert("ERC721: invalid token ID");
        manifest.ownerOf(tokenId);
    }

    function testPurchaseDecay() public prank(alice) {
        manifest.purchase{value: 1e18}(1e18);
        vm.warp(block.timestamp + 25e16);
        assertEq(manifest.timeBalanceOf(alice), 5e17 / 2);
        assertEq(manifest.balanceOf(alice), 5e17);
    }

    function testPurchasExpire() public prank(alice) {
        manifest.purchase{value: 1e18}(1e18);
        vm.warp(block.timestamp + 6e17);
        assertEq(manifest.timeBalanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
    }

    function testPurchaseSpaced() public {
        purchase(alice, 1e18);
        assertEq(manifest.timeBalanceOf(alice), 5e17);
        vm.warp(block.timestamp + 1e18);
        assertEq(manifest.timeBalanceOf(alice), 0);
        purchase(alice, 1e18);
        assertEq(manifest.timeBalanceOf(alice), 5e17);
    }

    function testCreatorEarnings() public {
        purchase(alice, 1e18);
        purchase(bob, 1e18);
        purchase(charlie, 1e18);
        assertEq(manifest.creatorBalance(), 3e18);
    }

    function testCreatorWithdraw() public {
        purchase(alice, 1e18);
        purchase(bob, 1e18);
        vm.startPrank(creator);
        assertEq(manifest.creatorBalance(), 2e18);

        vm.expectEmit(true, true, false, true, address(manifest));
        emit CreatorWithdraw(creator, 2e18);
        manifest.withdraw();
        assertEq(manifest.creatorBalance(), 0);
        assertEq(manifest.creatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        manifest.withdraw();
        vm.stopPrank();

        assertEq(address(manifest).balance, 0);
    }

    function testRefund() public {
        purchase(alice, 1e18);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionRefund(alice, tokenId, 1e18, 1e18 / 2);
        (creator, 2e18);
        manifest.refund(alice);
        assertEq(address(manifest).balance, 0);
        vm.expectRevert("NoActiveSubscription");
        manifest.refund(alice);
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        manifest.refund(alice);
    }

    function testPartialRefund() public {
        purchase(alice, 1e18);
        vm.warp(block.timestamp + 2.5e17);
        assertEq(5e17, manifest.balanceOf(alice));
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionRefund(alice, 1, 5e17, 5e17 / 2);
        manifest.refund(alice);
        vm.stopPrank();
    }

    // TODO: Invalid transferOut address

    function testPausing() public {
        vm.startPrank(creator);
        manifest.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        manifest.purchase{value: 1e17}(1e17);
        vm.stopPrank();

        vm.startPrank(creator);
        manifest.unpause();
        vm.stopPrank();

        purchase(alice, 1e17);
    }

    /// ERC20

    function testERC20Purchase() public erc20 prank(alice) {
        assertTrue(manifest.isERC20());
        assertEq(token().balanceOf(alice), 1e20);
        token().approve(address(manifest), 1e18);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(alice, 1, 1e18, 1e18 / 2);
        manifest.purchase(1e18);
        assertEq(token().balanceOf(address(manifest)), 1e18);
        assertEq(manifest.timeBalanceOf(alice), 5e17);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
    }

    function testPurchaseInvalidERC20() public erc20 prank(alice) {
        vm.expectRevert("Native tokens not accepted for ERC20 subscriptions");
        manifest.purchase{value: 1e17}(1e18);
        vm.expectRevert("Insufficient Balance or Allowance");
        manifest.purchase(1e18);
    }

    function testWithdrawERC20() public erc20 {
        purchase(alice, 1e18);
        purchase(bob, 1e18);

        uint256 beforeBalance = token().balanceOf(creator);
        vm.startPrank(creator);
        assertEq(manifest.creatorBalance(), 2e18);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit CreatorWithdraw(creator, 2e18);
        manifest.withdraw();
        assertEq(manifest.creatorBalance(), 0);
        assertEq(manifest.creatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        manifest.withdraw();
        vm.stopPrank();

        assertEq(beforeBalance + 2e18, token().balanceOf(creator));
    }

    function testRefundERC20() public erc20 {
        purchase(alice, 1e18);
        uint256 beforeBalance = token().balanceOf(alice);
        vm.startPrank(creator);
        manifest.refund(alice);
        vm.stopPrank();
        assertEq(beforeBalance + 1e18, token().balanceOf(alice));
    }

    function testRefundERC20AfterWithdraw() public erc20 {
        purchase(alice, 1e18);
        vm.startPrank(creator);
        manifest.withdraw();
        vm.expectRevert("Insufficient Balance");
        manifest.refund(alice);
        vm.stopPrank();
    }
}
