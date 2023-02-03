// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "./util/TestHelper.sol";
import "src/finance/ERC20CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "src/finance/EthCrowdFinancingV1.sol";
import "src/finance/DataQuiltRegistryV1.sol";

contract DataQuiltRegistryV1Test is TestHelper {
    DataQuiltRegistryV1 internal registry;

    function generateId(address addr, uint32 variant) public returns (uint256) {
        return uint256(bytes32(abi.encodePacked(addr, uint64(0), variant)));
    }

    function setUp() public {
        registry = new DataQuiltRegistryV1("TEST", "TEST", "https://art.meow.com/");
        deal(depositor, 1e19);
    }

    function testInvalidAddress() public {
        uint256 id = generateId(beneficiary, uint32(0xff));
        vm.expectRevert();
        registry.mintContributionToken(id);
    }

    function testMintWithoutDeposits() public {
        EthCrowdFinancingV1 cf = createETHCampaign();
        uint256 id = generateId(address(cf), uint32(0xff));
        vm.expectRevert("Err: 100, No deposits registered");
        registry.mintContributionToken(id);
    }

    function testMintWithDeposits() public {
        EthCrowdFinancingV1 cf = createETHCampaign();
        uint256 id = generateId(address(cf), uint32(0xff));

        depositEth(cf, depositor, 1e18);
        vm.startPrank(depositor);
        assert(registry.canMint(address(cf)));
        registry.mintContributionToken(id);

        assertEq(1, registry.balanceOf(depositor));
        assertEq(
            "https://art.meow.com/20868766820000560018335248259782891309437497197130732538605701684905228894463",
            registry.tokenURI(id)
        );

        assert(!registry.canMint(address(cf)));
        vm.expectRevert("Err: 101, already minted");
        registry.mintContributionToken(id);
        vm.expectRevert("Err: 101, already minted");
        registry.mintContributionToken(id + 1);
    }

    function testERC20MintWithDeposits() public {
        ERC20CrowdFinancingV1 cf = createERC20Campaign();
        uint256 id = generateId(address(cf), uint32(0xff));
        dealTokens(ERC20Token(cf.tokenAddress()), depositor, 1e18);
        depositTokens(cf, depositor, 1e18);
        vm.startPrank(depositor);
        registry.mintContributionToken(id);
        assertEq(1, registry.balanceOf(depositor));
    }
}
