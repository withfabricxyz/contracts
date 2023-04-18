// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseCampaignTest.t.sol";

contract InitTests is BaseCampaignTest {
    CrowdFinancingV1 internal _campaign;
    uint256 internal ts;

    function setUp() public {
        _campaign = new CrowdFinancingV1();
        vm.store(address(_campaign), bytes32(uint256(0)), bytes32(0));
        ts = block.timestamp;
    }

    function testValid() public {
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testInitialDeployment() public {
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
        assertTrue(_campaign.isContributionAllowed());
        assertFalse(_campaign.isWithdrawAllowed());
        assertFalse(_campaign.isGoalMinMet());
        assertFalse(_campaign.isGoalMaxMet());
        assertEq(0, _campaign.totalSupply());
        assertEq(0, _campaign.yieldTotal());
        assertEq(2e17, _campaign.minAllowedContribution());
        assertEq(1e18, _campaign.maxAllowedContribution());
        assertEq(address(0), _campaign.erc20Address());
        assertEq(2e18, _campaign.goalMin());
        assertEq(5e18, _campaign.goalMax());
        assertEq(recipient, _campaign.recipientAddress());
        assertEq(address(0), _campaign.feeRecipientAddress());
        assertEq(0, _campaign.transferFeeBips());
        assertEq(0, _campaign.yieldFeeBips());
        assertTrue(_campaign.isEthDenominated());
        assertEq(ts, _campaign.startsAt());
        assertEq(ts + expirationFuture, _campaign.endsAt());
        assertTrue(_campaign.isStarted());
        assertFalse(_campaign.isEnded());
        assertTrue(_campaign.state() == CrowdFinancingV1.State.FUNDING);
        // assertEq(0, _campaign.payoutsMadeTo(alice));
        assertEq(0, _campaign.yieldTotalOf(alice));
    }

    function testReinit() public {
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
        vm.expectRevert("Initializable: contract is already initialized");
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testBadrecipient() public {
        vm.expectRevert("Invalid recipient address");
        _campaign.initialize(
            address(0), 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testPastStart() public {
        vm.warp(ts + 200);
        vm.expectRevert("Invalid start time");
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testBadRange() public {
        vm.expectRevert("Invalid time range");
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + 20, address(0), address(0), 0, 0);
    }

    function testTooLong() public {
        vm.expectRevert("Invalid end time");
        _campaign.initialize(recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + 7776000 + 1, address(0), address(0), 0, 0);
    }

    function testZeroGoal() public {
        vm.expectRevert("Min goal must be > 0");
        _campaign.initialize(recipient, 0, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testImpossibleGoalRange() public {
        vm.expectRevert("Min goal must be <= Max goal");
        _campaign.initialize(recipient, 5e18, 4e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testZeroDeposit() public {
        vm.expectRevert("Min contribution must be > 0");
        _campaign.initialize(recipient, 2e18, 5e18, 0, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testImpossibleDepositRange() public {
        vm.expectRevert("Min contribution must be <= Max contribution");
        _campaign.initialize(recipient, 2e18, 5e18, 1e18, 2e17, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testMinDepositGoalRelation() public {
        vm.expectRevert("Min contribution must be < (maxGoal - minGoal) or 1");
        _campaign.initialize(recipient, 2e18, 2e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testMinGoalRelationWith1() public {
        _campaign.initialize(recipient, 2e18, 2e18, 1, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testLargeUpfrontFee() public {
        vm.expectRevert("Transfer fee too high");
        _campaign.initialize(
            recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 5000, 0
        );
    }

    function testLargePayoutFee() public {
        vm.expectRevert("Yield fee too high");
        _campaign.initialize(
            recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 5000
        );
    }

    function testFeeCollectorNoFees() public {
        vm.expectRevert("Fees must be 0 when there is no fee recipient");
        _campaign.initialize(
            recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 250, 0
        );
    }

    function testNoFeeCollectorFees() public {
        vm.expectRevert("Fees required when fee recipient is present");
        _campaign.initialize(
            recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), feeCollector, 0, 0
        );
    }

    function testtransferFeeBips() public {
        ERC20Token _token = createERC20Token();
        _campaign.initialize(
            recipient, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(_token), address(0), 0, 0
        );
        assertFalse(_campaign.isEthDenominated());
        assertEq(address(_token), _campaign.erc20Address());
        assertEq(0, _token.balanceOf(address(_campaign)));
    }
}
