// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./mocks/MockToken.sol";
import "./BaseCampaignTest.t.sol";

contract UnlockTests is BaseCampaignTest {
    function testInProgress() public multiTokenTest {
        assertFalse(campaign().isUnlockAllowed());
        vm.expectRevert("Funds cannot be unlocked");
        campaign().unlockFailedFunds();
    }

    function testSuccess() public multiTokenTest {
        fundAndEnd();
        assertFalse(campaign().isUnlockAllowed());
        vm.warp(campaign().endsAt() + 89 days);
        assertFalse(campaign().isUnlockAllowed());
        vm.warp(campaign().endsAt() + 91 days);
        assertTrue(campaign().isUnlockAllowed());
        assertFalse(campaign().isWithdrawAllowed());

        campaign().unlockFailedFunds();
        assertTrue(campaign().isWithdrawAllowed());
        assertFalse(campaign().isUnlockAllowed());
        assertTrue(CrowdFinancingV1.State.FAILED == campaign().state());
    }

    function testEvents() public multiTokenTest {
        fundAndEnd();
        vm.warp(campaign().endsAt() + 91 days);

        vm.expectEmit(true, true, false, false, address(campaign()));
        emit Fail();
        campaign().unlockFailedFunds();
    }

    function testPostSuccess() public multiTokenTest {
        fundAndTransfer();
        vm.warp(campaign().endsAt() + 91 days);
        assertFalse(campaign().isUnlockAllowed());
    }

    function testPostFail() public multiTokenTest {
        fundAndFail();
        vm.warp(campaign().endsAt() + 91 days);
        // Unlocking is allowed, but withdraw will have the same effect in this case
        assertTrue(campaign().isUnlockAllowed());
        withdraw(alice);
        assertFalse(campaign().isUnlockAllowed());
    }
}
