#!/bin/bash

set -e

ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_HOST="${ANVIL_HOST:-http://localhost:8545}"
RPC_ARGS=(--private-key ${ANVIL_KEY} --rpc-url ${ANVIL_HOST} --json)

echo "Deploying crowdfund contracts to ${ANVIL_HOST}"

########

TOKEN_ADDRESS=$(forge create ERC20Token --constructor-args "USD Token" "USDC" "100000000000" ${RPC_ARGS[@]} | jq -r .deployedTo)
echo "Deployed Faux USDC Token @ ${TOKEN_ADDRESS}"

LOGIC_ADDRESS=$(forge create CrowdFinancingV1 ${RPC_ARGS[@]} | jq -r .deployedTo)
echo "Deployed CampaignFinancingV1 Logic Contract @ ${LOGIC_ADDRESS}"

DEPLOYER_ADDRESS=$(forge create CrowdFinancingV1Factory --constructor-args ${LOGIC_ADDRESS} ${RPC_ARGS[@]} | jq -r .deployedTo)
echo "Deployed CampaignFinancingV1 Factory Contract @ ${DEPLOYER_ADDRESS}"

QUILT_NFT_ADDRESS=$(forge create DataQuiltRegistryV1 --constructor-args "Fabric Quilts" "FABQ" "http://localhost:3000/api/nft/" ${RPC_ARGS[@]} | jq -r .deployedTo)
echo "Deployed Quilt NFT @ ${QUILT_NFT_ADDRESS}"

#########

DEPLOY_SIG="deployCampaign(address,uint256,uint256,uint256,uint256,uint32,uint32,address)"
DEPLOY_ARGS=(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 100000000000 100000000000000000 1 1000000000 0 1800)
ETH_CONTRACT=$(cast send ${DEPLOYER_ADDRESS} "${DEPLOY_SIG}" ${DEPLOY_ARGS[@]} 0x0000000000000000000000000000000000000000 ${RPC_ARGS[@]} | jq -r '.logs[0].address')
echo "Deployed ETH Campaign @ ${ETH_CONTRACT}"

ERC20_CONTRACT=$(cast send ${DEPLOYER_ADDRESS} "${DEPLOY_SIG}" ${DEPLOY_ARGS[@]} ${TOKEN_ADDRESS} ${RPC_ARGS[@]} | jq -r '.logs[0].address')
echo "Deployed ERC20 Campaign @ ${ERC20_CONTRACT}"
echo
echo "---------------"
echo
echo "ERC20 Example: cast call ${ERC20_CONTRACT} 'isContributionAllowed()' --rpc-url http://localhost:8545"
echo "  ETH Example: cast call ${ETH_CONTRACT} 'isContributionAllowed()' --rpc-url http://localhost:8545"