// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./mocks/MockToken.sol";
import "./BaseCampaignTest.t.sol";

contract TokenizationTests is BaseCampaignTest {
    function setUp() public {
        deal(alice, 1e19);
    }

    function testtransferFeeBipss() public ethTest {
        fundAndTransfer();
        assertEq(campaign().balanceOf(alice), campaign().balanceOf(alice));
        assertEq(3e18, campaign().totalSupply());
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
        assertApproxEqAbs(campaign().yieldBalanceOf(alice), campaign().yieldBalanceOf(newOwner), 1, "Payout balance");
    }

    function testInvalidAllowanceAddresses() public ethTest {
        fundAndTransfer();
        vm.expectRevert("ERC20: approve to the zero address");
        campaign().approve(address(0), 1e18);

        vm.prank(address(0));
        vm.expectRevert("ERC20: approve from the zero address");
        campaign().approve(address(0), 1e18);
    }

    function testInvalidTransferAddresses() public ethTest {
        fundAndTransfer();
        vm.expectRevert("ERC20: transfer to the zero address");
        campaign().transfer(address(0), 1e18);

        vm.prank(address(0));
        vm.expectRevert("ERC20: transfer from the zero address");
        campaign().transfer(bob, 1e18);
    }

    function testInsufficientAllowance() public ethTest {
        fundAndTransfer();

        vm.startPrank(alice);
        campaign().approve(bob, 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        campaign().transferFrom(alice, bob, 2e18);
        vm.stopPrank();
    }

    function testIncreaseDecreaseAllowance() public ethTest {
        fundAndTransfer();
        vm.startPrank(alice);
        campaign().increaseAllowance(bob, 5);
        assertEq(5, campaign().allowance(alice, bob));
        campaign().decreaseAllowance(bob, 5);
        assertEq(0, campaign().allowance(alice, bob));
        vm.expectRevert("ERC20: decreased allowance below zero");
        campaign().decreaseAllowance(bob, 5);
        vm.stopPrank();
    }
}
