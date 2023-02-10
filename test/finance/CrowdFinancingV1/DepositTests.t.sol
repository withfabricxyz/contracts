// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";

contract DepositTests is BaseCampaignTest {

    function testHappyPath() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        assertEq(1e18, campaign().balanceOf(alice));
        assertEq(1_000_000, campaign().ownershipPPM(alice));
    }

    function testDepositEmit() public multiTokenTest {
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Deposit(alice, 1e18);
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
    }

    function testEarlyDepositEth() public ethTest {
        vm.warp(campaign().startsAt() - 1);
        assertFalse(campaign().depositAllowed());
        dealMulti(alice, 1e19);

        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().depositEth{ value: 1e18 }();
    }

    function testEarlyDepositErc20() public erc20Test {
        vm.warp(campaign().startsAt() - 1);
        dealMulti(alice, 1e19);
        vm.startPrank(alice);
        token().approve(address(campaign()), 1e18);
        vm.expectRevert("Deposits are not allowed");
        campaign().depositTokens(1e18);
    }

    function testInvalidERC20Deposit() public ethTest {
      dealMulti(alice, 1e19);
      vm.startPrank(alice);
      vm.expectRevert("erc20 only fn called");
      campaign().depositTokens(1e18);
    }

    function testInvalidETHDeposit() public erc20Test {
      dealMulti(alice, 1e19);
      vm.startPrank(alice);
      vm.expectRevert("ETH only fn called");
      campaign().depositEth{ value: 1e18 }();
    }

    function testLateDeposit() public ethTest {
        vm.warp(campaign().expiresAt() + 1);
        assertFalse(campaign().depositAllowed());
        vm.expectRevert("Deposits are not allowed");
        campaign().depositEth{value: 1e19}();
    }

    function testFailBadBalance() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e19);
    }

    function testBadAllowance() public erc20Test prank(alice) {
        vm.expectRevert("Amount exceeds token allowance");
        campaign().depositTokens(1e18);
    }

    function testSmallContribution() public ethTest prank(alice) {
        vm.expectRevert("Deposit amount is too low");
        deal(alice, 1e18);
        campaign().depositEth{ value: 1e11 }();
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
        campaign().depositEth{value: 1e19}();
    }

    function testBadOutcome() public ethTest {
        fundAndFail();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().depositEth{value: 1e18}();
    }

    function testEarlyGoal() public ethTest {
        fundAndTransferEarly();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().depositEth{value: 1e18}();
    }

    function testTransferredCampaign() public ethTest {
        fundAndTransfer();
        vm.startPrank(alice);
        vm.expectRevert("Deposits are not allowed");
        campaign().depositEth{value: 1e18}();
    }
}
