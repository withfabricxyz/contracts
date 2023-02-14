// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./mocks/MockToken.sol";
import "./BaseCampaignTest.t.sol";

contract ProcessTests is BaseCampaignTest {
    function testReprocess() public multiTokenTest {
        fundAndTransfer();
        vm.expectRevert("Funds already processed");
        campaign().processFunds();
    }

    function testTooEarly() public multiTokenTest {
        vm.expectRevert("More time/funds required");
        campaign().processFunds();
    }

    function testSuccess() public multiTokenTest {
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Transfer(beneficiary, 1e18 * 3);
        fundAndTransfer();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign().state());
        assertTrue(campaign().withdrawAllowed());
        assertEq(3e18, balance(beneficiary));
    }

    function testEarlySuccess() public multiTokenTest {
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Transfer(beneficiary, 1e18 * 5);
        fundAndTransferEarly();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign().state());
        assertTrue(campaign().withdrawAllowed());
    }

    function testBadOutcome() public multiTokenTest {
        vm.expectEmit(true, false, false, true, address(campaign()));
        emit Fail();
        fundAndFail();
        assertTrue(CrowdFinancingV1.State.FAILED == campaign().state());
        assertTrue(campaign().withdrawAllowed());
    }

    function testUpfrontFees() public multiTokenFeeTest(100, 0) {
        vm.expectEmit(true, true, false, false, address(campaign()));
        emit Transfer(feeCollector, 3e16);

        fundAndTransfer();
        assertEq(3e18 - 3e16, balance(beneficiary));
        assertEq(3e16, balance(feeCollector));
        assertEq(0, address(campaign()).balance);
    }

    function testPayoutFees() public multiTokenFeeTest(0, 250) {
        uint256 preSupply = campaign().totalSupply();
        assertEq(0, campaign().balanceOf(feeCollector));
        fundAndTransfer();
        assertTrue(campaign().totalSupply() > preSupply);
        assertTrue(campaign().balanceOf(feeCollector) > 0);
        yield(1e18);
        assertEq(24390243902439024, campaign().payoutBalance(feeCollector));
    }

    function testAllFees() public multiTokenFeeTest(100, 250) {
        uint256 preSupply = campaign().totalSupply();
        fundAndTransfer();
        assertEq(3e18 - 3e16, balance(beneficiary));
        assertEq(3e16, balance(feeCollector));
        assertTrue(campaign().totalSupply() > preSupply);
    }

    // Coverage of false retrun on free transfer
    function testProcessFailedFeeTransfer() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createFeeCampaign(address(mt), feeCollector, 100, 100));

        dealAll();
        deposit(alice, 1e18);
        deposit(bob, 1e18);
        deposit(charlie, 1e18);
        vm.warp(campaign().expiresAt());

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("ERC20: Fee transfer failed");
        campaign().processFunds();
    }

    // Coverage of false return on transfer
    function testProcessFailedTransfer() public erc20Test {
        MockToken mt = new MockToken("T", "T", 1e21);
        assignCampaign(createCampaign(address(mt)));

        dealAll();
        deposit(alice, 1e18);
        deposit(bob, 1e18);
        deposit(charlie, 1e18);
        vm.warp(campaign().expiresAt());

        mt.setTransferReturn(false);
        vm.startPrank(alice);
        vm.expectRevert("ERC20: Transfer failed");
        campaign().processFunds();
    }
}
