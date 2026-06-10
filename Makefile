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

# ── Upgrade (UUPS) ───────────────────────────────────────────────────────
# Requires: VAULT_PROXY, VAULT_ADMIN, and the network RPC URL. See script/README.md.
#   *-calldata : deploy new impl + print upgradeToAndCall calldata for the Safe
#   *-execute  : deploy + upgrade directly (broadcaster must hold the admin role)
#   *-verify   : read-only post-upgrade state assertions (run after the Safe executes)

upgrade-base-calldata :; forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account deployer \
	--broadcast \
	--verify
upgrade-base-execute :; EXECUTE=true forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_MAINNET_RPC_URL} \
	--account deployer \
	--broadcast \
	--verify
upgrade-base-verify :; VERIFY_ONLY=true forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_MAINNET_RPC_URL}

upgrade-sepolia-calldata :; forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_SEPOLIA_RPC_URL} \
	--account $${DEPLOYER} \
	--broadcast \
	--verify
upgrade-sepolia-execute :; EXECUTE=true forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_SEPOLIA_RPC_URL} \
	--account $${DEPLOYER} \
	--broadcast \
	--verify
upgrade-sepolia-verify :; VERIFY_ONLY=true forge script script/UpgradeVault.s.sol:UpgradeVault \
	--rpc-url $${BASE_SEPOLIA_RPC_URL}
