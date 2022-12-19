// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/EthCrowdFinancingV1.sol";

contract EthCrowdFinancingV1Test is Test {
    EthCrowdFinancingV1 internal campaign;
    uint256 internal expirationFuture = 70000;
    address payable internal beneficiary = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal depositor = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal depositor2 = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal depositor3 = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;
    address internal depositorEmpty = 0xC4C79dAB8F259C7Aee6e5B2aa729821864227e81;
    address internal feeCollector = 0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87;

    function deposit(EthCrowdFinancingV1 _campaign, address _depositor, uint256 amount) public {
        vm.startPrank(_depositor);
        (bool success, bytes memory data) =
            address(_campaign).call{value: amount, gas: 700000}(abi.encodeWithSignature("deposit()"));
        vm.stopPrank();

        if (!success) {
            if (data.length == 0) revert();
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function deposit(address _depositor, uint256 amount) public {
        deposit(campaign, _depositor, amount);
    }

    function withdraw(EthCrowdFinancingV1 _campaign, address _depositor) public {
        vm.startPrank(_depositor);
        _campaign.withdraw();
        vm.stopPrank();
    }

    function fundAndTransferCampaign(EthCrowdFinancingV1 _campaign) public {
        deposit(_campaign, depositor, 1e18);
        deposit(_campaign, depositor2, 1e18);
        deposit(_campaign, depositor3, 1e18);
        vm.warp(_campaign.expiresAt());
        _campaign.processFunds();
    }

    function fundAndTransfer() public {
        fundAndTransferCampaign(campaign);
    }

    function fundAndFail() public {
        deposit(depositor, 3e17);
        deposit(depositor2, 3e17);
        deposit(depositor3, 3e17);
        vm.warp(campaign.expiresAt());
        campaign.processFunds();
    }

    function yieldValue(EthCrowdFinancingV1 _campaign, uint256 amount) public {
        vm.startPrank(beneficiary);
        payable(address(_campaign)).transfer(amount);
        vm.stopPrank();
    }

    function yieldValue(uint256 amount) public {
        yieldValue(campaign, amount);
    }

    function setUp() public {
        campaign = new EthCrowdFinancingV1();

        vm.store(address(campaign), bytes32(uint256(0)), bytes32(0));
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            address(0),
            0,
            0
        );

        deal(depositor, 9e18);
        deal(depositor2, 9e18);
        deal(depositor3, 9e18);
    }

    function testInitialDeployment() public {
        assertTrue(campaign.depositAllowed());
        assertFalse(campaign.withdrawAllowed());
        assertFalse(campaign.fundTargetMet());
        assertEq(0, campaign.depositTotal());
        assertEq(2e17, campaign.minimumDeposit());
        assertEq(1e18, campaign.maximumDeposit());
        assertEq(2e18, campaign.minimumFundTarget());
        assertEq(5e18, campaign.maximumFundTarget());
        assertEq(beneficiary, campaign.beneficiaryAddress());
    }

    function testStartChecks() public {
        assertTrue(campaign.started());
        assertEq(campaign.startsAt(), block.timestamp);
        rewind(block.timestamp);
        assertFalse(campaign.started());
        assertFalse(campaign.depositAllowed());
    }

    function testEndChecks() public {
        assertFalse(campaign.expired());
        assertEq(campaign.expiresAt(), block.timestamp + expirationFuture);
        vm.warp(block.timestamp + expirationFuture);
        assertTrue(campaign.expired());
        assertFalse(campaign.depositAllowed());
    }

    function testEarlyWithdraw() public {
        vm.startPrank(depositor);
        vm.expectRevert("Withdraw not allowed");
        campaign.withdraw();
    }

    function testEmptyDeposit() public {
        vm.expectRevert("Deposit amount is too low");
        vm.startPrank(depositor);
        deal(depositor, 1e18);
        campaign.deposit();
    }

    function testDeposit() public {
        deal(depositor, 10e18);
        deposit(depositor, 1e18);
        assertEq(1e18, address(campaign).balance);
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositAmount(depositor));
        assertEq(0, campaign.payoutTotal());
    }

    function testLargeDeposit() public {
        vm.expectRevert("Deposit amount is too high");
        deposit(depositor, 6e18);
    }

    function testSmallDeposit() public {
        vm.expectRevert("Deposit amount is too low");
        deposit(depositor, 1e12);
    }

    function testManyDeposits() public {
        deposit(depositor, 9e17);
        deposit(depositor, 1e17);
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositAmount(depositor));
        vm.expectRevert("Deposit amount is too high");
        deposit(depositor, 1e17);
    }

    function testManyDepositsFromMany() public {
        assertEq(0, campaign.depositTotal());
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertEq(3e18, address(campaign).balance);
        assertTrue(campaign.fundTargetMet());
    }

    function testDepositWithNoBalance() public {
        vm.expectRevert();
        deposit(depositorEmpty, 1e18);
    }

    function testFundsTransfer() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertTrue(campaign.fundTargetMet());
        vm.warp(campaign.expiresAt());
        assertFalse(campaign.withdrawAllowed());
        campaign.processFunds();
        assertTrue(EthCrowdFinancingV1.State.FUNDED == campaign.state());
        assertEq(3e18, beneficiary.balance);
        assertEq(0, address(campaign).balance);
        assertTrue(campaign.withdrawAllowed());
    }

    function testEarlyProcess() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertTrue(campaign.fundTargetMet());
        vm.expectRevert("Raise window is not expired");
        campaign.processFunds();
    }

    function testSecondProcess() public {
        fundAndTransfer();
        vm.expectRevert("Funds already processed");
        campaign.processFunds();
    }

    function testSecondPassFail() public {
        fundAndFail();
        vm.expectRevert("Funds already processed");
        campaign.processFunds();
    }

    function testReturns() public {
        fundAndTransfer();
        assertEq(0, address(campaign).balance);
        yieldValue(1e18);
        assertEq(1e18, address(campaign).balance);

        // Transfer funds to the contract from the beneficiary (assumed)
        assertEq(333333333333333333, campaign.payoutBalance(depositor));
        assertEq(333333333333333333, campaign.payoutBalance(depositor2));
        assertEq(333333333333333333, campaign.payoutBalance(depositor3));
        assertEq(0, campaign.payoutBalance(depositorEmpty));
    }

    function testMultiReturns() public {
        fundAndTransfer();
        yieldValue(1e18);

        uint256 dBalance = depositor.balance;
        withdraw(campaign, depositor);
        yieldValue(1e18);
        withdraw(campaign, depositor);

        assertEq(666666666666666666, depositor.balance - dBalance);
        assertEq(0, campaign.payoutBalance(depositor));
    }

    function testFundingFailure() public {
        fundAndFail();
        assertTrue(EthCrowdFinancingV1.State.FAILED == campaign.state());
        assertTrue(campaign.withdrawAllowed());
        assertEq(0, beneficiary.balance);

        deal(beneficiary, 1e19);

        vm.startPrank(depositor);
        campaign.withdraw();

        // // This one should fail
        vm.expectRevert("No balance");
        campaign.withdraw();
        vm.stopPrank();

        vm.expectRevert();
        yieldValue(1e18);
    }

    function testWithdraw() public {
        fundAndTransfer();
        yieldValue(1e18);

        assertEq(campaign.payoutTotal(), 1e18);

        uint256 startBalance = depositor.balance;
        uint256 campaignBalance = address(campaign).balance;

        vm.startPrank(depositor);
        assertEq(campaign.withdrawsOf(depositor), 0);
        campaign.withdraw();
        assertEq(campaign.withdrawsOf(depositor), 333333333333333333);
        assertEq(campaign.payoutBalance(depositor), 0);
        assertEq(depositor.balance, startBalance + 333333333333333333);
        assertEq(campaign.payoutBalance(depositor3), 333333333333333333);
        assertEq(address(campaign).balance, campaignBalance - 333333333333333333);
    }

    function testDoubleWithdraw() public {
        fundAndTransfer();
        yieldValue(1e18);
        vm.startPrank(depositor);
        campaign.withdraw();
        vm.expectRevert("No balance");
        campaign.withdraw();
    }

    function testDepositAfterFunded() public {
        fundAndTransfer();
        vm.expectRevert("Deposits are not allowed");
        deposit(depositor, 1e17);
    }

    function testDepositAfterFailed() public {
        fundAndFail();
        vm.expectRevert("Deposits are not allowed");
        deposit(depositor, 1e18);
    }

    ////////////
    // Fee Collection Tests
    ////////////

    function createFeeCampaign(uint256 upfrontBips, uint256 payoutBips) internal returns (EthCrowdFinancingV1) {
        EthCrowdFinancingV1 withFees = new EthCrowdFinancingV1();
        // unmark initialized, eg: campaign._initialized = 0;
        vm.store(address(withFees), bytes32(uint256(0)), bytes32(0));
        withFees.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            feeCollector,
            upfrontBips,
            payoutBips
        );
        return withFees;
    }

    function testUpfrontFees() public {
        EthCrowdFinancingV1 _campaign = createFeeCampaign(100, 0);
        fundAndTransferCampaign(_campaign);
        assertEq(3e18 - 3e16, beneficiary.balance);
        assertEq(3e16, feeCollector.balance);
        assertEq(0, address(_campaign).balance);
    }

    function testUpfrontFeesSplit() public {
        EthCrowdFinancingV1 _campaign = createFeeCampaign(2500, 0); // 25%!
        fundAndTransferCampaign(_campaign);
        assertEq(beneficiary.balance, 2.25e18);
        assertEq(feeCollector.balance, 0.75e18);
    }

    function testPayoutFees() public {
        EthCrowdFinancingV1 _campaign = createFeeCampaign(0, 250);
        fundAndTransferCampaign(_campaign);
        yieldValue(_campaign, 1e18);

        withdraw(_campaign, depositor);
        withdraw(_campaign, depositor2);
        withdraw(_campaign, depositor3);
        withdraw(_campaign, feeCollector);

        assertApproxEqAbs(0, address(_campaign).balance, 4);
        assertApproxEqAbs(25000000000000000, feeCollector.balance, 1e15);
    }

    function testInvalidFeeConfig() public {
        EthCrowdFinancingV1 withFees = new EthCrowdFinancingV1();
        // unmark initialized, eg: campaign._initialized = 0;
        vm.store(address(withFees), bytes32(uint256(0)), bytes32(0));
        vm.expectRevert("Fees must be 0 when there is no fee collector");
        withFees.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            address(0),
            100,
            0
        );

        vm.expectRevert("Fees required when fee collector is present");
        withFees.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            feeCollector,
            0,
            0
        );
    }
}
