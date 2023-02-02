# Fabric Smart Contracts

### Setup

Foundry tooling is used for testing and compiling contracts. Run the setup
script to install and update it.

```
./script/setup
```

### Testing

```
forge test -vvv
```

Other useful tools

```
forge coverage
forge fmt
```

### Signing Commits

All commits and tags for this repository should be signed.

### Deployment Example (Finance + Ledger + Goerli)

Before you can use ledger with forge, you must enable blind signing... and then *disable blind signing!* after
completing the deployment.

```
forge create EthCrowdFinancingV1 --ledger --rpc-url https://goerli.infura.io/v3/KEY
```

Upon running the transaction, approve the transaction on the ledger and wait for the address. The contract was deployed
to: 0x3DbadAE2e93b8A8d49123afC359eB580905B9E5A [View TX](https://goerli.etherscan.io/tx/0x6860b867842af3192f58bde608387972657fe15612968d65c2fe26bcf1d43f87)

Then, deploy the beacon

```
forge create FabricBeacon --ledger --rpc-url https://goerli.infura.io/v3/KEY --constructor-args 0x3DbadAE2e93b8A8d49123afC359eB580905B9E5A
```

Beacon was deployed to: 0xD6e48BC68D194d617E101D12eE712a0744f3f522 [View TX](https://goerli.etherscan.io/tx/0x6029c19977b3f413adbafbe46274ea3aea4fbb8267646f4bf6ff19e0e34b6374)

#### Repeat for the ERC20 variant

Goerli ERC20 Logic Contract: [0xEd818B4b66F4da1a86F0bDdBaDFB1e7dF9b61B51](https://goerli.etherscan.io/address/0xEd818B4b66F4da1a86F0bDdBaDFB1e7dF9b61B51)
Goerli ERC20 Beacon Contract: [0xD0884D249B74B7E6C433bB4130a9d3FCa309170E](https://goerli.etherscan.io/address/0xD0884D249B74B7E6C433bB4130a9d3FCa309170E)