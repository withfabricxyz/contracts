// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "src/CrowdFinancing.sol";

contract CrowdFinancingTest is Test {
    CrowdFinancing internal campaign;
    address payable internal beneficiary = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal depositor = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal depositor2 = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal depositor3 = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;

    function revertFromReturnedData(bytes memory returnedData) internal pure {
        if (returnedData.length < 4) {
            // case 1: catch all
            revert("CallUtils: target revert()");
        } else {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(returnedData, 0x20))
            }
            if (errorSelector == bytes4(0x4e487b71) /* `seth sig "Panic(uint256)"` */) {
                // case 2: Panic(uint256) (Defined since 0.8.0)
                // solhint-disable-next-line max-line-length
                // ref: https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require)
                string memory reason = "CallUtils: target panicked: 0x__";
                uint errorCode;
                assembly {
                    errorCode := mload(add(returnedData, 0x24))
                    let reasonWord := mload(add(reason, 0x20))
                    // [0..9] is converted to ['0'..'9']
                    // [0xa..0xf] is not correctly converted to ['a'..'f']
                    // but since panic code doesn't have those cases, we will ignore them for now!
                    let e1 := add(and(errorCode, 0xf), 0x30)
                    let e2 := shl(8, add(shr(4, and(errorCode, 0xf0)), 0x30))
                    reasonWord := or(
                        and(reasonWord, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000),
                        or(e2, e1))
                    mstore(add(reason, 0x20), reasonWord)
                }
                revert(reason);
            } else {
                // case 3: Error(string) (Defined at least since 0.7.0)
                // case 4: Custom errors (Defined since 0.8.0)
                uint len = returnedData.length;
                assembly {
                    revert(add(returnedData, 32), len)
                }
            }
        }
    }

    function deposit(address _depositor, uint256 amount) public {
      vm.startPrank(_depositor);
      (bool success, bytes memory data) = address(campaign).call{ value: amount, gas: 700000 }(
        abi.encodeWithSignature("deposit()")
      );
      vm.stopPrank();

      if(!success) {
        if (data.length == 0) revert();
        assembly {
            revert(add(32, data), mload(data))
        }
        // revertFromReturnedData(data);
      }
    }

    function setUp() public {
      campaign = new CrowdFinancing(
        beneficiary,
        2e18, // 2ETH
        5e18, // 5ETH
        2e17, // 0.2ETH
        1e18  // 1ETH
      );
    }

    function testInitialDeployment() public {
      assertFalse(campaign.withdrawalAllowed());
      assertEq(0, campaign.amountRaised());
    }

    function testEmptyDeposit() public {
      vm.expectRevert("Deposit requires funds");
      vm.startPrank(depositor);
      deal(depositor, 1e18);
      campaign.deposit();
    }

    function testDeposit() public {
      deal(depositor, 10e18);
      deposit(depositor, 1e18);
      assertEq(1e18, address(campaign).balance);
      assertEq(1e18, campaign.amountRaised());
      assertEq(1e18, campaign.amountFunded(depositor));
    }

    function testLargeDeposit() public {
      vm.expectRevert("Deposit amount is too high");
      deal(depositor, 10e18);
      deposit(depositor, 6e18);
    }

    function testSmallDeposit() public {
      vm.expectRevert("Deposit amount is too low");
      deal(depositor, 1e18);
      deposit(depositor, 1e12);
    }

    function testManyDeposits() public {
      deal(depositor, 9e18);
      deposit(depositor, 9e17);
      deposit(depositor, 1e17);
      assertEq(1e18, campaign.amountRaised());
      assertEq(1e18, campaign.amountFunded(depositor));
      vm.expectRevert("Deposit amount is too high");
      deposit(depositor, 1e17);
    }

    function testManyDepositsFromMany() public {
      deal(depositor, 3e18);
      deal(depositor2, 3e18);
      deal(depositor3, 3e18);
      assertEq(0, campaign.amountRaised());
      deposit(depositor, 1e18);
      deposit(depositor2, 1e18);
      deposit(depositor3, 1e18);
      assertEq(3e18, address(campaign).balance);
      assertTrue(campaign.fundTargetMet());
    }

    function testDepositWithBadBalance() public {
      vm.expectRevert();
      // vm.startPrank(depositor);
      deposit(depositor, 1e18);
    }
}
