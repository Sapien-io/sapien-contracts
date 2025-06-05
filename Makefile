# Runs the unit tests
unit    :; FOUNDRY_PROFILE=default forge test

# Runs the invariant tests
invar   :; FOUNDRY_PROFILE=invariant forge test

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

# Run Tenderly integration tests
test-tenderly    :; ./script/run-tenderly-tests.sh


# CONTRACT=
# ACCOUNT=
# TENDERLY_VIRTUAL_TESTNET_RPC_URL=
# TENDERLY_ACCESS_KEY=
deploy-tenderly    :; forge script script/$(CONTRACT).s.sol:$(CONTRACT) \
                    --slow \
                    --verifier etherscan \
                    --verifier-url $(TENDERLY_VIRTUAL_TESTNET_RPC_URL)/verify/etherscan \
                    --account $(ACCOUNT) \
                    --rpc-url  $(TENDERLY_VIRTUAL_TESTNET_RPC_URL) \
                    --etherscan-api-key $(TENDERLY_ACCESS_KEY) \
                    --broadcast \
                    --verify

# CONTRACT=
# ACCOUNT=
# BASE_SEPOLIA_RPC_URL=
# ETHERSCAN_API_KEY=
deploy-sepolia    :; forge script script/$(CONTRACT).s.sol:$(CONTRACT) \
                    --slow \
                    --account $(ACCOUNT) \
                    --rpc-url  $(BASE_SEPOLIA_RPC_URL) \
                    --etherscan-api-key $(ETHERSCAN_API_KEY) \
                    --broadcast \
                    --verbosity -vv \
                    --verify                    