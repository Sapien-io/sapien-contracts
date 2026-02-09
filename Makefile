

deploy-sepolia :;
	forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
	--account 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59 \
	--rpc-url ${RPC_URL} \
	--broadcast \
	--verify
	-vvvv



deploy-local :;
	@./script/deploy-local.sh

coverage :; forge coverage --ir-minimum