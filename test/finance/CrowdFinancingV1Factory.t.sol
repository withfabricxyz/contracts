// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "./CrowdFinancingV1/BaseCampaignTest.t.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/finance/CrowdFinancingV1Factory.sol";

contract CrowdFinancingV1FactoryTest is BaseCampaignTest {
    CrowdFinancingV1 internal impl;
    CrowdFinancingV1Factory internal factory;

    event Deployment(uint64 nonce, address indexed deployment);
    event FeeScheduleChange(address feeCollector, uint16 upfrontBips, uint16 payoutBips);

    function setUp() public {
        impl = new CrowdFinancingV1();
        factory = new CrowdFinancingV1Factory(address(impl));
        deal(alice, 1e19);
    }

    function testDeployment() public {
        vm.startPrank(alice);
        vm.expectEmit(false, false, false, true, address(factory));
        emit Deployment(1, address(1));

        address deployment = factory.deploy(1, beneficiary, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        uint256 time = block.timestamp;

        CrowdFinancingV1 campaign = CrowdFinancingV1(deployment);
        assertFalse(campaign.withdrawAllowed());
        assertFalse(campaign.fundTargetMet());
        assertEq(0, campaign.depositTotal());
        assertEq(2e17, campaign.minimumDeposit());
        assertEq(1e18, campaign.maximumDeposit());
        assertFalse(campaign.erc20Denominated());
        assertEq(address(0), campaign.tokenAddress());
        assertEq(2e18, campaign.minimumFundTarget());
        assertEq(5e18, campaign.maximumFundTarget());
        assertEq(beneficiary, campaign.beneficiaryAddress());

        assertEq(time, campaign.startsAt());
        assertEq(time + (60 * 60), campaign.expiresAt());
    }

    function testFeeUpdate() public {
        vm.expectEmit(true, false, false, true, address(factory));
        emit FeeScheduleChange(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), 100, 10);

        factory.updateFeeSchedule(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), 100, 10);

        (address addr, uint16 upfront, uint16 payout) = factory.feeSchedule();
        assertEq(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), addr);
        assertEq(100, upfront);
        assertEq(10, payout);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateFeeSchedule(address(alice), 100, 100);
    }
}
