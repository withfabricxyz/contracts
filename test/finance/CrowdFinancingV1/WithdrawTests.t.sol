// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";

contract WithdrawTests is BaseCampaignTest {
    function testGoalNotMet() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        vm.warp(campaign().expiresAt());
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Fail();
        withdraw(alice);
        assertEq(0, campaign().balanceOf(alice));
        assertTrue(CrowdFinancingV1.State.FAILED == campaign().state());
    }

    function testDoubleWithdraw() public multiTokenTest {
        dealMulti(alice, 1e19);
        deposit(alice, 1e18);
        vm.warp(campaign().expiresAt());
        withdraw(alice);
        vm.expectRevert("No balance");
        withdraw(alice);
    }

    function testEarlyWithdraw() public multiTokenTest {
      dealMulti(alice, 1e19);
      deposit(alice, 1e18);
      vm.expectRevert("Withdraw not allowed");
      withdraw(alice);
    }
}
