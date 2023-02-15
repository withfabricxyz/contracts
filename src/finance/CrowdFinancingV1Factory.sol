// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CrowdFinancingV1.sol";

/**
 *
 * @title Fabric Crowd Financing Factory Contract
 * @author Dan Simpson
 *
 * A simple factory which leverages Clones to deploy new campaigns
 *
 */
contract CrowdFinancingV1Factory is Ownable {
    // The event emitted upon a successful Campaign deployment
    event Deployment(uint64 nonce, address indexed deployment);

    // Emitted when the fee collector or schedule changes
    event FeeScheduleChange(address feeCollector, uint16 upfrontBips, uint16 payoutBips);

    // The contract implementation address
    address immutable _implementation;

    // The fee collector address (can be 0, no fees are collected)
    address private _feeCollector;

    // The upfront fee (See CrowdFinancingV1)
    uint16 private _feeUpfrontBips;

    // The payout fee (See CrowdFinancingV1)
    uint16 private _feePayoutBips;

    /**
     * @param implementation the CrowdFinancingV1 implementation address
     */
    constructor(address implementation) Ownable() {
        _implementation = implementation;
        _feeCollector = address(0);
        _feeUpfrontBips = 0;
        _feePayoutBips = 0;
    }

    /**
     * @notice Deploys a new CrowdFinancingV1 contract
     *
     * @param externalRef An optional reference value emitted in the deploy event for association
     * @param beneficiary the address of the beneficiary, where funds are sent on success
     * @param fundTargetMin the minimum funding amount acceptible for successful financing
     * @param fundTargetMax the maximum funding amount accepted for the financing round
     * @param minDeposit the minimum deposit an account can make in one deposit
     * @param maxDeposit the maximum deposit an account can make in one or more deposits
     * @param holdOff the number of seconds to wait until the fund starts
     * @param duration the runtime of the campaign, in seconds
     * @param tokenAddr the address of the ERC20 token used for payments, or 0 address for native token
     */
    function deploy(
        uint64 externalRef,
        address beneficiary,
        uint256 fundTargetMin,
        uint256 fundTargetMax,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint32 holdOff,
        uint32 duration,
        address tokenAddr
    ) external returns (address) {
        address deployment = Clones.clone(_implementation);

        uint256 startTimestamp = block.timestamp + holdOff;
        uint256 endTimestamp = startTimestamp + duration;

        CrowdFinancingV1(deployment).initialize(
            beneficiary,
            fundTargetMin,
            fundTargetMax,
            minDeposit,
            maxDeposit,
            startTimestamp,
            endTimestamp,
            tokenAddr,
            _feeCollector,
            _feeUpfrontBips,
            _feePayoutBips
        );

        emit Deployment(externalRef, deployment);

        return deployment;
    }

    /**
     * Update the fee schedule for future deployments
     *
     * @param feeCollector the address of the fee collector, or the 0 address if no fees are collected
     * @param feeUpfrontBips the upfront fee in basis points, calculated during processing
     * @param feePayoutBips the payout fee in basis points. Dilutes the cap table for fee collection
     */
    function updateFeeSchedule(address feeCollector, uint16 feeUpfrontBips, uint16 feePayoutBips) external onlyOwner {
        _feeCollector = feeCollector;
        _feeUpfrontBips = feeUpfrontBips;
        _feePayoutBips = feePayoutBips;
        emit FeeScheduleChange(feeCollector, feeUpfrontBips, feePayoutBips);
    }

    function feeSchedule() external view returns (address, uint16, uint16) {
        return (_feeCollector, _feeUpfrontBips, _feePayoutBips);
    }
}
