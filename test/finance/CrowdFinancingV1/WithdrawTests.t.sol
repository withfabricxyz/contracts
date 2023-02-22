// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";
import "./mocks/MockToken.sol";

contract WithdrawTests is BaseCampaignTest {
    function testGoalNotMet() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        vm.warp(campaign().endsAt());
        vm.expectEmit(true, true, false, true, address(campaign()));
        emit Fail();
        withdraw(alice);
        assertEq(0, campaign().balanceOf(alice));
        assertTrue(CrowdFinancingV1.State.FAILED == campaign().state());
    }

    function testDoubleWithdraw() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        vm.warp(campaign().endsAt());
        withdraw(alice);
        vm.expectRevert("No balance");
        withdraw(alice);
    }

    function testDoublewithdrawYieldBalance() public multiTokenTest {
        fundAndTransfer();
        yield(1e18);
        withdraw(alice);
        vm.expectRevert("No balance");
        withdraw(alice);
        yield(1e18);
        withdraw(alice);
    }

    function testEarlyWithdraw() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        vm.expectRevert("Withdraw not allowed");
        withdraw(alice);
    }

    function testwithdrawYieldBalanceERC20Fail() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        fundAndTransfer();
        yield(1e18);

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("ERC20 transfer failed");
        campaign().withdraw();
        vm.stopPrank();
    }

    function testWithdrawcontributeERC20Fail() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        fundAndFail();

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("ERC20 transfer failed");
        campaign().withdraw();
        vm.stopPrank();
    }
}
