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
        deal(charlie, 1e19);
        deal(doug, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        stp = createETHSub(2592000, 0, 500);
    }

    function testDecay() public {
        uint256 halvings = 6;
        for (uint256 i = 0; i < halvings; i++) {
            vm.warp((stp.minPurchaseSeconds() * i) + 1);
            assertEq(stp.rewardMultiplier(), (2 ** (halvings - i)));
        }
    }

    function testRewardPointAllocation() public {
        mint(alice, 1e18);
        (,, uint256 points,) = stp.subscriptionOf(alice);
        assertEq(stp.rewardMultiplier(), 64);
        assertEq(points, 1e18 * 64);
        assertEq(stp.totalRewardPoints(), 1e18 * 64);
    }

    function testRewardPointWithdraw() public {
        mint(alice, 1e18);
        uint256 preBalance = creator.balance;
        withdraw();
        assertEq(preBalance + 1e18 - ((1e18 * 500) / 10_000), creator.balance);
        vm.startPrank(alice);
        preBalance = alice.balance;
        assertEq((1e18 * 500) / 10_000, stp.rewardBalanceOf(alice));
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardWithdraw(alice, (1e18 * 500) / 10_000);
        stp.withdrawRewards();
        assertEq(preBalance + (1e18 * 500) / 10_000, alice.balance);
        assertEq(0, stp.rewardBalanceOf(alice));
        vm.expectRevert("No rewards to withdraw");
        stp.withdrawRewards();
        vm.stopPrank();

        mint(bob, 1e18);
        withdraw();
        assertEq((1e18 * 500) / 10_000, stp.rewardBalanceOf(bob));
        assertEq(0, stp.rewardBalanceOf(alice));

        mint(charlie, 1e18);
        withdraw();
        assertEq((1e18 * 500) / 10_000, stp.rewardBalanceOf(bob));
        assertEq((1e18 * 500) / 10_000, stp.rewardBalanceOf(charlie));
        assertEq(0, stp.rewardBalanceOf(alice));
    }

    function testRewardPointWithdrawStepped() public {
        mint(alice, 1e18);
        vm.warp(31 days);
        mint(bob, 1e18);
        vm.warp(61 days);
        mint(charlie, 1e18);
        vm.warp(91 days);
        mint(doug, 1e18);

        withdraw();
        uint256 totalPool = (4e18 * 500) / 10_000;

        assertEq((totalPool * 64) / (64 + 32 + 16 + 8), stp.rewardBalanceOf(alice));
        assertEq((totalPool * 32) / (64 + 32 + 16 + 8), stp.rewardBalanceOf(bob));
        assertEq((totalPool * 16) / (64 + 32 + 16 + 8), stp.rewardBalanceOf(charlie));
        assertEq((totalPool * 8) / (64 + 32 + 16 + 8), stp.rewardBalanceOf(doug));

        vm.startPrank(alice);
        stp.withdrawRewards();
        vm.stopPrank();
        assertEq(0, stp.rewardBalanceOf(alice));

        mint(doug, 1e18);
        withdraw();

        uint256 withdrawn = (totalPool * 64) / (64 + 32 + 16 + 8);
        totalPool = (5e18 * 500) / 10_000;
        assertEq((totalPool * 64) / (64 + 32 + 16 + 8 + 8) - withdrawn, stp.rewardBalanceOf(alice));

        vm.startPrank(alice);
        stp.withdrawRewards();
        vm.stopPrank();
    }
}
