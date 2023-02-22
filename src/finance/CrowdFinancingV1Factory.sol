// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CrowdFinancingV1.sol";

/**
 *
 * @title Fabric Crowd Financing Factory Contract
 * @author Fabric Inc.
 *
 * A factory which leverages Clones to deploy campaigns.
 *
 */
contract CrowdFinancingV1Factory is Ownable {
    modifier feeRequired() {
        require(msg.value >= _feeDeployMin, "Insuffient ETH to deploy");
        _;
    }

    // The event emitted upon a successful Campaign deployment
    event Deployment(uint64 nonce, address indexed deployment);

    // Emitted when the fee collector or schedule changes
    event FeeScheduleChange(address feeCollector, uint16 upfrontBips, uint16 payoutBips);

    // Emitted when the creation fee minium changes
    event DeployFeeChange(uint256 fee);

    // Emitted when the deploy fees are collected by the owner
    event DeployFeeTransfer(address indexed recipient, uint256 fee);

    // The contract implementation address
    address immutable _implementation;

    // The fee collector address (can be 0, no fees are collected)
    address private _feeCollector;

    // The upfront fee (See CrowdFinancingV1)
    uint16 private _feeTransferBips;

    // The payout fee (See CrowdFinancingV1)
    uint16 private _feeYieldBips;

    // Fee to collect upon creation
    uint256 private _feeDeployMin;

    /**
     * @param implementation the CrowdFinancingV1 implementation address
     */
    constructor(address implementation) Ownable() {
        _implementation = implementation;
        _feeCollector = address(0);
        _feeTransferBips = 0;
        _feeYieldBips = 0;
        _feeDeployMin = 0;
    }

    /**
     * @notice Deploys a new CrowdFinancingV1 contract
     *
     * @param externalRef An optional reference value emitted in the deploy event for association
     * @param recipient the address of the recipient, where funds are sent on success
     * @param minGoal the minimum funding amount acceptible for successful financing
     * @param maxGoal the maximum funding amount accepted for the financing round
     * @param minContribution the minimum deposit an account can make in one deposit
     * @param maxContribution the maximum deposit an account can make in one or more deposits
     * @param holdOff the number of seconds to wait until the fund starts
     * @param duration the runtime of the campaign, in seconds
     * @param erc20TokenAddr the address of the ERC20 token used for payments, or 0 address for native token
     */
    function deployCampaign(
        uint64 externalRef,
        address recipient,
        uint256 minGoal,
        uint256 maxGoal,
        uint256 minContribution,
        uint256 maxContribution,
        uint32 holdOff,
        uint32 duration,
        address erc20TokenAddr
    ) external payable feeRequired returns (address) {
        address deployment = Clones.clone(_implementation);

        uint256 startTimestamp = block.timestamp + holdOff;
        uint256 endTimestamp = startTimestamp + duration;

        CrowdFinancingV1(deployment).initialize(
            recipient,
            minGoal,
            maxGoal,
            minContribution,
            maxContribution,
            startTimestamp,
            endTimestamp,
            erc20TokenAddr,
            _feeCollector,
            _feeTransferBips,
            _feeYieldBips
        );

        emit Deployment(externalRef, deployment);

        return deployment;
    }

    /**
     * Owner Only: Transfer accumulated fees
     */
    function transferDeployFees(address recipient) external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No fees to collect");
        emit DeployFeeTransfer(recipient, amount);
        (bool sent,) = payable(recipient).call{value: amount}("");
        require(sent, "Failed to transfer Ether");
    }

    /**
     * Update the fee schedule for future deployments
     *
     * @param feeCollector the address of the fee collector, or the 0 address if no fees are collected
     * @param feeTransferBips the upfront fee in basis points, calculated during processing
     * @param feeYieldBips the payout fee in basis points. Dilutes the cap table for fee collection
     */
    function updateFeeSchedule(address feeCollector, uint16 feeTransferBips, uint16 feeYieldBips) external onlyOwner {
        _feeCollector = feeCollector;
        _feeTransferBips = feeTransferBips;
        _feeYieldBips = feeYieldBips;
        emit FeeScheduleChange(feeCollector, feeTransferBips, feeYieldBips);
    }

    /**
     * Update the deploy fee.
     *
     * @param minFeeAmount the amount of wei required to deploy a campaign
     */
    function updateMinimumDeployFee(uint256 minFeeAmount) external onlyOwner {
        _feeDeployMin = minFeeAmount;
        emit DeployFeeChange(minFeeAmount);
    }

    /**
     * Fetch the fee schedule for campaigns and the deploy fee
     */
    function feeSchedule() external view returns (address, uint16, uint16, uint256) {
        return (_feeCollector, _feeTransferBips, _feeYieldBips, _feeDeployMin);
    }
}
