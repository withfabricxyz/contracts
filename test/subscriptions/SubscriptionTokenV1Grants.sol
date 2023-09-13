// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionTokenV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionTokenV1GrantsTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        stp = createETHSub(1, 0, 0);
    }

    function testGrant() public {
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Grant(alice, 1, 1e15, block.timestamp + 1e15);
        stp.grantTime(list(alice), 1e15);
        vm.stopPrank();
        assertEq(stp.balanceOf(alice), 1e15);
        assertEq(stp.refundableBalanceOf(alice), 0);
    }

    function testGrantDouble() public {
        vm.startPrank(creator);
        stp.grantTime(list(alice), 1e15);
        vm.warp(block.timestamp + 1e16);
        stp.grantTime(list(alice), 1e15);
        vm.stopPrank();
        assertEq(stp.balanceOf(alice), 1e15);
        assertEq(stp.refundableBalanceOf(alice), 0);
    }

    function testGrantMixed() public {
        vm.startPrank(creator);
        stp.grantTime(list(alice), 1e15);
        vm.stopPrank();
        mint(alice, 1e18);
        assertEq(stp.balanceOf(alice), 1e15 + 1e18 / 2);
        assertEq(stp.refundableBalanceOf(alice), 1e18 / 2);
    }

    function testGrantRefund() public {
        vm.startPrank(creator);
        stp.grantTime(list(alice), 1e15);
        stp.refund(0, list(alice));
        vm.stopPrank();
        assertEq(stp.balanceOf(alice), 0);
    }

    function testGrantRefundMixed() public {
        mint(alice, 1e18);
        vm.startPrank(creator);
        stp.grantTime(list(alice), 1e15);
        stp.refund(0, list(alice));
        vm.stopPrank();
        assertEq(stp.balanceOf(alice), 0);
    }
}
