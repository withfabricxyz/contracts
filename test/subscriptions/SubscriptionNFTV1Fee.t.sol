// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionNFTV1FeeTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testAllocation() public withFees {
        (address recipient, uint16 bps) = manifest.feeSchedule();

        assertEq(bps, 500);
        assertEq(recipient, fees);
        mint(alice, 1e18);

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = creator.balance;
        withdraw();

        assertEq(creator.balance, balance + (1e18 - expectedFee));
        assertEq(manifest.feeBalance(), expectedFee);
    }

    function testFeeTransfer() public withFees {
        mint(alice, 1e18);
        withdraw();

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = fees.balance;

        vm.expectEmit(true, true, false, true, address(manifest));
        emit FeeRecipientTransfer(address(this), fees, expectedFee);
        manifest.transferFees();
        assertEq(fees.balance, balance + expectedFee);
        assertEq(manifest.feeBalance(), 0);

        vm.expectRevert("No fees to collect");
        manifest.transferFees();
    }

    function testFeeCollectorUpdate() public withFees {
        vm.startPrank(fees);
        vm.expectEmit(true, true, false, true, address(manifest));
        emit FeeRecipientChange(fees, charlie);
        manifest.updateFeeRecipient(charlie);
        vm.expectRevert("Unauthorized");
        manifest.updateFeeRecipient(charlie);
        vm.stopPrank();
    }
}
