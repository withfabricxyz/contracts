// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@forge/Test.sol";
import "@forge/console2.sol";
import "src/subscriptions/SubscriptionNFTV1.sol";
import "src/tokens/ERC20Token.sol";
import "./BaseTest.t.sol";

contract SubscriptionNFTV1GrantsTest is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        manifest = createETHManifest(0, 0);
    }

    function testGrant() public {
        vm.startPrank(creator);
        manifest.grantTime(list(alice), 1e15);
        vm.stopPrank();

        assertEq(manifest.balanceOf(alice), 1e15);
        assertEq(manifest.refundableBalanceOf(alice), 0);

        mint(alice, 1e18);

        assertEq(manifest.balanceOf(alice), 1e15 + 1e18);
        // assertEq(manifest.refundableBalanceOf(alice), 1e18);
    }
}
