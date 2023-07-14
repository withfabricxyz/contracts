// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionNFTV1Test is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testAllocation() public withFees {
        assertEq(manifest.feeBps(), 500);
        assertEq(manifest.feeRecipient(), fees);
        purchase(alice, 1e18);

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = creator.balance;
        withdraw();

        assertEq(creator.balance, balance + (1e18 - expectedFee));
        assertEq(manifest.feeBalance(), expectedFee);
    }

    function testFeeTransfer() public withFees {
        purchase(alice, 1e18);
        withdraw();

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = fees.balance;

        manifest.transferFees();
        assertEq(fees.balance, balance + expectedFee);
        assertEq(manifest.feeBalance(), 0);

        vm.expectRevert("No fees to collect");
        manifest.transferFees();
    }

}
