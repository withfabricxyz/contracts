// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";
import "./mocks/MockToken.sol";

contract DepositTests is BaseCampaignTest {
    function testHappyPath() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        assertEq(1e18, campaign().balanceOf(alice));
    }

    function testDepositEmit() public multiTokenTest {
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Deposit(alice, 1e18);
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
    }

    function testEarlycontributeEth() public ethTest {
        vm.warp(campaign().startsAt() - 1);
        assertFalse(campaign().isContributionAllowed());
        dealMulti(alice, 1e19);

        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testEarlycontributeERC20() public erc20Test {
        vm.warp(campaign().startsAt() - 1);
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("Deposits are not allowed");
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
        vm.expectRevert("Deposits are not allowed");
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
        vm.expectRevert("Deposit amount is too low");
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

    function testBigThenSmallContribution() public multiTokenTest {
        dealMulti(alice, 1e18);
        deposit(alice, 3e17);
        deposit(alice, 1e5);
        assertEq(3e17 + 1e5, campaign().balanceOf(alice));
    }

    function testHugeDeposit() public ethTest prank(alice) {
        deal(alice, 1e20);
        vm.expectRevert("Deposit amount is too high");
        campaign().contributeEth{value: 1e19}();
    }

    function testBadOutcome() public ethTest {
        fundAndFail();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testEarlyGoal() public ethTest {
        fundAndTransferEarly();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testTransferredCampaign() public ethTest {
        fundAndTransfer();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().contributeEth{value: 1e18}();
    }

    function testTransferFalseReturn() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        dealMulti(alice, 1e18);
        mt.setTransferReturn(false);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("ERC20 transfer failed");
        campaign().contributeERC20(1e18);
    }
}
