#!/bin/bash

# Tenderly Integration Test Runner
# This script runs all integration tests against deployed contracts on Tenderly Base mainnet fork

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_env_vars() {
    print_status "Checking environment variables..."
    
    if [ -z "$TENDERLY_VIRTUAL_TESTNET_RPC_URL" ]; then
        print_error "TENDERLY_VIRTUAL_TESTNET_RPC_URL environment variable is not set"
        echo "Please set it to your Tenderly Virtual Testnet RPC URL"
        exit 1
    fi
    
    if [ -z "$TENDERLY_ACCESS_KEY" ]; then
        print_warning "TENDERLY_ACCESS_KEY environment variable is not set"
        echo "This is optional but recommended for Etherscan verification"
    fi
    
    print_success "Environment variables checked"
}

# Test individual contracts
run_token_tests() {
    print_status "Running SapienToken integration tests..."
    forge test --profile integration --match-contract "TenderlyTokenIntegrationTest" -v
}

run_vault_tests() {
    print_status "Running SapienVault integration tests..."
    forge test --profile integration --match-contract "TenderlyVaultIntegrationTest" -v
}

run_rewards_tests() {
    print_status "Running SapienRewards integration tests..."
    forge test --profile integration --match-contract "TenderlyRewardsIntegrationTest" -v
}

run_qa_tests() {
    print_status "Running SapienQA integration tests..."
    forge test --profile integration --match-contract "TenderlyQAIntegrationTest" -v
}

run_multiplier_tests() {
    print_status "Running Multiplier integration tests..."
    forge test --profile integration --match-contract "TenderlyMultiplierIntegrationTest" -v
}

run_integration_tests() {
    print_status "Running comprehensive integration tests..."
    forge test --profile integration --match-contract "TenderlyIntegrationTest" -v
}

# Run all tests
run_all_tests() {
    print_status "Running all Tenderly integration tests..."
    
    echo "=================================================="
    echo "🚀 SAPIEN TENDERLY INTEGRATION TEST SUITE 🚀"
    echo "=================================================="
    echo ""
    
    # Check environment first
    check_env_vars
    echo ""
    
    # Run individual contract tests
    echo "📋 Running individual contract tests..."
    echo ""
    
    run_token_tests
    echo ""
    
    run_vault_tests
    echo ""
    
    run_rewards_tests
    echo ""
    
    run_qa_tests
    echo ""
    
    run_multiplier_tests
    echo ""
    
    # Run comprehensive integration tests
    echo "🔗 Running comprehensive integration tests..."
    echo ""
    
    run_integration_tests
    echo ""
    
    print_success "All integration tests completed!"
    echo ""
    echo "=================================================="
    echo "✅ TENDERLY INTEGRATION TESTS PASSED ✅"
    echo "=================================================="
}

# Run specific test function
run_specific_test() {
    local test_name=$1
    print_status "Running specific test: $test_name"
    forge test --profile integration --match-test "$test_name" -vv
}

# Show help
show_help() {
    echo "Tenderly Integration Test Runner"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  all                Run all integration tests (default)"
    echo "  token              Run SapienToken integration tests only"
    echo "  vault              Run SapienVault integration tests only"
    echo "  rewards            Run SapienRewards integration tests only"
    echo "  qa                 Run SapienQA integration tests only"
    echo "  multiplier         Run Multiplier integration tests only"
    echo "  integration        Run comprehensive integration tests only"
    echo "  test <TEST_NAME>   Run specific test function"
    echo "  help               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  TENDERLY_VIRTUAL_TESTNET_RPC_URL  Required: Tenderly Virtual Testnet RPC URL"
    echo "  TENDERLY_ACCESS_KEY               Optional: Tenderly access key for verification"
    echo ""
    echo "Examples:"
    echo "  $0 all                                          # Run all tests"
    echo "  $0 token                                        # Run only token tests"
    echo "  $0 test test_Integration_CompleteUserJourney    # Run specific test"
}

# Main script logic
case "${1:-all}" in
    "all")
        run_all_tests
        ;;
    "token")
        check_env_vars
        run_token_tests
        ;;
    "vault")
        check_env_vars
        run_vault_tests
        ;;
    "rewards")
        check_env_vars
        run_rewards_tests
        ;;
    "qa")
        check_env_vars
        run_qa_tests
        ;;
    "multiplier")
        check_env_vars
        run_multiplier_tests
        ;;
    "integration")
        check_env_vars
        run_integration_tests
        ;;
    "test")
        if [ -z "$2" ]; then
            print_error "Test name required. Usage: $0 test <TEST_NAME>"
            exit 1
        fi
        check_env_vars
        run_specific_test "$2"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac