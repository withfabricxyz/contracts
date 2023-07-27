// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./mocks/MockToken.sol";
import "./BaseCampaignTest.t.sol";

contract TransferTests is BaseCampaignTest {
    function testReprocess() public multiTokenTest {
        fundAndTransfer();
        vm.expectRevert("Transfer not allowed");
        campaign().transferBalanceToRecipient();
    }

    function testTooEarly() public multiTokenTest {
        vm.expectRevert("Transfer not allowed");
        campaign().transferBalanceToRecipient();
    }

    function testSuccess() public multiTokenTest {
        fundAndEnd();
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit TransferContributions(recipient, 1e18 * 3);
        campaign().transferBalanceToRecipient();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign().state());
        assertTrue(campaign().isWithdrawAllowed());
        assertEq(3e18, balance(recipient));
    }

    function testEarlySuccess() public multiTokenTest {
        fullyFund();
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit TransferContributions(recipient, 1e18 * 5);
        campaign().transferBalanceToRecipient();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign().state());
        assertTrue(campaign().isWithdrawAllowed());
    }

    function testBadOutcome() public multiTokenTest {
        fundAndFail();
        assertFalse(campaign().isTransferAllowed());
    }

    function testUpfrontFees() public multiTokenFeeTest(100, 0) {
        fundAndEnd();
        vm.expectEmit(true, true, false, false, address(campaign()));
        emit TransferContributions(feeCollector, 3e16);
        campaign().transferBalanceToRecipient();
        assertEq(3e18 - 3e16, balance(recipient));
        assertEq(3e16, balance(feeCollector));
        assertEq(0, address(campaign()).balance);
    }

    function testYieldFees() public multiTokenFeeTest(0, 250) {
        uint256 preSupply = campaign().totalSupply();
        assertEq(0, campaign().balanceOf(feeCollector));
        fundAndTransfer();
        assertTrue(campaign().totalSupply() > preSupply);
        assertTrue(campaign().balanceOf(feeCollector) > 0);
        // Dilution such that feeCollector has ~2.5% of tokens
        assertEq(76923076923076923, campaign().balanceOf(feeCollector));
        assertApproxEqAbs(250, (campaign().balanceOf(feeCollector) * 10_000) / campaign().totalSupply(), 1);
    }

    function testAllFees() public multiTokenFeeTest(100, 250) {
        uint256 preSupply = campaign().totalSupply();
        fundAndTransfer();
        assertEq(3e18 - 3e16, balance(recipient));
        assertEq(3e16, balance(feeCollector));
        assertTrue(campaign().totalSupply() > preSupply);
    }

    // Coverage of false return on fee transfer
    function testProcessFailedFeeTransfer() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createFeeCampaign(address(mt), feeCollector, 100, 100));
        fundAndEnd();

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        campaign().transferBalanceToRecipient();
    }

    // Coverage of false return on transfer
    function testTransferFailedTransfer() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));
        fundAndEnd();

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        campaign().transferBalanceToRecipient();
    }

    function testTransferEthFailedFeeTransfer() public ethTest {
        assignCampaign(createFeeCampaign(address(0), address(this), 100, 100));
        fundAndEnd();

        vm.startPrank(alice);
        vm.expectRevert("Failed to transfer Ether");
        campaign().transferBalanceToRecipient();
    }

    // Coverage of false return on transfer
    function testProcessFailedTransfer() public erc20Test {
        assignCampaign(createConfiguredCampaign(address(this), address(0), address(0), 0, 0));
        fundAndEnd();

        vm.startPrank(alice);
        vm.expectRevert("Failed to transfer Ether");
        campaign().transferBalanceToRecipient();
    }
}
