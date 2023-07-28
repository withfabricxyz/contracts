// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionNFTV1Test is BaseTest {
    function setUp() public {
        manifest = new SubscriptionNFTV1();

        vm.store(address(manifest), bytes32(uint256(0)), bytes32(0));
        manifest.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, 0, 0, address(0), address(0));

        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testInit() public {
        assertEq(manifest.erc20Address(), address(0));
        assertEq(manifest.timeValue(2), 1);

        vm.store(address(manifest), bytes32(uint256(0)), bytes32(0));

        vm.expectRevert("Owner address cannot be 0x0");
        manifest.initialize("Meow Manifest", "MEOW", "curi", "turi", address(0), 2, 0, 0, address(0), address(0));

        vm.expectRevert("Tokens per second must be > 0");
        manifest.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 0, 0, 0, address(0), address(0));

        vm.expectRevert("Fee bps too high");
        manifest.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, 0, 1500, fees, address(0));

        vm.expectRevert("Fees required when fee recipient is present");
        manifest.initialize("Meow Manifest", "MEOW", "curi", "turi", creator, 2, 0, 0, fees, address(0));
    }

    function testMint() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(alice, 1, 1e18, 1e18 / 2, uint64(block.timestamp + 1e18 / 2));
        manifest.mint{value: 1e18}(1e18);
        assertEq(address(manifest).balance, 1e18);
        assertEq(manifest.balanceOf(alice), 5e17);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
        assertEq(manifest.tokenURI(1), "turi");
    }

    function testMintInvalid() public prank(alice) {
        vm.expectRevert("Purchase amount must match value sent");
        manifest.mint{value: 1e17}(1e18);
    }

    function testMintFor() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(bob, 1, 1e18, 1e18 / 2, block.timestamp + (1e18 / 2));
        manifest.mintFor{value: 1e18}(bob, 1e18);
        assertEq(address(manifest).balance, 1e18);
        assertEq(manifest.balanceOf(bob), 5e17);
        assertEq(manifest.balanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(bob);
        assertEq(manifest.ownerOf(tokenId), bob);
    }

    function testNonSub() public {
        assertEq(manifest.balanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.expectRevert("ERC721: invalid token ID");
        manifest.ownerOf(tokenId);
    }

    function testMintDecay() public prank(alice) {
        manifest.mint{value: 1e18}(1e18);
        vm.warp(block.timestamp + 25e16);
        assertEq(manifest.balanceOf(alice), 5e17 / 2);
        assertEq(manifest.refundableBalanceOf(alice), 5e17 / 2);
    }

    function testMintExpire() public prank(alice) {
        manifest.mint{value: 1e18}(1e18);
        vm.warp(block.timestamp + 6e17);
        assertEq(manifest.balanceOf(alice), 0);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
    }

    function testMintSpaced() public {
        mint(alice, 1e18);
        assertEq(manifest.balanceOf(alice), 5e17);
        vm.warp(block.timestamp + 1e18);
        assertEq(manifest.balanceOf(alice), 0);
        mint(alice, 1e18);
        assertEq(manifest.balanceOf(alice), 5e17);
    }

    function testCreatorEarnings() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        mint(charlie, 1e18);
        assertEq(manifest.creatorBalance(), 3e18);
    }

    function testCreatorWithdraw() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        vm.startPrank(creator);
        assertEq(manifest.creatorBalance(), 2e18);

        vm.expectEmit(true, true, false, true, address(manifest));
        emit CreatorWithdraw(creator, 2e18);
        manifest.withdraw();
        assertEq(manifest.creatorBalance(), 0);
        assertEq(manifest.totalCreatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        manifest.withdraw();
        vm.stopPrank();

        assertEq(address(manifest).balance, 0);
    }

    function testRefund() public {
        mint(alice, 1e18);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionRefund(alice, tokenId, 1e18, 1e18 / 2);
        (creator, 2e18);
        manifest.refund(list(alice));
        assertEq(address(manifest).balance, 0);
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        manifest.refund(list(alice));
    }

    function testPartialRefund() public {
        mint(alice, 1e18);
        vm.warp(block.timestamp + 2.5e17);
        assertEq(5e17 / 2, manifest.refundableBalanceOf(alice));
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionRefund(alice, 1, 5e17, 5e17 / 2);
        manifest.refund(list(alice));
        vm.stopPrank();
    }

    function testRefundNoPurchase() public {
        mint(alice, 1e18);
        uint256 balance = bob.balance;
        vm.startPrank(creator);
        manifest.refund(list(bob));
        vm.stopPrank();
        assertEq(balance, bob.balance);
    }

    function testTransferEarnings() public {
        uint256 aliceBalance = alice.balance;
        mint(alice, 1e18);
        address invalid = address(this);
        vm.startPrank(creator);
        vm.expectRevert("Failed to transfer Ether");
        manifest.withdrawTo(invalid);
        manifest.withdrawTo(alice);
        vm.stopPrank();
        assertEq(aliceBalance, alice.balance);
    }

    function testPausing() public {
        vm.startPrank(creator);
        manifest.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        manifest.mint{value: 1e17}(1e17);
        vm.stopPrank();

        vm.startPrank(creator);
        manifest.unpause();
        vm.stopPrank();

        mint(alice, 1e17);
    }

    /// ERC20

    function testERC20Mint() public erc20 prank(alice) {
        assert(manifest.erc20Address() != address(0));
        assertEq(token().balanceOf(alice), 1e20);
        token().approve(address(manifest), 1e18);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit SubscriptionFunded(alice, 1, 1e18, 1e18 / 2, uint64(block.timestamp + 1e18 / 2));
        manifest.mint(1e18);
        assertEq(token().balanceOf(address(manifest)), 1e18);
        assertEq(manifest.balanceOf(alice), 5e17);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        assertEq(manifest.ownerOf(tokenId), alice);
    }

    function testMintInvalidERC20() public erc20 prank(alice) {
        vm.expectRevert("Native tokens not accepted for ERC20 subscriptions");
        manifest.mint{value: 1e17}(1e18);
        vm.expectRevert("Insufficient Balance or Allowance");
        manifest.mint(1e18);
    }

    function testWithdrawERC20() public erc20 {
        mint(alice, 1e18);
        mint(bob, 1e18);

        uint256 beforeBalance = token().balanceOf(creator);
        vm.startPrank(creator);
        assertEq(manifest.creatorBalance(), 2e18);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit CreatorWithdraw(creator, 2e18);
        manifest.withdraw();
        assertEq(manifest.creatorBalance(), 0);
        assertEq(manifest.totalCreatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        manifest.withdraw();
        vm.stopPrank();

        assertEq(beforeBalance + 2e18, token().balanceOf(creator));
    }

    function testRefundERC20() public erc20 {
        mint(alice, 1e18);
        uint256 beforeBalance = token().balanceOf(alice);
        vm.startPrank(creator);
        manifest.refund(list(alice));
        vm.stopPrank();
        assertEq(beforeBalance + 1e18, token().balanceOf(alice));
    }

    function testRefundERC20AfterWithdraw() public erc20 {
        mint(alice, 1e18);
        vm.startPrank(creator);
        manifest.withdraw();
        vm.expectRevert("Insufficient Balance");
        manifest.refund(list(alice));
        vm.stopPrank();
    }

    function testTransfer() public {
        mint(alice, 1e18);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.startPrank(alice);
        manifest.approve(bob, tokenId);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit Transfer(alice, bob, tokenId);
        manifest.transferFrom(alice, bob, tokenId);
        vm.stopPrank();
        assertEq(manifest.ownerOf(tokenId), bob);
    }

    function testTransferToExistingHolder() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        (uint256 tokenId,,) = manifest.subscriptionOf(alice);
        vm.startPrank(alice);
        manifest.approve(bob, tokenId);
        vm.expectRevert("Cannot transfer to existing subscribers");
        manifest.transferFrom(alice, bob, tokenId);
    }

    function testUpdateMetadata() public {
        mint(alice, 1e18);

        vm.startPrank(creator);
        manifest.updateMetadata("x", "y/");
        assertEq(manifest.contractURI(), "x");
        assertEq(manifest.tokenURI(1), "y/1");

        manifest.updateMetadata("x", "");
        assertEq(manifest.tokenURI(1), "");
        vm.stopPrank();

        vm.expectRevert("Ownable: caller is not the owner");
        manifest.updateMetadata("x", "z");
    }
}
