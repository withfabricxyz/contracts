// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionTokenV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionTokenV1FeeTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testAllocation() public withFees {
        (address recipient, uint16 bps) = stp.feeSchedule();

        assertEq(bps, 500);
        assertEq(recipient, fees);
        mint(alice, 1e18);

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = creator.balance;

        vm.expectEmit(true, true, false, true, address(stp));
        emit FeeAllocated(expectedFee);
        withdraw();

        assertEq(creator.balance, balance + (1e18 - expectedFee));
        assertEq(stp.feeBalance(), expectedFee);
    }

    function testFeeTransfer() public withFees {
        mint(alice, 1e18);
        withdraw();

        uint256 expectedFee = (1e18 * 500) / 10000;
        uint256 balance = fees.balance;

        vm.expectEmit(true, true, false, true, address(stp));
        emit FeeTransfer(address(this), fees, expectedFee);
        stp.transferFees();
        assertEq(fees.balance, balance + expectedFee);
        assertEq(stp.feeBalance(), 0);

        vm.expectRevert("No fees to collect");
        stp.transferFees();
    }

    function testWithdrawWithFees() public withFees {
        mint(alice, 1e18);
        mint(bob, 1e18);

        uint256 balance = creator.balance;
        uint256 feeBalance = fees.balance;
        uint256 expectedFee = (2e18 * 500) / 10000;

        vm.expectRevert("Ownable: caller is not the owner");
        stp.withdrawAndTransferFees();

        vm.startPrank(creator);
        stp.withdrawAndTransferFees();
        assertEq(creator.balance, balance + 2e18 - expectedFee);
        assertEq(fees.balance, feeBalance + expectedFee);
        vm.stopPrank();
    }

    function testFeeCollectorUpdate() public withFees {
        vm.startPrank(fees);
        vm.expectEmit(true, true, false, true, address(stp));
        emit FeeCollectorChange(fees, charlie);
        stp.updateFeeRecipient(charlie);
        vm.expectRevert("Unauthorized");
        stp.updateFeeRecipient(charlie);
        vm.stopPrank();
    }

    function testFeeCollectorRelinquish() public withFees {
        mint(alice, 5e18);
        withdraw();

        assertEq(stp.creatorBalance(), 0);

        uint256 expectedFee = (5e18 * 500) / 10000;
        assertEq(stp.feeBalance(), expectedFee);

        vm.startPrank(fees);
        stp.updateFeeRecipient(address(0));
        vm.stopPrank();

        (address recipient, uint16 bps) = stp.feeSchedule();
        assertEq(recipient, address(0));
        assertEq(bps, 0);

        assertEq(stp.feeBalance(), 0);
        assertEq(stp.creatorBalance(), expectedFee);
    }

    function testRenounce() public withFees {
        mint(alice, 1e18);
        withdraw();
        mint(alice, 1e17);

        uint256 balance = fees.balance;
        vm.startPrank(creator);
        stp.renounceOwnership();
        vm.stopPrank();

        assertGt(fees.balance, balance);
        assertEq(stp.feeBalance(), 0);
    }

    function testTransferAll() public withFees {
        mint(alice, 1e18);
        mint(bob, 1e18);

        vm.startPrank(creator);
        stp.setTransferRecipient(creator);
        vm.stopPrank();

        uint256 balance = creator.balance;
        uint256 feeBalance = fees.balance;
        uint256 expectedFee = (2e18 * 500) / 10000;
        stp.transferAllBalances();
        assertEq(creator.balance, balance + 2e18 - expectedFee);
        assertEq(fees.balance, feeBalance + expectedFee);
    }
}
