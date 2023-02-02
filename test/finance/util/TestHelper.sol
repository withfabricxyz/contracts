// SPDX-License-Identifier: UNLICENSED

import "@forge/Test.sol";
import "@forge/console2.sol";

import "src/finance/ERC20CrowdFinancingV1.sol";
import "src/tokens/ERC20Token.sol";
import "src/finance/EthCrowdFinancingV1.sol";
import "src/finance/DataQuiltRegistryV1.sol";

contract TestHelper is Test {
    address payable internal beneficiary = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal depositor = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;

    function createERC20Token() public virtual returns (ERC20Token) {
        return new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
    }

    function dealTokens(ERC20Token token, address addr, uint256 tokens) public {
        token.transfer(addr, tokens);
    }

    function depositTokens(ERC20CrowdFinancingV1 _campaign, address _depositor, uint256 amount) public {
        vm.startPrank(_depositor);
        ERC20Token(_campaign.tokenAddress()).approve(address(_campaign), amount);
        _campaign.deposit(amount);
        vm.stopPrank();
    }

    function createERC20Campaign() public virtual returns (ERC20CrowdFinancingV1) {
        ERC20Token token = createERC20Token();
        ERC20CrowdFinancingV1 campaign = new ERC20CrowdFinancingV1();

        // unmark initialzied, eg: campaign._initialized = 0;
        vm.store(address(campaign), bytes32(uint256(0)), bytes32(0));
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + 60 * 60,
            address(token),
            address(0),
            0,
            0
        );

        return campaign;
    }

    function createETHCampaign() public virtual returns (EthCrowdFinancingV1) {
        EthCrowdFinancingV1 campaign = new EthCrowdFinancingV1();

        vm.store(address(campaign), bytes32(uint256(0)), bytes32(0));
        campaign.initialize(
            beneficiary,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + 60 * 60,
            address(0),
            0,
            0
        );

        return campaign;
    }

    function depositEth(EthCrowdFinancingV1 _campaign, address _depositor, uint256 amount) public virtual {
        vm.startPrank(_depositor);
        (bool success, bytes memory data) =
            address(_campaign).call{value: amount, gas: 700000}(abi.encodeWithSignature("deposit()"));
        vm.stopPrank();

        if (!success) {
            if (data.length == 0) revert();
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }
}
