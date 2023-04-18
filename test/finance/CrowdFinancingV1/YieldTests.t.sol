// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";

contract YieldTests is BaseCampaignTest {
    function testReturns() public multiTokenTest {
        fundAndTransfer();
        yield(1e18);
        uint256 dBalance = balance(alice);
        uint256 pBalance = campaign().yieldBalanceOf(alice);
        assertEq(333333333333333333, pBalance);
        withdraw(alice);
        assertEq(pBalance, balance(alice) - dBalance);
        assertEq(0, campaign().yieldBalanceOf(alice));
    }

    function testProfit() public multiTokenTest {
        fundAndTransfer();
        dealDenomination(recipient, 1e20);
        yield(1e19);
        assertEq(3333333333333333333, campaign().yieldBalanceOf(alice));
        assertEq(3333333333333333333 - 1e18, campaign().yieldTotalOf(alice));
    }

    function testMulti() public multiTokenTest {
        fundAndTransfer();
        yield(1e18);

        uint256 dBalance = balance(alice);
        withdraw(alice);
        yield(1e18);
        withdraw(alice);

        assertEq(2e18, campaign().yieldTotal());
        assertEq(666666666666666666, balance(alice) - dBalance);
        assertEq(0, campaign().yieldBalanceOf(alice));
        assertEq(666666666666666666, campaign().yieldBalanceOf(bob));
    }

    function testYieldFees() public multiTokenFeeTest(0, 500) {
        fundAndTransfer();
        yield(1e18);
        assertEq(0, balance(feeCollector));
        withdraw(feeCollector);
        // ~5% fee
        assertApproxEqAbs(50000000000000000, balance(feeCollector), 1);
        assertEq(0, campaign().yieldBalanceOf(feeCollector));
    }
}
