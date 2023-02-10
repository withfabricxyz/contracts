// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "./util/TestHelper.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/finance/CrowdFinancingV1Factory.sol";

contract CrowdFinancingV1FactoryTest is TestHelper {
    CrowdFinancingV1 internal impl;
    CrowdFinancingV1Factory internal factory;

    function setUp() public {
        impl = new CrowdFinancingV1();
        factory = new CrowdFinancingV1Factory(address(impl));
        deal(depositor, 1e19);
    }

    function testDeployment() public {
        vm.startPrank(depositor);
        address deployment = factory.deploy(beneficiary, 2e18, 5e18, 2e17, 1e18, 60 * 60, address(0));

        CrowdFinancingV1 campaign = CrowdFinancingV1(deployment);
        assertFalse(campaign.withdrawAllowed());
        assertFalse(campaign.fundTargetMet());
        assertEq(0, campaign.depositTotal());
        assertEq(2e17, campaign.minimumDeposit());
        assertEq(1e18, campaign.maximumDeposit());
        assertTrue(campaign.erc20Denominated());
        assertEq(address(0), campaign.tokenAddress());
        assertEq(2e18, campaign.minimumFundTarget());
        assertEq(5e18, campaign.maximumFundTarget());
        assertEq(beneficiary, campaign.beneficiaryAddress());

        // Test fee collection
    }
}
