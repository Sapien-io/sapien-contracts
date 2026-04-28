build   :; forge build
test    :; forge test
lint    :; forge lint src/
coverage:; forge coverage --ir-minimum

# ── Deploy ───────────────────────────────────────────────────────────────

# Base Sepolia: SAPIEN_TOKEN, ADMIN, BASE_SEPOLIA_RPC_URL, BASESCAN_API_KEY.
# Import key: cast wallet import deployer --interactive
deploy-sepolia     :; forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
	--rpc-url $${BASE_SEPOLIA_RPC_URL} \
	--account $${DEPLOYER} \
	--broadcast \
	--verify

deploy-sepolia-dry :; forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
	--rpc-url $${BASE_SEPOLIA_RPC_URL} \
	--account $${DEPLOYER} \

# Base mainnet: SAPIEN_TOKEN, ADMIN, BASE_MAINNET_RPC_URL, BASESCAN_API_KEY.
deploy-base     :; forge script script/DeployBase.s.sol:DeployBase \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account deployer \
	--broadcast \
	--verify
deploy-base-dry :; forge script script/DeployBase.s.sol:DeployBase \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account deployer

# Base mainnet (token + vault)
deploy-base-full :; forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account $${DEPLOYER_ADDRESS} \
	--verify \
	--broadcast
deploy-base-full-dry :; forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account $${DEPLOYER_ADDRESS}
