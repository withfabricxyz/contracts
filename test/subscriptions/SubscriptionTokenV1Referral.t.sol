// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionTokenV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionTokenV1ReferralTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        stp = createETHSub(1, 0);
    }

    function testCreate() public prank(creator) {
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardCreated(1, 500, 500);
        stp.createReferralCode(1, 500, 500);
        (uint16 min, uint16 max) = stp.referralRewards(1);
        assertEq(min, 500);
        assertEq(max, 500);
    }

    function testCreateInvalid() public prank(creator) {
        vm.expectRevert("minBps > maxBps");
        stp.createReferralCode(1, 600, 500);
        vm.expectRevert("maxBps too high");
        stp.createReferralCode(1, 600, 11000);
        stp.createReferralCode(1, 500, 500);
        vm.expectRevert("Referral code exists");
        stp.createReferralCode(1, 500, 500);
    }

    function testDelete() public prank(creator) {
        stp.createReferralCode(1, 500, 500);
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardDestroyed(1);
        stp.deleteReferralCode(1);
        (uint16 min, uint16 max) = stp.referralRewards(1);
        assertEq(min, 0);
        assertEq(max, 0);
    }

    function testInvalidReferralCode() public {
        uint256 balance = charlie.balance;
        vm.startPrank(alice);
        stp.mintWithReferral{value: 1e17}(1e17, 1, charlie);
        vm.stopPrank();
        assertEq(charlie.balance, balance);
    }

    function testRewards() public {
        vm.startPrank(creator);
        stp.createReferralCode(1, 500, 500);
        vm.stopPrank();

        uint256 balance = charlie.balance;
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(stp));
        emit Reward(1, charlie, 1, 5e15);
        stp.mintWithReferral{value: 1e17}(1e17, 1, charlie);
        vm.stopPrank();
        assertEq(charlie.balance, balance + 5e15);
        assertEq(address(stp).balance, 1e17 - 5e15);
    }

    function testRewardsMintFor() public {
        uint256 balance = charlie.balance;
        vm.startPrank(alice);
        stp.mintWithReferralFor{value: 1e17}(bob, 1e17, 1, charlie);
        vm.stopPrank();
        assertEq(charlie.balance, balance);
    }

    function testRewardsErc20() public erc20 {
        vm.startPrank(creator);
        stp.createReferralCode(1, 500, 500);
        vm.stopPrank();

        uint256 balance = token().balanceOf(charlie);
        vm.startPrank(alice);
        token().approve(address(stp), 1e17);
        stp.mintWithReferral(1e17, 1, charlie);
        vm.stopPrank();
        assertEq(token().balanceOf(charlie), balance + 5e15);
    }

    function testVariableRewards() public {
        vm.startPrank(creator);
        stp.createReferralCode(1, 1000, 2000);
        vm.stopPrank();

        uint256 balance = charlie.balance;
        vm.startPrank(alice);
        stp.mintWithReferral{value: 1e17}(1e17, 1, charlie);
        vm.stopPrank();
        assertTrue(charlie.balance >= balance + 10e15 && charlie.balance <= balance + 20e15);
    }

    function testFuzzVariableRewards(uint16 min, uint16 max) public {
        vm.assume(max <= 10_000);
        vm.assume(min <= max);

        vm.startPrank(creator);
        stp.createReferralCode(1, min, max);
        vm.stopPrank();

        uint256 balance = charlie.balance;
        vm.startPrank(alice);
        stp.mintWithReferral{value: 1e17}(1e17, 1, charlie);
        vm.stopPrank();

        uint256 minValue = uint256(min) * 1e13;
        uint256 maxValue = uint256(max) * 1e13;

        assertTrue(charlie.balance >= balance + minValue);
        assertTrue(charlie.balance <= balance + maxValue);
    }
}
