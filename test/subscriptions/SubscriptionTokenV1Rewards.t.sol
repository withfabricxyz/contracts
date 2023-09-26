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

    function testSingleHalving() public {
        SubscriptionTokenV1 m = new SubscriptionTokenV1();
        vm.store(address(m), bytes32(uint256(0)), bytes32(0));
        m.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 10, 500, 1, 0, address(0), address(0))
        );
        assertEq(m.rewardMultiplier(), 2);
        vm.warp(block.timestamp + 11);
        assertEq(m.rewardMultiplier(), 1);
        vm.warp(block.timestamp + 21);
        assertEq(m.rewardMultiplier(), 0);
    }

    function testDecay() public {
        uint256 halvings = 6;
        for (uint256 i = 0; i <= halvings; i++) {
            vm.warp((stp.minPurchaseSeconds() * i) + 1);
            assertEq(stp.rewardMultiplier(), (2 ** (halvings - i)));
        }
        vm.warp((stp.minPurchaseSeconds() * 7) + 1);
        assertEq(stp.rewardMultiplier(), 0);
    }

    function testRewardPointAllocation() public {
        mint(alice, 1e18);
        (,, uint256 points,) = stp.subscriptionOf(alice);
        assertEq(stp.rewardMultiplier(), 64);
        assertEq(points, 1e18 * 64);
        assertEq(stp.totalRewardPoints(), 1e18 * 64);
    }

    function testDisabledWithdraw() public {
        stp = createETHSub(2592000, 0, 0);
        mint(alice, 1e18);
        withdraw();
        assertEq(0, stp.rewardBalanceOf(alice));
        vm.startPrank(alice);
        vm.expectRevert("No rewards to withdraw");
        stp.withdrawRewards();
        vm.stopPrank();
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
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardsAllocated(1e18 * 500 / 10_000);
        withdraw();

        uint256 withdrawn = (totalPool * 64) / (64 + 32 + 16 + 8);
        totalPool = (5e18 * 500) / 10_000;
        assertEq((totalPool * 64) / (64 + 32 + 16 + 8 + 8) - withdrawn, stp.rewardBalanceOf(alice));

        vm.startPrank(alice);
        stp.withdrawRewards();
        vm.stopPrank();
    }

    function testWithdrawExpired() public {
        mint(alice, 2592000 * 2);
        vm.warp(60 days);
        withdraw();
        vm.startPrank(alice);
        vm.expectRevert("Subscription not active");
        stp.withdrawRewards();
        vm.stopPrank();
    }

    function testSlashingNoRewards() public {
        vm.store(address(stp), bytes32(uint256(0)), bytes32(0));
        stp.initialize(
            Shared.InitParams("Meow Sub", "MEOW", "curi", "turi", creator, 2, 10, 0, 1, 0, address(0), address(0))
        );

        mint(alice, 2592000 * 2);
        mint(bob, 1e8);

        vm.warp(2592000 * 3);
        vm.startPrank(bob);
        vm.expectRevert("Rewards disabled");
        stp.slashRewards(alice);
        vm.stopPrank();
    }

    function testSlashing() public {
        mint(alice, 2592000 * 2);
        mint(bob, 1e8);

        uint256 beforePoints = stp.totalRewardPoints();
        (,, uint256 alicePoints,) = stp.subscriptionOf(alice);

        vm.warp(2592000 * 3);
        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPointsSlashed(alice, bob, alicePoints);
        stp.slashRewards(alice);
        vm.stopPrank();

        uint256 afterPoints = stp.totalRewardPoints();
        (,, uint256 aliceAfterPoints,) = stp.subscriptionOf(alice);

        assertEq(0, aliceAfterPoints);
        assertEq(afterPoints, beforePoints - alicePoints);
    }

    function testSlashingPartial() public {
        mint(alice, 2592000 * 2);
        mint(bob, 1e8);

        uint256 beforePoints = stp.totalRewardPoints();
        (,, uint256 alicePoints, uint256 expires) = stp.subscriptionOf(alice);

        // 50% slash
        uint256 warpTo = expires + (stp.balanceOf(alice) / 2);
        vm.warp(warpTo);
        vm.startPrank(bob);
        stp.slashRewards(alice);
        vm.stopPrank();

        uint256 afterPoints = stp.totalRewardPoints();
        (,, uint256 aliceAfterPoints,) = stp.subscriptionOf(alice);

        assertEq(alicePoints / 2, aliceAfterPoints);
        assertEq(afterPoints, beforePoints - (alicePoints / 2));
    }

    function testSlashingWithdraws() public {
        mint(alice, 2592000 * 2);
        vm.warp((stp.minPurchaseSeconds() * 3) + 1);
        mint(bob, 1e8);

        // Allocate rewards
        withdraw();
        vm.startPrank(bob);
        stp.withdrawRewards();
        assertEq(stp.rewardBalanceOf(bob), 0);
        stp.slashRewards(alice);
        assertEq(stp.rewardBalanceOf(bob), stp.rewardPoolBalance());
        stp.withdrawRewards();
        vm.stopPrank();
    }

    function testDoubleSlash() public {
        mint(alice, 2592000 * 2);
        vm.warp((stp.minPurchaseSeconds() * 3) + 1);
        mint(bob, 1e8);
        withdraw();
        vm.startPrank(bob);
        stp.slashRewards(alice);
        vm.expectRevert("Not slashable");
        stp.slashRewards(alice);
        vm.warp((stp.minPurchaseSeconds() * 4) + 1);
        vm.expectRevert("No reward points to slash");
        stp.slashRewards(alice);
        vm.stopPrank();
    }

    function testSlashingActive() public {
        mint(alice, 2592000 * 2);
        mint(bob, 1e8);
        vm.startPrank(alice);
        vm.expectRevert("Not slashable");
        stp.slashRewards(alice);
        vm.warp(60 days);
        vm.expectRevert("Subscription not active");
        stp.slashRewards(alice);
        vm.stopPrank();
    }
}
