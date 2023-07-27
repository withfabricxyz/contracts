// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "src/tokens/ERC20Token.sol";
import "src/finance/CrowdFinancingV1.sol";
import "src/finance/DataQuiltRegistryV1.sol";

import "@forge/Test.sol";
import "@forge/console2.sol";

abstract contract BaseCampaignTest is Test {
    event Contribution(address indexed account, uint256 numTokens);
    event TransferContributions(address indexed account, uint256 numTokens);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Withdraw(address indexed account, uint256 numTokens);
    event Fail();

    modifier prank(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    modifier ethTest() {
        __campaign = createETHCampaign();
        _;
    }

    modifier erc20Test() {
        __campaign = createERC20Campaign();
        _;
    }

    modifier multiTokenTest() {
        __campaign = createERC20Campaign();
        _;
        __campaign = createETHCampaign();
        _;
    }

    modifier multiTokenFeeTest(uint16 upfrontFee, uint16 payoutFee) {
        __campaign = createFeeCampaign(address(0), feeCollector, upfrontFee, payoutFee);
        _;
        ERC20Token _token = createERC20Token();
        __campaign = createFeeCampaign(address(_token), feeCollector, upfrontFee, payoutFee);
        _;
    }

    CrowdFinancingV1 private __campaign;

    uint256 internal expirationFuture = 70000;
    address payable internal recipient = payable(0xB4c79DAb8f259C7aeE6e5B2aa729821864227e83);
    address internal alice = 0xb4c79DAB8f259c7Aee6E5b2aa729821864227E81;
    address internal bob = 0xB4C79DAB8f259C7aEE6E5B2aa729821864227E8a;
    address internal charlie = 0xb4C79Dab8F259C7AEe6e5b2Aa729821864227e7A;
    address internal doug = 0xB4c79DAB8f259C7AEE6e5B2Aa729821764227E8A;
    address internal elliot = 0xB4C79DAB8f259c7Aee6E5b2AA729821764227e7A;
    address internal broke = 0xC4C79dAB8F259C7Aee6e5B2aa729821864227e81;
    address internal feeCollector = 0xC4c79dAb8F259c7AEE6e5b2aA729821864227E87;

    function buildCampaign() internal virtual returns (CrowdFinancingV1) {
        return createETHCampaign();
    }

    function token() internal returns (ERC20Token) {
        if (!campaign().isEthDenominated()) {
            return ERC20Token(campaign().erc20Address());
        }
        revert("Token isn't available for ETH contracts");
    }

    function balance(address account) internal returns (uint256) {
        if (!campaign().isEthDenominated()) {
            return token().balanceOf(account);
        }
        return account.balance;
    }

    function deposit(address account, uint256 amount) internal prank(account) {
        if (!campaign().isEthDenominated()) {
            token().approve(address(campaign()), amount);
            return campaign().contributeERC20(amount);
        } else {
            return campaign().contributeEth{value: amount}();
        }
    }

    function yield(address account, uint256 amount) internal prank(account) {
        if (!campaign().isEthDenominated()) {
            token().approve(address(campaign()), amount);
            campaign().yieldERC20(amount);
        } else {
            campaign().yieldEth{value: amount}();
        }
    }

    function yield(uint256 amount) internal {
        yield(recipient, amount);
    }

    function withdraw(address account) internal prank(account) {
        campaign().withdraw();
    }

    function dealDenomination(address account, uint256 amount) internal {
        if (!campaign().isEthDenominated()) {
            token().transfer(account, amount);
        } else {
            deal(account, amount);
        }
    }

    function campaign() internal returns (CrowdFinancingV1) {
        if (address(__campaign) == address(0)) {
            __campaign = buildCampaign();
        }
        return __campaign;
    }

    function assignCampaign(CrowdFinancingV1 _campaign) internal {
        __campaign = _campaign;
    }

    function createERC20Campaign() public virtual returns (CrowdFinancingV1) {
        ERC20Token _token = createERC20Token();
        return createCampaign(address(_token));
    }

    function createETHCampaign() public virtual returns (CrowdFinancingV1) {
        return createCampaign(address(0));
    }

    function createCampaign(address _token) public virtual returns (CrowdFinancingV1) {
        return createFeeCampaign(_token, address(0), 0, 0);
    }

    function createFeeCampaign(address _token, address collector, uint16 upfrontBips, uint16 payoutBips)
        public
        virtual
        returns (CrowdFinancingV1)
    {
        return createConfiguredCampaign(recipient, _token, collector, upfrontBips, payoutBips);
    }

    function createConfiguredCampaign(
        address _recipient,
        address _token,
        address collector,
        uint16 upfrontBips,
        uint16 payoutBips
    ) public virtual returns (CrowdFinancingV1) {
        CrowdFinancingV1 c = new CrowdFinancingV1();

        vm.store(address(c), bytes32(uint256(0)), bytes32(0));
        c.initialize(
            _recipient,
            2e18, // 2ETH
            5e18, // 5ETH
            2e17, // 0.2ETH
            1e18, // 1ETH
            block.timestamp,
            block.timestamp + expirationFuture,
            _token,
            collector,
            upfrontBips,
            payoutBips
        );

        return c;
    }

    function dealAll() internal {
        dealMulti(alice, 1e19);
        dealMulti(bob, 1e19);
        dealMulti(charlie, 1e19);
        dealMulti(doug, 1e19);
        dealMulti(elliot, 1e19);
    }

    function dealMulti(address addr, uint256 tokens) internal {
        deal(addr, tokens);
        dealDenomination(addr, tokens);
    }

    function createERC20Token() internal returns (ERC20Token) {
        return new ERC20Token(
        "FIAT",
        "FIAT",
        1e21
      );
    }

    function fundAndTransfer() internal {
        fundAndEnd();
        campaign().transferBalanceToRecipient();
    }

    function fundAndEnd() internal {
        dealAll();
        deposit(alice, 1e18);
        deposit(bob, 1e18);
        deposit(charlie, 1e18);
        vm.warp(campaign().endsAt());
    }

    function fullyFund() internal {
        dealAll();
        deposit(alice, 1e18);
        deposit(bob, 1e18);
        deposit(charlie, 1e18);
        deposit(doug, 1e18);
        deposit(elliot, 1e18);
    }

    function fundAndTransferEarly() internal {
        fullyFund();
        campaign().transferBalanceToRecipient();
    }

    function fundAndFail() internal {
        dealAll();
        deposit(alice, 1e18);
        vm.warp(campaign().endsAt());
    }

    function testIgnore() internal {}
}
