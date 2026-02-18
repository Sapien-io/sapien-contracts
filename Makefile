

deploy-sepolia :;
	forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
	--account 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59 \
	--rpc-url ${RPC_URL} \
	--broadcast \
	--verify
	-vvvv



deploy-local :;
	@./script/deploy-local.sh

# Start Anvil with raised code-size-limit (QualityEngine exceeds default 24KB)
anvil :;
	anvil --code-size-limit 50000

deploy-anvil :;
	forge script script/DeployAnvil.s.sol:DeployAnvil \
		--rpc-url http://localhost:8545 \
		--broadcast \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

coverage :; forge coverage --ir-minimum

lint     :; forge lint src/

build    :; forge build