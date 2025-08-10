# Runs the unit tests
unit    :; FOUNDRY_PROFILE=default forge test

# Runs the invariant tests
invar   :; FOUNDRY_PROFILE=invariant forge test

fuzz    :; FOUNDRY_PROFILE=fuzz forge test --fuzz-runs 1000000

# Runs the Tenderly integration tests
tenderly  :; FOUNDRY_PROFILE=tenderly forge test

fmt     :;  FOUNDRY_PROFILE=default forge fmt && FOUNDRY_PROFILE=mainnet forge fmt

lint    :;  solhint --fix --noPrompt test/**/*.sol && \
            solhint --fix --noPrompt src/**/*.sol && \
            solhint --fix --noPrompt script/**/*.sol

# Create the coverage report
# Coverage https://github.com/linux-test-project/lcov (brew install lcov)
cover   :;  FOUNDRY_PROFILE=default forge coverage --report lcov \
            --no-match-coverage "(test|script)" \
            --report-file default_coverage.info && \
            lcov --ignore-errors inconsistent \
            -a default_coverage.info -o lcov.info && \
            rm default_coverage.info && \
            genhtml lcov.info -o coverage/

# Show the coverage report
show    :;  npx http-server ./coverage

# Clean the coverage report
clean   :;  rm -rf coverage/

# Start anvil
node   :; anvil

# Kill anvil
kill-node    :; @pkill anvil 2>/dev/null || true

# Deploy local contracts
deploy    :; ./deploy-local.sh

test-localhost :; FOUNDRY_PROFILE=localhost forge test --match-path "test/localhost/LocalIntegration.t.sol" --rpc-url http://localhost:8545 -v


# Note: Required environment variables for Tenderly deployment:
# CONTRACT - The contract script to deploy
# ACCOUNT - The deployer account address
# TENDERLY_VIRTUAL_TESTNET_RPC_URL - RPC URL for Tenderly virtual testnet
# TENDERLY_ACCESS_KEY - API key for Tenderly contract verification
deploy-tenderly    :; forge script script/$(CONTRACT).s.sol:$(CONTRACT) \
                    --slow \
                    --verifier etherscan \
                    --verifier-url $(TENDERLY_VIRTUAL_TESTNET_RPC_URL)/verify/etherscan \
                    --account $(ACCOUNT) \
                    --rpc-url  $(TENDERLY_VIRTUAL_TESTNET_RPC_URL) \
                    --etherscan-api-key $(TENDERLY_ACCESS_KEY) \
                    --broadcast \
                    --verify

# Note: Required environment variables for Sepolia deployment:
# CONTRACT - The contract script to deploy
# ACCOUNT - The deployer account address
# BASE_SEPOLIA_RPC_URL - RPC URL for Base Sepolia network
# ETHERSCAN_API_KEY - API key for contract verification
deploy-script    :; forge script script/$(CONTRACT).s.sol:$(CONTRACT) \
                    --slow \
                    --account $(ACCOUNT) \
                    --rpc-url  $(RPC_URL) \
                    --etherscan-api-key $(ETHERSCAN_API_KEY) \
                    --broadcast \
                    --verify

deploy-contract   :; forge create \
                    --account $(ACCOUNT) \
                    --rpc-url  $(RPC_URL) \
                    --etherscan-api-key $(ETHERSCAN_API_KEY) \
                    --broadcast \
                    --verify \
                    src/$(CONTRACT).sol:$(CONTRACT)

# Note: Required environment variables for multisig transaction data:
# TARGET_ADDRESS - Address to grant/revoke the role to/from
# Optional variables:
# CONTRACT_ADDRESS - Address of the rewards contract (defaults to Sapien rewards)
# ROLE_ACTION - "grant" or "revoke" (default: "grant")
# USDC_REWARDS_ADDRESS - Address of USDC rewards contract
generate-role-tx  :; forge script script/UpdateRole.s.sol:UpdateRole \
                    --sig "run()" \
                    --rpc-url $(RPC_URL)

# Generate transaction data for batch role updates
generate-batch-tx :; forge script script/UpdateRole.s.sol:UpdateRole \
                    --sig "generateBatchRoleUpdate()" \
                    --rpc-url $(RPC_URL)

# Generate transaction data for role checking (read-only)
generate-check-tx :; forge script script/UpdateRole.s.sol:UpdateRole \
                    --sig "generateRoleCheckData()" \
                    --rpc-url $(RPC_URL)

# Show common scenarios and usage examples
role-scenarios    :; forge script script/UpdateRole.s.sol:UpdateRole \
                    --sig "generateCommonScenarios()" \
                    --rpc-url $(RPC_URL)

# Note: Required environment variables for BatchRewards deployment:
# Optional variables:
# SAPIEN_REWARDS_ADDRESS - Override default Sapien rewards contract address
# USDC_REWARDS_ADDRESS - Override default USDC rewards contract address (auto-detected for Base Sepolia)
deploy-batch-rewards :; forge script script/DeployBatchRewards.s.sol:DeployBatchRewards \
                    --account $(ACCOUNT) \
                    --rpc-url $(RPC_URL) \
                    --broadcast \
                    --verify

# Verify rewards contracts before deployment
verify-rewards-contracts :; forge script script/DeployBatchRewards.s.sol:DeployBatchRewards \
                    --sig "verifyRewardsContracts()" \
                    --rpc-url $(RPC_URL)

# Generate role update transactions for BatchRewards (requires BATCH_REWARDS_ADDRESS)
generate-batch-role-updates :; forge script script/DeployBatchRewards.s.sol:DeployBatchRewards \
                    --sig "generateRoleUpdates()" \
                    --rpc-url $(RPC_URL)