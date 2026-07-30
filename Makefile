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

# ── Fork tests (anvil) ───────────────────────────────────────────────────
# Sepolia V1→V2 upgrade rehearsal against the retired proxy 0x58E72Fa7…,
# pinned one block before the on-chain upgrade (44794237). Requires
# BASE_SEPOLIA_RPC_URL (or FORK_RPC_URL pointing at a running anvil).
#
#   make anvil-sepolia-upgrade   # start anvil forked at the V1 tip
#   make test-fork-sepolia       # run SepoliaUpgradeFork against it
anvil-sepolia-upgrade :; anvil --fork-url $${BASE_SEPOLIA_RPC_URL} --fork-block-number 44794237 --port 8545
test-fork-sepolia :; FORK_RPC_URL=$${FORK_RPC_URL:-http://127.0.0.1:8545} FORK_BLOCK=$${FORK_BLOCK:-0} \
	forge test --match-path test/fork/SepoliaUpgradeFork.t.sol -vvv
test-fork-mainnet :; forge test --match-path test/fork/UpgradeFork.t.sol -vvv

