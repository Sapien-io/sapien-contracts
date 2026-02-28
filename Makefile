
# ── Base Sepolia ────────────────────────────────────────────────────
# Prerequisites:
#   1. Import deployer key:  cast wallet import deployer --interactive
#   2. Set env vars:         BASE_SEPOLIA_RPC_URL, BASESCAN_API_KEY
#   3. (Optional)            SAPIEN_TOKEN=<addr>  to skip mock token deploy
#   4. (Optional)            TREASURY=<addr>      defaults to deployer
deploy-sepolia :;
	forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
		--account ${ACCOUNT} \
		--rpc-url ${RPC_URL} \
		--broadcast \
		--verify \
		-vvvv

# Dry-run (simulate without broadcasting)
deploy-sepolia-dry :;
	forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
		--account ${ACCOUNT} \
		--rpc-url ${RPC_URL} \
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



clean-modules :; git submodule update --init --recursive \
	&& git submodule foreach --recursive git clean -fd \
	&& git submodule foreach --recursive git checkout .
