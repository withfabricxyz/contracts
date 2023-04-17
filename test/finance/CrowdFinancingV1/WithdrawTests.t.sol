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
        assertTrue(CrowdFinancingV1.State.FUNDING == campaign().state());
        uint256 supply = campaign().totalSupply();
        vm.expectEmit(true, true, true, true, address(campaign()));
        emit Fail();
        vm.expectEmit(true, true, true, true, address(campaign()));
        emit Withdraw(address(alice), 1e18);
        vm.expectEmit(true, true, true, true, address(campaign()));
        emit Transfer(alice, address(0), 1e18);
        withdraw(alice);
        assertEq(0, campaign().balanceOf(alice));
        assertEq(supply - 1e18, campaign().totalSupply());
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

    function testDoubleWithdrawYieldBalance() public multiTokenTest {
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

    function testWithdrawYieldBalanceERC20Fail() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        fundAndTransfer();
        yield(1e18);

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        campaign().withdraw();
        vm.stopPrank();
    }

    function testWithdrawContributeERC20Fail() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        fundAndFail();

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        campaign().withdraw();
        vm.stopPrank();
    }

    function testWithdrawContributionEthFail() public ethTest {
        deposit(address(this), 2e17);
        fundAndFail();

        vm.expectRevert("Failed to transfer Ether");
        campaign().withdraw();
    }

    function testWithdrawYieldEthFail() public ethTest {
        deposit(address(this), 2e17);
        fundAndTransfer();
        yield(1e18);

        vm.expectRevert("Failed to transfer Ether");
        campaign().withdraw();
    }
}
