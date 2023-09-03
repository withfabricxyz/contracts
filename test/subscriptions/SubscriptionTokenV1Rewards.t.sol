// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionTokenV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionTokenV1RewardsTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        stp = createETHSub(1, 0);
    }

    function testDecay() public {
        assertEq(stp.rewardMultiplier(), 64);
        vm.warp(31 days);
        assertEq(stp.rewardMultiplier(), 32);
        vm.warp(61 days);
        assertEq(stp.rewardMultiplier(), 16);
        vm.warp(91 days);
        assertEq(stp.rewardMultiplier(), 8);
        vm.warp(121 days);
        assertEq(stp.rewardMultiplier(), 4);
        vm.warp(151 days);
        assertEq(stp.rewardMultiplier(), 2);
        vm.warp(181 days);
        assertEq(stp.rewardMultiplier(), 1);
        vm.warp(211 days);
        assertEq(stp.rewardMultiplier(), 1);
        vm.warp(365 * 100 days);
        assertEq(stp.rewardMultiplier(), 1);
    }

    function testRewardPointAllocation() public {
        mint(alice, 1e18);
        (,, uint256 points,) = stp.subscriptionOf(alice);
        assertEq(stp.rewardMultiplier(), 64);
        assertEq(points, 1e18 * 64);
    }
}
