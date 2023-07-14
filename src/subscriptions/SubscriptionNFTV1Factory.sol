// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SubscriptionNFTV1.sol";

/**
 *
 * @title Fabric Manifest NFT Subscriptions Factory Contract
 * @author Fabric Inc.
 *
 * @dev A factory which leverages Clones to deploy Fabric Manifest Subscription NFT contracts
 *
 */
contract SubscriptionNFTV1Factory is Ownable {
    modifier feeRequired() {
        require(msg.value >= _feeDeployMin, "Insufficient ETH to deploy");
        _;
    }

    /// @dev Emitted upon a successful Campaign deployment
    event Deployment(address indexed deployment);

    /// @dev Emitted when the fee collector or schedule changes
    event FeeScheduleChange(address feeCollector, uint16 feeBips);

    /// @dev Emitted when the creation fee minium changes
    event DeployFeeChange(uint256 fee);

    /// @dev Emitted when the deploy fees are collected by the owner
    event DeployFeeTransfer(address indexed recipient, uint256 fee);

    /// @dev The campaign contract implementation address
    address immutable _implementation;

    /// @dev The fee collector address (can be 0, no fees are collected)
    address private _feeCollector;

    /// @dev The transfer fee (See CrowdFinancingV1)
    uint16 private _feeBips;

    /// @dev Fee to collect upon deployment
    uint256 private _feeDeployMin;

    /**
     * @param implementation the CrowdFinancingV1 implementation address
     */
    constructor(address implementation) Ownable() {
        _implementation = implementation;
        _feeCollector = address(0);
        _feeBips = 0;
        _feeDeployMin = 0;
    }

    function deploySubscriptionNFT(
        string memory name,
        string memory symbol,
        string memory baseUri,
        uint256 tokensPerSecond,
        address erc20TokenAddr
    ) external payable feeRequired returns (address) {
        address deployment = Clones.clone(_implementation);
        SubscriptionNFTV1(payable(deployment)).initialize(
            name, symbol, baseUri, msg.sender, tokensPerSecond, 0, _feeBips, _feeCollector, erc20TokenAddr
        );
        emit Deployment(deployment);
        return deployment;
    }

    /**
     * @dev Owner Only: Transfer accumulated fees
     */
    function transferDeployFees(address recipient) external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No fees to collect");
        emit DeployFeeTransfer(recipient, amount);
        (bool sent,) = payable(recipient).call{value: amount}("");
        require(sent, "Failed to transfer Ether");
    }

    /**
     * @dev Owner Only: Update the fee schedule for future deployments
     *
     * @param feeCollector the address of the fee collector, or the 0 address if no fees are collected
     * @param feeBips the fee in basis points, allocated during withdraw
     */
    function updateFeeSchedule(address feeCollector, uint16 feeBips) external onlyOwner {
        _feeCollector = feeCollector;
        _feeBips = feeBips;
        emit FeeScheduleChange(feeCollector, _feeBips);
    }

    /**
     * @dev Owner Only: Update the deploy fee.
     *
     * @param minFeeAmount the amount of wei required to deploy a campaign
     */
    function updateMinimumDeployFee(uint256 minFeeAmount) external onlyOwner {
        _feeDeployMin = minFeeAmount;
        emit DeployFeeChange(minFeeAmount);
    }

    /**
     * @dev Fetch the fee schedule for campaigns and the deploy fee
     *
     * @return collector the address of the fee collector, or the 0 address if no fees are collected
     * @return feeBips the fee in basis points, allocated during withdraw
     * @return deployFee the amount of wei required to deploy a campaign
     */
    function feeSchedule() external view returns (address collector, uint16 feeBips, uint256 deployFee) {
        return (_feeCollector, _feeBips, _feeDeployMin);
    }
}
