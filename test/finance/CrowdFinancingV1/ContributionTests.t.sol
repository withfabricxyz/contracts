// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockFeeToken.sol";

contract ContributionTests is BaseCampaignTest {
    function testHappyPath() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        assertEq(1e18, campaign().balanceOf(alice));
    }

    function testDepositEmit() public ethTest prank(alice) {
        dealMulti(alice, 1e19);
        vm.expectEmit(true, true, true, true, address(campaign()));
        emit Contribution(alice, 1e18);
        vm.expectEmit(true, true, true, true, address(campaign()));
        emit Transfer(address(0), alice, 1e18);
        campaign().contributeEth{value: 1e18}();
    }

    function testEarlycontributeEth() public ethTest {
        vm.warp(campaign().startsAt() - 1);
        assertFalse(campaign().isContributionAllowed());
        dealMulti(alice, 1e19);

        vm.startPrank(alice);
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testEarlycontributeERC20() public erc20Test {
        vm.warp(campaign().startsAt() - 1);
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeERC20(1e18);
    }

    function testInvalidERC20Deposit() public ethTest {
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        vm.expectRevert("erc20 only fn called");
        campaign().contributeERC20(1e18);
    }

    function testInvalidETHDeposit() public erc20Test {
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        vm.expectRevert("ETH only fn called");
        campaign().contributeEth{value: 1e18}();
    }

    function testLateDeposit() public ethTest {
        vm.warp(campaign().endsAt() + 1);
        assertFalse(campaign().isContributionAllowed());
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeEth{value: 1e19}();
    }

    function testFailBadBalance() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e19);
    }

    function testBadAllowance() public erc20Test prank(alice) {
        vm.expectRevert("Amount exceeds token allowance");
        campaign().contributeERC20(1e18);
    }

    function testSmallContribution() public ethTest prank(alice) {
        vm.expectRevert("Contribution amount is too low");
        deal(alice, 1e18);
        campaign().contributeEth{value: 1e11}();
    }

    function testDepositRange() public ethTest prank(alice) {
        deal(alice, 2e18);
        (uint256 min, uint256 max) = campaign().contributionRangeFor(alice);
        assertEq(2e17, min);
        assertEq(1e18, max);
        campaign().contributeEth{value: 3e17}();
        (min, max) = campaign().contributionRangeFor(alice);
        assertEq(1, min);
        assertEq(1e18 - 3e17, max);
        campaign().contributeEth{value: 7e17}();
        (min, max) = campaign().contributionRangeFor(alice);
        assertEq(0, min);
        assertEq(0, max);
    }

    function testDepositRangeAdvanced() public ethTest {
        vm.store(address(campaign()), bytes32(uint256(0)), bytes32(0));
        campaign().initialize(
            address(alice),
            1 ether,
            1.25 ether,
            0.2 ether,
            1 ether,
            block.timestamp,
            block.timestamp + expirationFuture,
            address(0),
            address(0),
            0,
            0
        );

        deal(alice, 2e18);
        deal(bob, 2e18);
        deal(charlie, 2e18);

        (uint256 min, uint256 max) = campaign().contributionRangeFor(alice);
        assertEq(0.2 ether, min);
        assertEq(1 ether, max);

        vm.startPrank(alice);
        campaign().contributeEth{value: 1e18}();
        vm.stopPrank();

        vm.startPrank(bob);
        campaign().contributeEth{value: 0.24 ether}();
        vm.stopPrank();

        (min, max) = campaign().contributionRangeFor(alice);
        assertEq(0, min);
        assertEq(0, max);

        (min, max) = campaign().contributionRangeFor(bob);
        assertEq(1, min);
        assertEq(0.01 ether, max);

        // Remaining deposits < min contribution
        (min, max) = campaign().contributionRangeFor(charlie);
        assertEq(0, min);
        assertEq(0, max);

        vm.startPrank(bob);
        campaign().contributeEth{value: 0.01 ether}();
        vm.stopPrank();

        assertTrue(campaign().isGoalMaxMet());
        assertFalse(campaign().isContributionAllowed());
    }

    function testBigThenSmallContribution() public multiTokenTest {
        dealMulti(alice, 1e18);
        deposit(alice, 3e17);
        deposit(alice, 1e5);
        assertEq(3e17 + 1e5, campaign().balanceOf(alice));
    }

    function testHugeDeposit() public ethTest prank(alice) {
        deal(alice, 1e20);
        vm.expectRevert("Contribution amount is too high");
        campaign().contributeEth{value: 1e19}();
    }

    function testBadOutcome() public ethTest {
        fundAndFail();
        vm.startPrank(alice);
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testEarlyGoal() public ethTest {
        fundAndTransferEarly();
        vm.startPrank(alice);
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testTransferredCampaign() public ethTest {
        fundAndTransfer();
        vm.startPrank(alice);
        vm.expectRevert("Contributions are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testTransferFalseReturn() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        dealMulti(alice, 1e18);
        mt.setTransferReturn(false);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        campaign().contributeERC20(1e18);
    }

    function testContributionMinOnFeeTokens() public erc20Test {
        MockFeeToken mt = new MockFeeToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        dealMulti(alice, 1e18);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("Contribution amount is too low");
        campaign().contributeERC20(2e17);
    }

    function testContributionMaxOnFeeTokens() public erc20Test {
        MockFeeToken mt = new MockFeeToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        token().approve(address(campaign()), 5e18);
        // Max contribution is 1e18, fee is 50% on token, so it should pass with 2e18
        campaign().contributeERC20(2e18);
        vm.expectRevert("Contribution amount is too high");
        // Max is tracked cumulatively, so any amount should fail now
        campaign().contributeERC20(2);
    }
}
