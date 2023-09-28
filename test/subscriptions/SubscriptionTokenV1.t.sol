// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionTokenV1.sol";
import "src/subscriptions/Shared.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";
import "../finance/CrowdFinancingV1/mocks/MockFeeToken.sol";

contract SubscriptionTokenV1Test is BaseTest {
    function setUp() public {
        stp = new SubscriptionTokenV1();

        vm.store(address(stp), bytes32(uint256(0)), bytes32(0));
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 0, 0, 0, address(0), address(0))
        );

        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testInit() public {
        assertEq(stp.erc20Address(), address(0));
        assertEq(stp.timeValue(2), 1);
        assertEq(stp.tps(), 2);
        assertEq(stp.minPurchaseSeconds(), 4);
        assertEq(stp.baseTokenURI(), "turi");

        vm.store(address(stp), bytes32(uint256(0)), bytes32(0));

        vm.expectRevert("Owner address cannot be 0x0");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", address(0), 2, 4, 0, 0, 0, address(0), address(0))
        );

        vm.expectRevert("Tokens per second must be > 0");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 0, 4, 0, 0, 0, address(0), address(0))
        );

        vm.expectRevert("Fee bps too high");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 0, 0, 1500, fees, address(0))
        );

        vm.expectRevert("Fees required when fee recipient is present");
        stp.initialize(Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 0, 0, 0, fees, address(0)));

        vm.expectRevert("Min purchase seconds must be > 0");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 0, 0, 0, 0, address(0), address(0))
        );

        vm.expectRevert("Reward bps too high");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 11_000, 0, 0, address(0), address(0))
        );

        vm.expectRevert("Reward halvings too high");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 500, 33, 0, address(0), address(0))
        );

        vm.expectRevert("Reward halvings too low");
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 4, 500, 0, 0, address(0), address(0))
        );
    }

    function testMint() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(stp));
        emit Purchase(alice, 1, 1e18, 1e18 / 2, 0, block.timestamp + (1e18 / 2));
        stp.mint{value: 1e18}(1e18);
        assertEq(address(stp).balance, 1e18);
        assertEq(stp.balanceOf(alice), 5e17);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        assertEq(stp.ownerOf(tokenId), alice);
        assertEq(stp.tokenURI(1), "turi");
    }

    function testMintInvalid() public prank(alice) {
        vm.expectRevert("Purchase amount must match value sent");
        stp.mint{value: 1e17}(1e18);
    }

    function testMintViaFallback() public prank(alice) {
        (bool sent,) = address(stp).call{value: 1e18}("");
        assertTrue(sent);
    }

    function testMintViaFallbackERC20() public erc20 prank(alice) {
        vm.expectRevert("Native tokens not accepted for ERC20 subscriptions");
        (, bytes memory data) = address(stp).call{value: 1e18}("");
        assertTrue(data.length > 0);
    }

    function testMintFor() public prank(alice) {
        vm.expectEmit(true, true, false, true, address(stp));
        emit Purchase(bob, 1, 1e18, 1e18 / 2, 0, block.timestamp + (1e18 / 2));
        stp.mintFor{value: 1e18}(bob, 1e18);
        assertEq(address(stp).balance, 1e18);
        assertEq(stp.balanceOf(bob), 5e17);
        assertEq(stp.balanceOf(alice), 0);
        (uint256 tokenId,,,) = stp.subscriptionOf(bob);
        assertEq(stp.ownerOf(tokenId), bob);
    }

    function testMintForErc20() public erc20 prank(alice) {
        token().approve(address(stp), 1e18);
        stp.mintFor(bob, 1e18);
        assertEq(token().balanceOf(address(stp)), 1e18);
        assertEq(stp.balanceOf(bob), 5e17);
        assertEq(stp.balanceOf(alice), 0);
        (uint256 tokenId,,,) = stp.subscriptionOf(bob);
        assertEq(stp.ownerOf(tokenId), bob);
    }

    function testNonSub() public {
        assertEq(stp.balanceOf(alice), 0);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        vm.expectRevert("ERC721: invalid token ID");
        stp.ownerOf(tokenId);
    }

    function testMintDecay() public prank(alice) {
        stp.mint{value: 1e18}(1e18);
        vm.warp(block.timestamp + 25e16);
        assertEq(stp.balanceOf(alice), 5e17 / 2);
        assertEq(stp.refundableBalanceOf(alice), 5e17 / 2);
    }

    function testMintExpire() public prank(alice) {
        stp.mint{value: 1e18}(1e18);
        vm.warp(block.timestamp + 6e17);
        assertEq(stp.balanceOf(alice), 0);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        assertEq(stp.ownerOf(tokenId), alice);
    }

    function testMintSpaced() public {
        mint(alice, 1e18);
        assertEq(stp.balanceOf(alice), 5e17);
        vm.warp(block.timestamp + 1e18);
        assertEq(stp.balanceOf(alice), 0);
        mint(alice, 1e18);
        assertEq(stp.balanceOf(alice), 5e17);
    }

    function testCreatorEarnings() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        mint(charlie, 1e18);
        assertEq(stp.creatorBalance(), 3e18);
    }

    function testWithdraw() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        vm.startPrank(creator);
        assertEq(stp.creatorBalance(), 2e18);

        vm.expectEmit(true, true, false, true, address(stp));
        emit Withdraw(creator, 2e18);
        stp.withdraw();
        assertEq(stp.creatorBalance(), 0);
        assertEq(stp.totalCreatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        stp.withdraw();
        vm.stopPrank();

        assertEq(address(stp).balance, 0);
    }

    function testRefund() public {
        mint(alice, 1e18);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Refund(alice, tokenId, 1e18, 1e18 / 2);
        (creator, 2e18);
        stp.refund(0, list(alice));
        assertEq(address(stp).balance, 0);
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        stp.refund(0, list(alice));
    }

    function testPartialRefund() public {
        mint(alice, 1e18);
        vm.warp(block.timestamp + 2.5e17);
        assertEq(5e17 / 2, stp.refundableBalanceOf(alice));
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Refund(alice, 1, 5e17, 5e17 / 2);
        stp.refund(0, list(alice));
        vm.stopPrank();
    }

    function testRefundNoPurchase() public {
        mint(alice, 1e18);
        uint256 balance = bob.balance;
        vm.startPrank(creator);
        stp.refund(0, list(bob));
        vm.stopPrank();
        assertEq(balance, bob.balance);
    }

    function testInvalidRefund() public {
        mint(alice, 1e18);
        vm.startPrank(creator);
        vm.expectRevert("Unexpected value transfer");
        stp.refund{value: 1}(0, list(alice));
        vm.stopPrank();
    }

    ///
    function testRefundCalc() public {
        mint(alice, 1e18);
        assertEq(1e18, stp.refundableTokenBalanceOfAll(list(alice, bob)));
        mint(bob, 1e18);
        assertEq(2e18, stp.refundableTokenBalanceOfAll(list(alice, bob)));
    }

    function testRefundNoBalance() public {
        mint(alice, 1e18);
        withdraw();
        assertFalse(stp.canRefund(list(alice)));
        vm.startPrank(creator);
        vm.expectRevert("Insufficient balance for refund");
        stp.refund(0, list(alice));

        // Send eth to contract while refunding
        vm.expectEmit(true, true, false, true, address(stp));
        emit RefundTopUp(1e18);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Refund(alice, 1, 1e18, 1e18 / 2);
        stp.refund{value: 1e18}(1e18, list(alice));
        assertEq(0, address(stp).balance);
        vm.stopPrank();
    }

    function testTransferEarnings() public {
        uint256 aliceBalance = alice.balance;
        mint(alice, 1e18);
        address invalid = address(this);
        vm.startPrank(creator);
        vm.expectRevert("Failed to transfer Ether");
        stp.withdrawTo(invalid);
        stp.withdrawTo(alice);
        vm.stopPrank();
        assertEq(aliceBalance, alice.balance);
    }

    function testPausing() public {
        vm.startPrank(creator);
        stp.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        stp.mint{value: 1e17}(1e17);
        vm.stopPrank();

        vm.startPrank(creator);
        stp.unpause();
        vm.stopPrank();

        mint(alice, 1e17);
    }

    /// ERC20

    function testERC20Mint() public erc20 prank(alice) {
        assert(stp.erc20Address() != address(0));
        assertEq(token().balanceOf(alice), 1e20);
        token().approve(address(stp), 1e18);
        stp.mint(1e18);
        assertEq(token().balanceOf(address(stp)), 1e18);
        assertEq(stp.balanceOf(alice), 5e17);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        assertEq(stp.ownerOf(tokenId), alice);
    }

    function testMintInvalidERC20() public erc20 prank(alice) {
        vm.expectRevert("Native tokens not accepted for ERC20 subscriptions");
        stp.mint{value: 1e17}(1e18);
        vm.expectRevert("Insufficient Balance or Allowance");
        stp.mint(1e18);
    }

    function testERC20FeeTakingToken() public {
        MockFeeToken _token = new MockFeeToken(
          "FIAT",
          "FIAT",
          1e21
        );
        _token.transfer(alice, 1e20);
        SubscriptionTokenV1 m = new SubscriptionTokenV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        m.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 2, 0, 0, 0, address(0), address(_token))
        );
        vm.startPrank(alice);
        _token.approve(address(m), 1e18);
        m.mint(1e18);
        assertEq(m.balanceOf(alice), 1e18 / 2 / 2);
        vm.stopPrank();
    }

    function testWithdrawERC20() public erc20 {
        mint(alice, 1e18);
        mint(bob, 1e18);

        uint256 beforeBalance = token().balanceOf(creator);
        vm.startPrank(creator);
        assertEq(stp.creatorBalance(), 2e18);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Withdraw(creator, 2e18);
        stp.withdraw();
        assertEq(stp.creatorBalance(), 0);
        assertEq(stp.totalCreatorEarnings(), 2e18);

        vm.expectRevert("No Balance");
        stp.withdraw();
        vm.stopPrank();

        assertEq(beforeBalance + 2e18, token().balanceOf(creator));
    }

    function testRefundERC20() public erc20 {
        mint(alice, 1e18);
        uint256 beforeBalance = token().balanceOf(alice);
        vm.startPrank(creator);
        stp.refund(0, list(alice));
        vm.stopPrank();
        assertEq(beforeBalance + 1e18, token().balanceOf(alice));
    }

    function testRefundERC20AfterWithdraw() public erc20 {
        mint(alice, 1e18);
        vm.startPrank(creator);
        stp.withdraw();
        vm.expectRevert("Insufficient balance for refund");
        stp.refund(0, list(alice));
        vm.stopPrank();
    }

    function testTransfer() public {
        mint(alice, 1e18);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        vm.startPrank(alice);
        stp.approve(bob, tokenId);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Transfer(alice, bob, tokenId);
        stp.transferFrom(alice, bob, tokenId);
        vm.stopPrank();
        assertEq(stp.ownerOf(tokenId), bob);
    }

    function testTransferToExistingHolder() public {
        mint(alice, 1e18);
        mint(bob, 1e18);
        (uint256 tokenId,,,) = stp.subscriptionOf(alice);
        vm.startPrank(alice);
        stp.approve(bob, tokenId);
        vm.expectRevert("Cannot transfer to existing subscribers");
        stp.transferFrom(alice, bob, tokenId);
    }

    function testUpdateMetadata() public {
        mint(alice, 1e18);

        vm.startPrank(creator);
        stp.updateMetadata("x", "y/");
        assertEq(stp.contractURI(), "x");
        assertEq(stp.tokenURI(1), "y/1");

        stp.updateMetadata("x", "");
        assertEq(stp.tokenURI(1), "");
        vm.stopPrank();

        vm.expectRevert("Ownable: caller is not the owner");
        stp.updateMetadata("x", "z");
    }

    function testRenounce() public {
        mint(alice, 1e18);
        withdraw();
        mint(alice, 1e17);

        vm.startPrank(creator);
        stp.renounceOwnership();
        vm.stopPrank();
        assertEq(stp.creatorBalance(), 0);
    }

    function testTransferAll() public {
        mint(alice, 1e18);
        mint(bob, 1e18);

        uint256 balance = charlie.balance;
        vm.expectRevert("Transfer recipient not set");
        stp.transferAllBalances();

        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(stp));
        emit TransferRecipientChange(charlie);
        stp.setTransferRecipient(charlie);
        vm.stopPrank();

        assertEq(charlie, stp.transferRecipient());

        stp.transferAllBalances();

        assertEq(charlie.balance, balance + 2e18);
    }

    /// Reconciation
    function testReconcileEth() public prank(creator) {
        vm.expectRevert("Only for ERC20 tokens");
        stp.reconcileERC20Balance();
    }

    function testReconcile() public erc20 prank(creator) {
        vm.expectRevert("Tokens already reconciled");
        stp.reconcileERC20Balance();

        token().transfer(address(stp), 1e17);
        stp.reconcileERC20Balance();
        assertEq(stp.creatorBalance(), 1e17);
    }

    function testRecoverERC20Self() public erc20 prank(creator) {
        address addr = stp.erc20Address();
        vm.expectRevert("Cannot recover subscription token");
        stp.recoverERC20(addr, alice, 1e17);
    }

    function testRecoverERC20() public prank(creator) {
        ERC20Token token = new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
        token.transfer(address(stp), 1e17);
        stp.recoverERC20(address(token), alice, 1e17);
        assertEq(token.balanceOf(alice), 1e17);
    }

    /// Supply Cap
    function testSupplyCap() public {
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(stp));
        emit SupplyCapChange(1);
        stp.setSupplyCap(1);
        (uint256 count, uint256 supply) = stp.supplyDetail();
        assertEq(supply, 1);
        assertEq(count, 0);
        vm.stopPrank();
        mint(alice, 1e18);

        vm.startPrank(bob);
        vm.expectRevert("Supply cap reached");
        stp.mint{value: 1e18}(1e18);
        vm.stopPrank();

        vm.startPrank(creator);
        stp.setSupplyCap(0);
        vm.stopPrank();

        mint(bob, 1e18);
        vm.startPrank(creator);
        vm.expectRevert("Supply cap must be >= current count or 0");
        stp.setSupplyCap(1);
        vm.stopPrank();
    }
}
