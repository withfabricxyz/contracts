// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";
import "src/subscriptions/SubscriptionNFTV1Factory.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionNFTV1FactoryTest is BaseTest {
    /// @dev Emitted upon a successful Campaign deployment
    event Deployment(address indexed deployment);

    /// @dev Emitted when the fee collector or schedule changes
    event FeeScheduleChange(address feeCollector, uint16 feeBips);

    /// @dev Emitted when the creation fee minium changes
    event DeployFeeChange(uint256 fee);

    /// @dev Emitted when the deploy fees are collected by the owner
    event DeployFeeTransfer(address indexed recipient, uint256 fee);

    SubscriptionNFTV1 internal impl;
    SubscriptionNFTV1Factory internal factory;

    function setUp() public {
        impl = new SubscriptionNFTV1();
        factory = new SubscriptionNFTV1Factory(address(impl));
        deal(alice, 1e19);
    }

    function testDeployment() public {
        vm.startPrank(alice);
        vm.expectEmit(false, false, false, true, address(factory));
        emit Deployment(address(1));

        address deployment = factory.deploySubscriptionNFT("test", "tst", "curi", "turi", 1e9, 2e9, address(0));

        SubscriptionNFTV1 nft = SubscriptionNFTV1(payable(deployment));
        assertEq(nft.name(), "test");
        assertEq(nft.symbol(), "tst");
        assertEq(nft.timeValue(1e9), 1);
        assertEq(nft.erc20Address(), address(0));
    }

    function testFeeUpdate() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit FeeScheduleChange(fees, 100);
        factory.updateFeeSchedule(fees, 100);

        (address addr, uint16 bips, uint256 deploy) = factory.feeSchedule();
        assertEq(fees, addr);
        assertEq(100, bips);
        assertEq(0, deploy);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateFeeSchedule(address(alice), 100);
    }

    function testDeployFeeUpdate() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit DeployFeeChange(1e12);
        factory.updateMinimumDeployFee(1e12);

        (address addr, uint16 bips, uint256 deploy) = factory.feeSchedule();
        assertEq(address(0), addr);
        assertEq(0, bips);
        assertEq(1e12, deploy);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateMinimumDeployFee(1e12);
    }

    function testDeployFeeTooLow() public {
        factory.updateMinimumDeployFee(1e12);
        vm.expectRevert("Insufficient ETH to deploy");
        factory.deploySubscriptionNFT("test", "tst", "curi", "turi", 1e9, 2e9, address(0));
    }

    function testDeployFeeCollectNone() public {
        vm.expectRevert("No fees to collect");
        factory.transferDeployFees(alice);
    }

    function testDeployFeeCapture() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deploySubscriptionNFT{value: 1e12}("test", "tst", "curi", "turi", 1e9, 2e9, address(0));
        assertEq(1e12, address(factory).balance);
    }

    function testDeployFeeTransfer() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deploySubscriptionNFT{value: 1e12}("test", "tst", "curi", "turi", 1e9, 2e9, address(0));
        vm.expectEmit(true, true, true, true, address(factory));
        emit DeployFeeTransfer(alice, 1e12);
        uint256 beforeBalance = alice.balance;
        factory.transferDeployFees(alice);
        assertEq(beforeBalance + 1e12, alice.balance);
        assertEq(0, address(factory).balance);
    }

    function testDeployFeeTransferNonOwner() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deploySubscriptionNFT{value: 1e12}("test", "tst", "curi", "turi", 1e9, 2e9, address(0));
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.transferDeployFees(alice);
    }

    function testDeployFeeTransferBadReceiver() public {
        factory.updateMinimumDeployFee(1e12);
        factory.deploySubscriptionNFT{value: 1e12}("test", "tst", "curi", "turi", 1e9, 2e9, address(0));
        vm.expectRevert("Failed to transfer Ether");
        factory.transferDeployFees(address(this));
    }
}
