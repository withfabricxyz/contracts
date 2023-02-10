// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";

/*

TODO:
Test eth dep, with, payment, etc

Transfer
Withdraw
*/

contract CrowdFinancingV1Test is Test {
    CrowdFinancingV1 internal campaign;
    ERC20Token internal token;

    uint256 internal expirationFuture = 70000;
    address payable internal beneficiary = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal depositor = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal depositor2 = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal depositor3 = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;
    address internal depositor4 = 0xB4c79DAB8f259C7AEE6e5B2Aa729821764227E8A;
    address internal depositor5 = 0xB4C79DAB8f259c7Aee6E5b2AA729821764227e7A;
    address internal depositorEmpty = 0xC4C79dAB8F259C7Aee6e5B2aa729821864227e81;
    address internal feeCollector = 0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87;

    function withdraw(CrowdFinancingV1 _campaign, address _depositor) public {
        vm.startPrank(_depositor);
        _campaign.withdraw();
        vm.stopPrank();
    }

    function deposit(CrowdFinancingV1 _campaign, address _depositor, uint256 amount) public {
        vm.startPrank(_depositor);
        token.approve(address(_campaign), amount);
        _campaign.depositTokens(amount);
        vm.stopPrank();
    }

    function deposit(address _depositor, uint256 amount) public {
        deposit(campaign, _depositor, amount);
    }

    function fundAndTransferCampaign(CrowdFinancingV1 _campaign) public {
        deposit(_campaign, depositor, 1e18);
        deposit(_campaign, depositor2, 1e18);
        deposit(_campaign, depositor3, 1e18);
        vm.warp(_campaign.expiresAt());
        _campaign.processFunds();
    }

    function fundAndTransfer() public {
        fundAndTransferCampaign(campaign);
    }

    function balanceOf(address addr) public view returns (uint256) {
        return token.balanceOf(addr);
    }

    function fundAndFail() public {
        deposit(depositor, 3e17);
        deposit(depositor2, 3e17);
        deposit(depositor3, 3e17);
        vm.warp(campaign.expiresAt());
        campaign.processFunds();
    }

    function yieldValue(CrowdFinancingV1 _campaign, uint256 amount) public {
        vm.startPrank(beneficiary);
        token.approve(address(_campaign), amount);
        _campaign.yieldTokens(amount);
        vm.stopPrank();
    }

    function yieldValue(uint256 amount) public {
        yieldValue(campaign, amount);
    }

    function setupToken() public {
        token = new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
    }

    function dealTokens(address addr, uint256 tokens) public {
        token.transfer(addr, tokens);
    }

    function setUp() public {
        setupToken();
        campaign = new CrowdFinancingV1();

        // unmark initialzied, eg: campaign._initialized = 0;
        vm.store(address(campaign), bytes32(uint256(0)), bytes32(0));
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            address(token),
            address(0),
            0,
            0
        );

        // For Gas...
        deal(depositor, 1e18);
        deal(depositor2, 1e18);
        deal(depositor3, 1e18);
        deal(depositor4, 1e18);
        deal(depositor5, 1e18);
        deal(beneficiary, 1e18);

        dealTokens(depositor, 9e18);
        dealTokens(depositor2, 9e18);
        dealTokens(depositor3, 9e18);
        dealTokens(depositor4, 9e18);
        dealTokens(depositor5, 9e18);
    }

    function testInitialDeployment() public {
        assertTrue(campaign.depositAllowed());
        assertFalse(campaign.withdrawAllowed());
        assertFalse(campaign.fundTargetMet());
        assertEq(0, campaign.depositTotal());
        assertEq(2e17, campaign.minimumDeposit());
        assertEq(1e18, campaign.maximumDeposit());
        assertEq(address(token), campaign.tokenAddress());
        assertEq(2e18, campaign.minimumFundTarget());
        assertEq(5e18, campaign.maximumFundTarget());
        assertEq(beneficiary, campaign.beneficiaryAddress());
        assertEq(address(0), campaign.feeCollector());
        assertEq(0, campaign.upfrontFeeBips());
        assertEq(0, campaign.payoutFeeBips());
        assertTrue(campaign.erc20Denominated());
    }

    function testReinit() public {
        vm.expectRevert("Initializable: contract is already initialized");
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            address(token),
            address(0),
            0,
            0
        );
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

    function testUnapprovedDeposit() public {
        vm.expectRevert("Deposit amount is too low");
        vm.startPrank(depositor);
        campaign.depositTokens(0);
    }

    function testDeposit() public {
        deposit(depositor, 1e18);
        assertEq(1e18, campaign.tokenBalance());
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositedAmount(depositor));
        assertEq(0, campaign.payoutTotal());
    }

    function testLargeDeposit() public {
        vm.startPrank(depositor);
        token.approve(address(campaign), 6e18);
        vm.expectRevert("Deposit amount is too high");
        campaign.depositTokens(6e18);
    }

    function testSmallDeposit() public {
        vm.startPrank(depositor);
        token.approve(address(campaign), 1e12);
        vm.expectRevert("Deposit amount is too low");
        campaign.depositTokens(1e12);
    }

    function testAllowanceMismatch() public {
        vm.startPrank(depositor);
        token.approve(address(campaign), 1e12);
        vm.expectRevert("Amount exceeds token allowance");
        campaign.depositTokens(1e18);
    }

    function testManyDeposits() public {
        deposit(depositor, 9e17);
        deposit(depositor, 1e17);
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositedAmount(depositor));

        vm.startPrank(depositor);
        token.approve(address(campaign), 1e12);
        vm.expectRevert("Deposit amount is too high");
        campaign.depositTokens(1e12);
    }

    function testManyDepositsFromMany() public {
        assertEq(0, campaign.depositTotal());
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertEq(0, campaign.returnOnInvestment(depositor));
        assertEq(333333, campaign.ownershipPPM(depositor));
        assertEq(3e18, campaign.tokenBalance());
        assertTrue(campaign.fundTargetMet());
    }

    function testDepositWithNoBalance() public {
        vm.startPrank(depositorEmpty);
        vm.expectRevert("Deposit amount is too low");
        campaign.depositTokens(0);
    }

    function testFundsTransfer() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertTrue(campaign.fundTargetMet());
        vm.warp(campaign.expiresAt());
        assertFalse(campaign.withdrawAllowed());
        campaign.processFunds();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign.state());
        assertEq(3e18, balanceOf(beneficiary));
        assertEq(0, campaign.tokenBalance());
        assertTrue(campaign.withdrawAllowed());
    }

    function testEarlyProcess() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertTrue(campaign.fundTargetMet());
        assertFalse(campaign.fundTargetMaxMet());
        assertFalse(campaign.expired());
        vm.expectRevert("More time/funds required");
        campaign.processFunds();
        deposit(depositor4, 1e18);
        deposit(depositor5, 1e18);
        assertTrue(campaign.fundTargetMaxMet());
        assertFalse(campaign.expired());
        campaign.processFunds();
        assertTrue(CrowdFinancingV1.State.FUNDED == campaign.state());
        assertTrue(campaign.withdrawAllowed());
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
        assertEq(0, balanceOf(address(campaign)));
        yieldValue(1e18);
        assertEq(1e18, balanceOf(address(campaign)));

        // Transfer funds to the contract from the beneficiary (assumed)
        assertEq(333333333333333333, campaign.payoutBalance(depositor));
        assertEq(333333333333333333, campaign.payoutBalance(depositor2));
        assertEq(333333333333333333, campaign.payoutBalance(depositor3));
        assertEq(0, campaign.payoutBalance(depositorEmpty));
    }

    function testMultiReturns() public {
        fundAndTransfer();
        yieldValue(1e18);

        uint256 dBalance = balanceOf(depositor);
        withdraw(campaign, depositor);
        yieldValue(1e18);
        withdraw(campaign, depositor);

        assertEq(666666666666666666, balanceOf(depositor) - dBalance);
        assertEq(0, campaign.payoutBalance(depositor));
    }

    function testProfit() public {
        fundAndTransfer();
        dealTokens(beneficiary, 1e20);
        yieldValue(1e19);
        assertEq(3333333333333333333, campaign.payoutBalance(depositor));
        assertEq(3333333333333333333 - 1e18, campaign.returnOnInvestment(depositor));
    }

    function testReturnsViaPayoutFn() public {
        vm.expectRevert("Cannot accept payment");
        campaign.yieldTokens(1e18);

        fundAndTransfer();
        assertEq(0, balanceOf(address(campaign)));
        vm.startPrank(beneficiary);
        token.approve(address(campaign), 1e18);
        campaign.yieldTokens(1e18);

        vm.expectRevert("Amount is 0");
        campaign.yieldTokens(0);

        vm.expectRevert("Amount exceeds token allowance");
        campaign.yieldTokens(1e18);

        vm.stopPrank();
        assertEq(1e18, balanceOf(address(campaign)));
    }

    function testFundingFailure() public {
        fundAndFail();
        assertTrue(CrowdFinancingV1.State.FAILED == campaign.state());
        assertTrue(campaign.withdrawAllowed());
        assertEq(0, balanceOf(beneficiary));

        assertEq(balanceOf(depositor), 9e18 - 3e17);
        vm.startPrank(depositor);
        campaign.withdraw();
        assertEq(balanceOf(depositor), 9e18);

        // // This one should fail
        vm.expectRevert("No balance");
        campaign.withdraw();
        vm.stopPrank();
    }

    function testWithdraw() public {
        fundAndTransfer();
        yieldValue(1e18);

        assertEq(campaign.payoutTotal(), 1e18);

        uint256 startBalance = balanceOf(depositor);
        uint256 campaignBalance = balanceOf(address(campaign));

        vm.startPrank(depositor);
        assertEq(campaign.withdrawsOf(depositor), 0);
        campaign.withdraw();
        assertEq(campaign.withdrawsOf(depositor), 333333333333333333);
        assertEq(campaign.payoutBalance(depositor), 0);
        assertEq(balanceOf(depositor), startBalance + 333333333333333333);
        assertEq(campaign.payoutBalance(depositor3), 333333333333333333);
        assertEq(balanceOf(address(campaign)), campaignBalance - 333333333333333333);
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
        vm.startPrank(depositor);
        vm.expectRevert("Deposits are not allowed");
        campaign.depositTokens(1e18);
    }

    function testDepositAfterFailed() public {
        fundAndFail();
        vm.startPrank(depositor);
        vm.expectRevert("Deposits are not allowed");
        campaign.depositTokens(1e18);
    }

    ////////////
    // Fee Collection Tests
    ////////////

    function createFeeCampaign(uint16 upfrontBips, uint16 payoutBips) internal returns (CrowdFinancingV1) {
        CrowdFinancingV1 withFees = new CrowdFinancingV1();
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
            address(token),
            feeCollector,
            upfrontBips,
            payoutBips
        );
        return withFees;
    }

    function testUpfrontFees() public {
        CrowdFinancingV1 _campaign = createFeeCampaign(100, 0);
        fundAndTransferCampaign(_campaign);
        assertEq(3e18 - 3e16, balanceOf(beneficiary));
        assertEq(3e16, balanceOf(feeCollector));
        assertEq(0, balanceOf(address(_campaign)));
    }

    function testUpfrontFeesSplit() public {
        CrowdFinancingV1 _campaign = createFeeCampaign(2500, 0); // 25%!
        fundAndTransferCampaign(_campaign);
        assertEq(balanceOf(beneficiary), 2.25e18);
        assertEq(balanceOf(feeCollector), 0.75e18);
    }

    function testPayoutFees() public {
        CrowdFinancingV1 _campaign = createFeeCampaign(0, 250);
        fundAndTransferCampaign(_campaign);
        yieldValue(_campaign, 1e18);

        withdraw(_campaign, depositor);
        withdraw(_campaign, depositor2);
        withdraw(_campaign, depositor3);
        withdraw(_campaign, feeCollector);

        assertApproxEqAbs(0, balanceOf(address(_campaign)), 4);
        assertApproxEqAbs(24390243902439024, balanceOf(feeCollector), 5);
    }

    function testInvalidFeeConfig() public {
        CrowdFinancingV1 withFees = new CrowdFinancingV1();
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
            address(token),
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
            address(token),
            feeCollector,
            0,
            0
        );
    }
}
