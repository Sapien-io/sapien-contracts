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
deploy-sepolia    :; forge script script/$(CONTRACT).s.sol:$(CONTRACT) \
                    --slow \
                    --account $(ACCOUNT) \
                    --rpc-url  $(BASE_SEPOLIA_RPC_URL) \
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