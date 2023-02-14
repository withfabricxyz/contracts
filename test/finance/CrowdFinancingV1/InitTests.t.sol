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
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testInitialDeployment() public {
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
        assertTrue(_campaign.depositAllowed());
        assertFalse(_campaign.withdrawAllowed());
        assertFalse(_campaign.fundTargetMet());
        assertFalse(_campaign.fundTargetMaxMet());
        assertEq(0, _campaign.depositTotal());
        assertEq(0, _campaign.totalSupply());
        assertEq(0, _campaign.payoutTotal());
        assertEq(2e17, _campaign.minimumDeposit());
        assertEq(1e18, _campaign.maximumDeposit());
        assertEq(address(0), _campaign.tokenAddress());
        assertEq(2e18, _campaign.minimumFundTarget());
        assertEq(5e18, _campaign.maximumFundTarget());
        assertEq(beneficiary, _campaign.beneficiaryAddress());
        assertEq(address(0), _campaign.feeCollector());
        assertEq(0, _campaign.upfrontFeeBips());
        assertEq(0, _campaign.payoutFeeBips());
        assertFalse(_campaign.erc20Denominated());
        assertEq(ts, _campaign.startsAt());
        assertEq(ts + expirationFuture, _campaign.expiresAt());
        assertTrue(_campaign.started());
        assertFalse(_campaign.expired());
        assertTrue(_campaign.state() == CrowdFinancingV1.State.FUNDING);
        // assertEq(0, _campaign.payoutsMadeTo(alice));
        assertEq(0, _campaign.returnOnInvestment(alice));
    }

    function testReinit() public {
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
        vm.expectRevert("Initializable: contract is already initialized");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testBadBeneficiary() public {
        vm.expectRevert("Invalid beneficiary address");
        _campaign.initialize(
            address(0), 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testPastStart() public {
        vm.warp(ts + 200);
        vm.expectRevert("Invalid start time");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testBadRange() public {
        vm.expectRevert("Invalid time range");
        _campaign.initialize(beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + 20, address(0), address(0), 0, 0);
    }

    function testTooLong() public {
        vm.expectRevert("Invalid end time");
        _campaign.initialize(beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + 7776000 + 1, address(0), address(0), 0, 0);
    }

    function testZeroGoal() public {
        vm.expectRevert("Min target must be > 0");
        _campaign.initialize(beneficiary, 0, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testImpossibleGoalRange() public {
        vm.expectRevert("Min target must be <= Max");
        _campaign.initialize(
            beneficiary, 5e18, 4e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testZeroDeposit() public {
        vm.expectRevert("Min deposit must be > 0");
        _campaign.initialize(beneficiary, 2e18, 5e18, 0, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0);
    }

    function testImpossibleDepositRange() public {
        vm.expectRevert("Min deposit must be <= Max");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 1e18, 2e17, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testDepositMaxGoalRelation() public {
        vm.expectRevert("Min deposit must be <= Target Max");
        _campaign.initialize(
            beneficiary, 1e18, 2e18, 2e19, 3e19, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testMinDepositGoalRelation() public {
        vm.expectRevert("Min deposit must be < (fundTargetMax - fundTargetMin)");
        _campaign.initialize(
            beneficiary, 2e18, 2e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 0
        );
    }

    function testLargeUpfrontFee() public {
        vm.expectRevert("Upfront fee too high");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 5000, 0
        );
    }

    function testLargePayoutFee() public {
        vm.expectRevert("Payout fee too high");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 0, 5000
        );
    }

    function testFeeCollectorNoFees() public {
        vm.expectRevert("Fees must be 0 when there is no fee collector");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), address(0), 250, 0
        );
    }

    function testNoFeeCollectorFees() public {
        vm.expectRevert("Fees required when fee collector is present");
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(0), feeCollector, 0, 0
        );
    }

    function testTokenBalance() public {
        ERC20Token _token = createERC20Token();
        _campaign.initialize(
            beneficiary, 2e18, 5e18, 2e17, 1e18, ts, ts + expirationFuture, address(_token), address(0), 0, 0
        );
        assertTrue(_campaign.erc20Denominated());
        assertEq(address(_token), _campaign.tokenAddress());
        assertEq(0, _campaign.tokenBalance());
    }
}
