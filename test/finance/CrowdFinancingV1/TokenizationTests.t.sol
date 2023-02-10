// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";

contract TokenizationTests is BaseCampaignTest {

    function setUp() public {
        deal(alice, 1e19);
    }

    function testTokenBalances() public ethTest {
        fundAndTransfer();
        assertEq(campaign().depositedAmount(alice), campaign().balanceOf(alice));
        assertEq(campaign().depositTotal(), campaign().totalSupply());
    }

    function testTokenTransfer() public ethTest {
        fundAndTransfer();
        uint256 balance = campaign().balanceOf(alice);
        vm.startPrank(alice);
        campaign().transfer(broke, 10);
        assertEq(10, campaign().balanceOf(broke));
        assertEq(balance - 10, campaign().balanceOf(alice));
    }

    function testTokenAllowanceAndApproval() public {
        fundAndTransfer();
        address owner = alice;
        address spender = bob;

        uint256 oBalance = campaign().balanceOf(owner);
        uint256 sBalance = campaign().balanceOf(spender);

        vm.startPrank(owner);
        campaign().approve(spender, 1e20);
        assertEq(1e20, campaign().allowance(owner, spender));
        vm.stopPrank();

        vm.startPrank(spender);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        campaign().transferFrom(owner, spender, 1e20);
        campaign().transferFrom(owner, spender, oBalance);

        assertEq(oBalance + sBalance, campaign().balanceOf(spender));
        assertEq(0, campaign().balanceOf(owner));
        assertEq(1e20 - oBalance, campaign().allowance(owner, spender));
    }

    function testPayoutRecalculation() public {
        fundAndTransfer();
        yield(1e18);

        address newOwner = broke;

        vm.startPrank(alice);
        campaign().withdraw();
        vm.stopPrank();

        uint256 withdraws = campaign().withdrawsOf(alice);

        yield(1e18);
        vm.startPrank(alice);
        campaign().transfer(newOwner, campaign().balanceOf(alice) / 2);

        assertEq(withdraws, campaign().withdrawsOf(alice) + campaign().withdrawsOf(newOwner), "Split roughly");
        assertApproxEqAbs(campaign().withdrawsOf(alice), campaign().withdrawsOf(newOwner), 1, "Equal withdraws");
        assertApproxEqAbs(campaign().payoutBalance(alice), campaign().payoutBalance(newOwner), 1, "Payout balance");
    }
}
