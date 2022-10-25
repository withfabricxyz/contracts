// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/ERC20CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";

contract ERC20CrowdFinancingV1Test is Test {
    ERC20CrowdFinancingV1 internal campaign;
    ERC20Token internal token;

    uint256 internal expirationFuture = 70000;
    address payable internal beneficiary = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal depositor = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal depositor2 = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal depositor3 = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;
    address internal depositorEmpty = 0xC4C79dAB8F259C7Aee6e5B2aa729821864227e81;

    function deposit(address _depositor, uint256 amount) public {
        vm.startPrank(_depositor);
        token.approve(address(campaign), amount);
        campaign.deposit();
        vm.stopPrank();
    }

    function fundAndTransfer() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        vm.warp(campaign.expiresAt());
        campaign.processFunds();
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

    function yieldValue(uint256 amount) public {
        vm.startPrank(beneficiary);
        token.transfer(address(campaign), amount);
        vm.stopPrank();
    }

    function setupToken() public {
        token = new ERC20Token(
        "FIAT",
        "FIAT",
        1e20
      );
    }

    function dealTokens(address addr, uint256 tokens) public {
        token.transfer(addr, tokens);
    }

    function setUp() public {
        setupToken();
        campaign = new ERC20CrowdFinancingV1();
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            address(token)
        );

        deal(depositor, 1e18);
        deal(depositor2, 1e18);
        deal(depositor3, 1e18);
        deal(beneficiary, 1e18);

        dealTokens(depositor, 9e18);
        dealTokens(depositor2, 9e18);
        dealTokens(depositor3, 9e18);
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
            address(token)
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
        campaign.deposit();
    }

    function testDeposit() public {
        deposit(depositor, 1e18);
        assertEq(1e18, campaign.tokenBalance());
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositAmount(depositor));
        assertEq(0, campaign.payoutTotal());
    }

    function testLargeDeposit() public {
        vm.startPrank(depositor);
        token.approve(address(campaign), 6e18);
        vm.expectRevert("Deposit amount is too high");
        campaign.deposit();
    }

    function testSmallDeposit() public {
        vm.startPrank(depositor);
        token.approve(address(campaign), 1e12);
        vm.expectRevert("Deposit amount is too low");
        campaign.deposit();
    }

    function testManyDeposits() public {
        deposit(depositor, 9e17);
        deposit(depositor, 1e17);
        assertEq(1e18, campaign.depositTotal());
        assertEq(1e18, campaign.depositAmount(depositor));

        vm.startPrank(depositor);
        token.approve(address(campaign), 1e12);
        vm.expectRevert("Deposit amount is too high");
        campaign.deposit();
    }

    function testManyDepositsFromMany() public {
        assertEq(0, campaign.depositTotal());
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertEq(3e18, campaign.tokenBalance());
        assertTrue(campaign.fundTargetMet());
    }

    function testDepositWithNoBalance() public {
        vm.startPrank(depositorEmpty);
        vm.expectRevert("Deposit amount is too low");
        campaign.deposit();
    }

    function testFundsTransfer() public {
        deposit(depositor, 1e18);
        deposit(depositor2, 1e18);
        deposit(depositor3, 1e18);
        assertTrue(campaign.fundTargetMet());
        vm.warp(campaign.expiresAt());
        assertFalse(campaign.withdrawAllowed());
        campaign.processFunds();
        assertTrue(ERC20CrowdFinancingV1.State.FUNDED == campaign.state());
        assertEq(3e18, balanceOf(beneficiary));
        assertEq(0, campaign.tokenBalance());
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
        assertEq(0, balanceOf(address(campaign)));
        yieldValue(1e18);
        assertEq(1e18, balanceOf(address(campaign)));

        // Transfer funds to the contract from the beneficiary (assumed)
        assertEq(333333333333333333, campaign.payoutBalance(depositor));
        assertEq(333333333333333333, campaign.payoutBalance(depositor2));
        assertEq(333333333333333333, campaign.payoutBalance(depositor3));
        assertEq(0, campaign.payoutBalance(depositorEmpty));
    }

    function testFundingFailure() public {
        fundAndFail();
        assertTrue(ERC20CrowdFinancingV1.State.FAILED == campaign.state());
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
        campaign.deposit();
    }

    function testDepositAfterFailed() public {
        fundAndFail();
        vm.startPrank(depositor);
        vm.expectRevert("Deposits are not allowed");
        campaign.deposit();
    }
}
