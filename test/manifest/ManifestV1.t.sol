// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
// import "../finance/CrowdFinancingV1/BaseCampaignTest.t.sol";
// import "src/finance/CrowdFinancingV1.sol";
// import "src/tokens/ERC20Token.sol";
import "src/manifest/ManifestV1.sol";

contract ManifestV1Test is Test {
    // error NoActiveSubscription(address account);

      modifier prank(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }
    address internal creator = 0xB4c79DAB8f259C7AEE6e5B2Aa729821764227E8A;
    address internal fees = 0xB4C79DAB8f259c7Aee6E5b2AA729821764227e7A;
    address internal alice = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal bob = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal charlie = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;

    ManifestV1 internal manifest;

    function purchase(address account, uint256 amount) internal prank(account) {
      manifest.purchase{ value: amount }(amount);
    }

    function cancel(address account) internal prank(account) {
      manifest.cancelSubscription();
    }

    function setUp() public {
        manifest = new ManifestV1();

        vm.store(address(manifest), bytes32(uint256(0)), bytes32(0));
        manifest.initialize(
          creator,
          "https://art.meow.com/",
          2
        );

        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testSub() public prank(alice) {
      manifest.purchase{ value: 1e18 }(1e18);
      assertEq(address(manifest).balance, 1e18);
      assertEq(manifest.balanceOf(alice), 5e17);
      (uint256 tokenId,,,) = manifest.subscriptionOf(alice);
      assertEq(manifest.ownerOf(tokenId), alice);
    }

    function testNonSub() public {
      assertEq(manifest.balanceOf(alice), 0);
      (uint256 tokenId,,,) = manifest.subscriptionOf(alice);
      vm.expectRevert("ERC721: invalid token ID");
      manifest.ownerOf(tokenId);
    }

    function testSubDecay() public prank(alice) {
      manifest.purchase{ value: 1e18 }(1e18);
      vm.warp(block.timestamp + 25e16);
      assertEq(manifest.balanceOf(alice), 5e17 / 2);
    }

    function testSubExpires() public prank(alice) {
      manifest.purchase{ value: 1e18 }(1e18);
      vm.warp(block.timestamp + 6e17);
      assertEq(manifest.balanceOf(alice), 0);
      (uint256 tokenId,,,) = manifest.subscriptionOf(alice);
      vm.expectRevert("ERC721: invalid token ID");
      manifest.ownerOf(tokenId);
    }

    function testSpacedPurchase() public {
      purchase(alice, 1e18);
      assertEq(manifest.balanceOf(alice), 5e17);
      vm.warp(block.timestamp + 1e18);
      assertEq(manifest.balanceOf(alice), 0);
      purchase(alice, 1e18);
      assertEq(manifest.balanceOf(alice), 5e17);
    }

    function testCancel() public prank(alice) {
      manifest.purchase{ value: 1e18 }(1e18);
      vm.warp(block.timestamp + 1e17);
      uint256 balance = alice.balance;
      assertEq(manifest.balanceOf(alice), 4e17);
      manifest.cancelSubscription();
      assertEq(manifest.balanceOf(alice), 0);
      assertEq(alice.balance, balance + 8e17);
      vm.expectRevert("NoActiveSubscription");
      manifest.cancelSubscription();
    }

    function testCancelMultiPrice() public {
      purchase(alice, 1e18);
      vm.startPrank(creator);
      manifest.updatePrice(4);
      vm.stopPrank();
      purchase(alice, 1e18);
      assertEq(manifest.balanceOf(alice), 5e17 + 25e16);
    }

    function testCreatorEarnings() public {
      purchase(alice, 1e18);
      purchase(bob, 1e18);
      purchase(charlie, 1e18);
      assertEq(manifest.creatorBalance(), 0);
      vm.warp(block.timestamp + 25e16);
      assertEq(manifest.creatorEarnings(),  15e17);
      vm.warp(block.timestamp + 25e16);
      assertEq(manifest.creatorEarnings(),  3e18);
    }

    function testCreatorWithdraw() public {
      purchase(alice, 1e18);
      purchase(bob, 1e18);
      vm.warp(block.timestamp + 25e16);

      vm.startPrank(creator);
      assertEq(manifest.creatorBalance(),  1e18);
      manifest.withdraw();
      assertEq(manifest.creatorBalance(),  0);
      assertEq(manifest.creatorEarnings(),  1e18);

      vm.expectRevert("No Balance");
      manifest.withdraw();
      vm.stopPrank();

      cancel(alice);
      cancel(bob);

      assertEq(address(manifest).balance,  0);
    }
}
