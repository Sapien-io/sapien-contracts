build   :; forge build
test    :; forge test
lint    :; forge lint src/
coverage:; forge coverage

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

# ── Fork tests ───────────────────────────────────────────────────────────
# Live V2 invariants against the current proxies. Suites skip when the RPC
# env var is unset so local/CI stays green.
#
#   make test-fork-mainnet    # requires BASE_MAINNET_RPC_URL
#   make test-fork-sepolia    # requires BASE_SEPOLIA_RPC_URL (or FORK_RPC_URL)
test-fork-sepolia :; forge test --match-path test/fork/SepoliaUpgradeFork.t.sol -vvv
test-fork-sepolia-loop :; forge test --match-path test/fork/SepoliaCollateralLoop.t.sol -vvv
test-fork-mainnet :; forge test --match-path test/fork/UpgradeFork.t.sol -vvv

# ── Sepolia ENGINE_ROLE grant ──────────────────────────────────────────
# Staging engine signer only. Script refuses the mainnet vault.
# Requires: SEPOLIA_ENGINE, BASE_SEPOLIA_RPC_URL. See script/README.md.
grant-engine-sepolia-calldata :; forge script script/GrantEngineRole.s.sol:GrantEngineRole \
	--rpc-url $${BASE_SEPOLIA_RPC_URL}
grant-engine-sepolia-execute :; EXECUTE=true forge script script/GrantEngineRole.s.sol:GrantEngineRole \
	--rpc-url $${BASE_SEPOLIA_RPC_URL} \
	--account $${DEPLOYER} \
	--broadcast
grant-engine-sepolia-verify :; VERIFY_ONLY=true forge script script/GrantEngineRole.s.sol:GrantEngineRole \
	--rpc-url $${BASE_SEPOLIA_RPC_URL}

