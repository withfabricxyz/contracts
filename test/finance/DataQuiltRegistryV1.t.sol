// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "./CrowdFinancingV1/BaseCampaignTest.t.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "src/finance/DataQuiltRegistryV1.sol";

contract DataQuiltRegistryV1Test is BaseCampaignTest {
    DataQuiltRegistryV1 internal registry;

    function generateId(address addr, uint32 variant) public pure returns (uint256) {
        return uint256(bytes32(abi.encodePacked(addr, uint64(0), variant)));
    }

    function setUp() public {
        registry = new DataQuiltRegistryV1("TEST", "TEST", "https://art.meow.com/");
        deal(alice, 1e19);
    }

    function testInvalidAddress() public {
        uint256 id = generateId(recipient, uint32(0xff));
        vm.expectRevert();
        registry.mint(id);
    }

    function testMintWithoutContribution() public ethTest {
        uint256 id = generateId(address(campaign()), uint32(0xff));
        vm.expectRevert("Err: already minted or contribution not found");
        registry.mint(id);
    }

    function testMintWithContribution() public ethTest {
        uint256 id = generateId(address(campaign()), uint32(0xff));

        deposit(alice, 1e18);
        vm.startPrank(alice);
        assert(registry.canMint(address(campaign()), alice));
        registry.mint(id);

        assertEq(1, registry.balanceOf(alice));
        assertEq(
            "https://art.meow.com/20868766820000560018335248259782891309437497197130732538605701684905228894463",
            registry.tokenURI(id)
        );

        assert(!registry.canMint(address(campaign()), alice));
        vm.expectRevert("Err: already minted or contribution not found");
        registry.mint(id);
        vm.expectRevert("Err: already minted or contribution not found");
        registry.mint(id + 1);
    }
}
