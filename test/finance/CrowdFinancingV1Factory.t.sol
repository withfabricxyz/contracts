// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "./CrowdFinancingV1/BaseCampaignTest.t.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/finance/CrowdFinancingV1Factory.sol";

contract CrowdFinancingV1FactoryTest is BaseCampaignTest {
    event Deployment(address indexed deployment);
    event FeeScheduleChange(address feeCollector, uint16 upfrontBips, uint16 payoutBips, uint256 deployFee);
    event DeployFeeChange(uint256 fee);
    event DeployFeeTransfer(address indexed recipient, uint256 fee);

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
        emit Deployment(address(1));

        address deployment = factory.deployCampaign(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        uint256 time = block.timestamp;

        CrowdFinancingV1 campaign = CrowdFinancingV1(deployment);
        assertFalse(campaign.isWithdrawAllowed());
        assertFalse(campaign.isGoalMinMet());
        assertEq(0, campaign.totalSupply());
        assertEq(2e17, campaign.minAllowedContribution());
        assertEq(1e18, campaign.maxAllowedContribution());
        assertTrue(campaign.isEthDenominated());
        assertEq(address(0), campaign.erc20Address());
        assertEq(2e18, campaign.goalMin());
        assertEq(5e18, campaign.goalMax());
        assertEq(recipient, campaign.recipientAddress());

        assertEq(time, campaign.startsAt());
        assertEq(time + (60 * 60), campaign.endsAt());
    }

    function testFeeUpdate() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit FeeScheduleChange(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), 100, 10);
        factory.updateFeeSchedule(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), 100, 10);

        (address addr, uint16 upfront, uint16 payout, uint256 deploy) = factory.feeSchedule();
        assertEq(address(0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87), addr);
        assertEq(100, upfront);
        assertEq(10, payout);
        assertEq(0, deploy);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateFeeSchedule(address(alice), 100, 100);
    }

    function testDeployFeeUpdate() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit DeployFeeChange(1e12);
        factory.updateMinimumDeployFee(1e12);

        (address addr, uint16 upfront, uint16 payout, uint256 deploy) = factory.feeSchedule();
        assertEq(address(0), addr);
        assertEq(0, upfront);
        assertEq(0, payout);
        assertEq(1e12, deploy);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateMinimumDeployFee(1e12);
    }

    function testDeployFeeTooLow() public {
        factory.updateMinimumDeployFee(1e12);
        vm.expectRevert("Insufficient ETH to deploy");
        factory.deployCampaign(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
    }

    function testDeployFeeCollectNone() public {
        vm.expectRevert("No fees to collect");
        factory.transferDeployFees(alice);
    }

    function testDeployFeeCapture() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deployCampaign{value: 1e12}(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        assertEq(1e12, address(factory).balance);
    }

    function testDeployFeeTransfer() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deployCampaign{value: 1e12}(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        vm.expectEmit(true, true, true, true, address(factory));
        emit DeployFeeTransfer(alice, 1e12);
        uint256 beforeBalance = alice.balance;
        factory.transferDeployFees(alice);
        assertEq(beforeBalance + 1e12, alice.balance);
        assertEq(0, address(factory).balance);
    }

    function testDeployFeeTransferNonOwner() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deployCampaign{value: 1e12}(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.transferDeployFees(alice);
    }

    function testDeployFeeTransferBadReceiver() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deployCampaign{value: 1e12}(recipient, 2e18, 5e18, 2e17, 1e18, 0, 60 * 60, address(0));
        vm.expectRevert("Failed to transfer Ether");
        factory.transferDeployFees(address(this));
    }
}
