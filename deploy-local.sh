#!/bin/bash

# Deploy Sapien Contracts to Local Anvil Node
# This script deploys all Sapien contracts to a local Anvil instance in the correct order

set -e  # Exit on any error

# Colors for output - default to no colors for compatibility
RED=''
GREEN=''
YELLOW=''
BLUE=''
NC=''

# Enable colors if explicitly requested or if we detect good support
if [ "$FORCE_COLOR" = "1" ] || [ "$FORCE_COLOR" = "true" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
elif [ -t 1 ] && [ "$TERM" != "dumb" ] && [ -n "$TERM" ]; then
    # Conservative color detection for known good terminals
    case "$TERM" in
        xterm-256color|screen-256color|tmux-256color)
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            YELLOW='\033[1;33m'
            BLUE='\033[0;34m'
            NC='\033[0m'
            ;;
    esac
fi

# Default configuration
ANVIL_PORT=${ANVIL_PORT:-8545}
ANVIL_HOST=${ANVIL_HOST:-127.0.0.1}
RPC_URL="http://$ANVIL_HOST:$ANVIL_PORT"
PRIVATE_KEY=${PRIVATE_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}  # Default Anvil account 0
CHAIN_ID=31337

# Deployment contracts in order
CONTRACTS=(
    "DeployToken"
    "DeployTimelock" 
    "DeployQA"
    "DeployRewards"
    "DeployVault"
)

# Function to print colored output
print_status() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Anvil is running
check_anvil() {
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "$RPC_URL" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to start Anvil
start_anvil() {
    print_status "Starting Anvil on port $ANVIL_PORT..."
    
    # Check if port is already in use
    if lsof -Pi :$ANVIL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port $ANVIL_PORT is already in use"
        if check_anvil; then
            print_success "Anvil is already running on port $ANVIL_PORT"
            return 0
        else
            print_error "Port $ANVIL_PORT is occupied by another process"
            return 1
        fi
    fi
    
    # Start Anvil in background
    anvil --port $ANVIL_PORT --host $ANVIL_HOST --chain-id $CHAIN_ID >/dev/null 2>&1 &
    ANVIL_PID=$!
    
    # Wait for Anvil to be ready
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if check_anvil; then
            print_success "Anvil started successfully (PID: $ANVIL_PID)"
            return 0
        fi
        print_status "Waiting for Anvil to start (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Failed to start Anvil after $max_attempts attempts"
    return 1
}

# Function to deploy a single contract
deploy_contract() {
    local contract_name=$1
    print_status "Deploying $contract_name..."
    
    if forge script "script/${contract_name}.s.sol:${contract_name}" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        --legacy \
        -v 2>&1 | tee "/tmp/${contract_name}_deploy.log"; then
        print_success "$contract_name deployed successfully"
        return 0
    else
        print_error "Failed to deploy $contract_name"
        print_error "Check log: /tmp/${contract_name}_deploy.log"
        return 1
    fi
}

# Function to extract deployed addresses from logs
extract_addresses() {
    print_status "Extracting deployed contract addresses..."
    
    local addresses_file="deployments/local-addresses.txt"
    echo "Local Anvil Deployment - $(date)" > "$addresses_file"
    echo "============================================" >> "$addresses_file"
    echo "" >> "$addresses_file"
    
    # Extract addresses from deployment logs
    for contract in "${CONTRACTS[@]}"; do
        local log_file="/tmp/${contract}_deploy.log"
        if [ -f "$log_file" ]; then
            echo "== $contract Logs ==" >> "$addresses_file"
            grep -E "(deployed at|Proxy deployed at):" "$log_file" >> "$addresses_file" 2>/dev/null || true
            echo "" >> "$addresses_file"
        fi
    done
    
    print_success "Deployment addresses saved to $addresses_file"
}

# Function to update a specific contract address in LocalContracts
update_single_contract_address() {
    local contract_type=$1
    local contract_addr=$2
    
    if [[ -z "$contract_addr" ]]; then
        print_error "No address provided for $contract_type"
        return 1
    fi
    
    # Update the specific contract address in LocalContracts
    awk -v addr="$contract_addr" -v contract="$contract_type" '
    BEGIN { in_local = 0 }
    /^library LocalContracts {/ { in_local = 1; print; next }
    /^}/ && in_local { in_local = 0; print; next }
    in_local && ($0 ~ "address public constant " contract) { 
        print "    address public constant " contract " = " addr ";"
        next
    }
    { print }
    ' script/Contracts.sol > script/Contracts.sol.tmp && mv script/Contracts.sol.tmp script/Contracts.sol
    
    print_success "$contract_type address updated: $contract_addr"
}

# Function to update contract address after each deployment
update_contract_after_deployment() {
    local contract_name=$1
    local log_file="/tmp/${contract_name}_deploy.log"
    
    case $contract_name in
        "DeployToken")
            local addr=$(grep "SapienToken deployed at:" "$log_file" | awk '{print $NF}' | tr -d '\n\r')
            update_single_contract_address "SAPIEN_TOKEN" "$addr"
            ;;
        "DeployTimelock")
            local addr=$(grep "Timelock deployed at:" "$log_file" | awk '{print $NF}' | tr -d '\n\r')
            update_single_contract_address "TIMELOCK" "$addr"
            ;;
        "DeployQA")
            local addr=$(grep "SapienQA deployed at:" "$log_file" | awk '{print $NF}' | tr -d '\n\r')
            update_single_contract_address "SAPIEN_QA" "$addr"
            ;;
        "DeployRewards")
            local addr=$(grep "Rewards Proxy deployed at:" "$log_file" | awk '{print $NF}' | tr -d '\n\r')
            update_single_contract_address "SAPIEN_REWARDS" "$addr"
            ;;
        "DeployVault")
            local addr=$(grep "Vault Proxy deployed at:" "$log_file" | awk '{print $NF}' | tr -d '\n\r')
            update_single_contract_address "SAPIEN_VAULT" "$addr"
            ;;
    esac
}

# Function to update TypeScript contracts.ts file with local addresses
update_typescript_contracts() {
    print_status "Updating deployments/contracts.ts with local addresses..."
    
    # Extract all addresses from deployment logs
    local token_addr=$(grep "SapienToken deployed at:" /tmp/DeployToken_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local timelock_addr=$(grep "Timelock deployed at:" /tmp/DeployTimelock_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local qa_addr=$(grep "SapienQA deployed at:" /tmp/DeployQA_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    
    # Extract rewards addresses (both implementation and proxy)
    local rewards_impl_addr=$(grep "SapienRewards deployed at:" /tmp/DeployRewards_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local rewards_proxy_addr=$(grep "Rewards Proxy deployed at:" /tmp/DeployRewards_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    
    # Extract vault addresses (both implementation and proxy)
    local vault_impl_addr=$(grep "SapienVault implementation deployed at:" /tmp/DeployVault_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local vault_proxy_addr=$(grep "Vault Proxy deployed at:" /tmp/DeployVault_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    
    # Backup the current contracts.ts
    cp deployments/contracts.ts deployments/contracts.ts.backup
    
    # Update the LOCAL addresses in contracts.ts using sed
    sed -i.tmp "s/const LOCAL_SAPAIEN_TOKEN = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPAIEN_TOKEN = \"$token_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_TIMELOCK = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_TIMELOCK = \"$timelock_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_SAPIEN_QA = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPIEN_QA = \"$qa_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_SAPIEN_REWARDS = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPIEN_REWARDS = \"$rewards_impl_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_SAPIEN_REWARDS_PROXY = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPIEN_REWARDS_PROXY = \"$rewards_proxy_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_SAPIEN_VAULT = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPIEN_VAULT = \"$vault_impl_addr\";/g" deployments/contracts.ts
    sed -i.tmp "s/const LOCAL_SAPIEN_VAULT_PROXY = \"0x[0-9a-fA-F]\{40\}\";/const LOCAL_SAPIEN_VAULT_PROXY = \"$vault_proxy_addr\";/g" deployments/contracts.ts
    
    # Clean up temporary files
    rm -f deployments/contracts.ts.tmp
    
    print_success "deployments/contracts.ts updated with local addresses"
    print_status "Backup saved as deployments/contracts.ts.backup"
    
    # Show what was updated
    print_status "Updated LOCAL addresses in contracts.ts:"
    echo "  LOCAL_SAPAIEN_TOKEN: $token_addr"
    echo "  LOCAL_TIMELOCK: $timelock_addr"
    echo "  LOCAL_SAPIEN_QA: $qa_addr"
    echo "  LOCAL_SAPIEN_REWARDS: $rewards_impl_addr"
    echo "  LOCAL_SAPIEN_REWARDS_PROXY: $rewards_proxy_addr"
    echo "  LOCAL_SAPIEN_VAULT: $vault_impl_addr"
    echo "  LOCAL_SAPIEN_VAULT_PROXY: $vault_proxy_addr"
}

# Function to update ONLY local contract addresses in Contracts.sol (final summary)
update_local_contract_addresses() {
    print_status "Final LocalContracts addresses summary:"
    
    # Extract specific addresses
    local token_addr=$(grep "SapienToken deployed at:" /tmp/DeployToken_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local timelock_addr=$(grep "Timelock deployed at:" /tmp/DeployTimelock_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local qa_addr=$(grep "SapienQA deployed at:" /tmp/DeployQA_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local rewards_addr=$(grep "Rewards Proxy deployed at:" /tmp/DeployRewards_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    local vault_addr=$(grep "Vault Proxy deployed at:" /tmp/DeployVault_deploy.log 2>/dev/null | awk '{print $NF}' | tr -d '\n\r')
    
    # Show what was updated
    echo "  SAPIEN_TOKEN: $token_addr"
    echo "  TIMELOCK: $timelock_addr"
    echo "  SAPIEN_QA: $qa_addr"
    echo "  SAPIEN_REWARDS: $rewards_addr"
    echo "  SAPIEN_VAULT: $vault_addr"
}

# Function to create deployment summary
create_deployment_summary() {
    print_status "Creating deployment summary..."
    
    printf "\n"
    printf "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║                    DEPLOYMENT COMPLETED                       ║${NC}\n"
    printf "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${BLUE}Network Details:${NC}\n"
    printf "  RPC URL:      %s\n" "$RPC_URL"
    printf "  Chain ID:     %s\n" "$CHAIN_ID"
    printf "  Private Key:  %s...\n" "${PRIVATE_KEY:0:10}"
    printf "\n"
    printf "${BLUE}Deployment Results:${NC}\n"

    # Show deployed addresses
    for contract in "${CONTRACTS[@]}"; do
        local log_file="/tmp/${contract}_deploy.log"
        if [ -f "$log_file" ]; then
            printf "  ${YELLOW}%s:${NC}\n" "$contract"
            grep -E "(deployed at|Proxy deployed at):" "$log_file" | sed 's/^/    /'
        fi
    done

    printf "\n"
    printf "${BLUE}Next Steps:${NC}\n"
    printf "  1. Contracts are ready for testing\n"
    printf "  2. Use the updated addresses in your frontend/tests\n"
    printf "  3. Deployment logs saved in /tmp/*_deploy.log\n"
    printf "  4. Contract addresses saved in deployments/local-addresses.txt\n"
    printf "  5. LocalContracts updated in Contracts.sol (backup saved)\n"
    printf "  6. LOCAL addresses updated in contracts.ts (backup saved)\n"
    printf "\n"
    printf "\n"
    printf "${BLUE}To run tests:${NC}\n"
    printf "  make unit    # Run unit tests\n"
    printf "  make invar   # Run invariant tests\n"
    printf "\n"
}

# Function to cleanup on exit
cleanup() {
    if [ ! -z "$ANVIL_PID" ] && kill -0 $ANVIL_PID 2>/dev/null; then
        print_status "Cleaning up..."
        # Don't kill Anvil automatically - let user decide
        print_warning "Anvil is still running (PID: $ANVIL_PID)"
        print_status "Run 'kill $ANVIL_PID' to stop it"
    fi
}

# Trap cleanup on script exit
trap cleanup EXIT

# Main deployment function
main() {
    print_status "Starting Sapien Contracts Local Deployment"
    echo "=============================================="
    
    # Check prerequisites
    if ! command_exists forge; then
        print_error "forge not found. Please install Foundry: https://getfoundry.sh/"
        exit 1
    fi
    
    if ! command_exists anvil; then
        print_error "anvil not found. Please install Foundry: https://getfoundry.sh/"
        exit 1
    fi
    
    # Start or check Anvil
    if ! start_anvil; then
        exit 1
    fi
    
    # Create deployments directory if it doesn't exist
    mkdir -p deployments
    
    # Backup original Contracts.sol before any deployments
    cp script/Contracts.sol script/Contracts.sol.backup
    print_status "Backup saved as script/Contracts.sol.backup"
    
    # Deploy contracts in order, updating addresses after each deployment
    local deployment_success=true
    for contract in "${CONTRACTS[@]}"; do
        if ! deploy_contract "$contract"; then
            deployment_success=false
            break
        fi
        
        # Update the contract address immediately after successful deployment
        update_contract_after_deployment "$contract"
        
        sleep 1  # Small delay between deployments
    done
    
    if [ "$deployment_success" = true ]; then
        extract_addresses
        update_local_contract_addresses
        update_typescript_contracts
        create_deployment_summary
        print_success "All contracts deployed successfully!"
    else
        print_error "Deployment failed. Check the logs for details."
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            ANVIL_PORT="$2"
            RPC_URL="http://$ANVIL_HOST:$ANVIL_PORT"
            shift 2
            ;;
        --host)
            ANVIL_HOST="$2"
            RPC_URL="http://$ANVIL_HOST:$ANVIL_PORT"
            shift 2
            ;;
        --private-key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        --color)
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            YELLOW='\033[1;33m'
            BLUE='\033[0;34m'
            NC='\033[0m'
            shift
            ;;
        --no-color)
            RED=''
            GREEN=''
            YELLOW=''
            BLUE=''
            NC=''
            shift
            ;;
        --help|-h)
            cat << EOF
Deploy Sapien Contracts to Local Anvil Node

Usage: $0 [OPTIONS]

Options:
  --port PORT            Anvil port (default: 8545)
  --host HOST            Anvil host (default: 127.0.0.1)
  --private-key KEY      Private key for deployment (default: Anvil account 0)
  --color                Force enable colored output
  --no-color             Force disable colored output
  --help, -h             Show this help message

Environment Variables:
  ANVIL_PORT            Same as --port
  ANVIL_HOST            Same as --host
  PRIVATE_KEY           Same as --private-key
  FORCE_COLOR           Set to 1 or true to enable colors

Examples:
  $0                                    # Deploy with defaults (no colors)
  $0 --color                           # Deploy with colored output
  $0 --port 8546                       # Deploy on custom port
  $0 --private-key 0x123...            # Deploy with custom private key
  FORCE_COLOR=1 $0                     # Deploy with colors via env var

EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_status "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main deployment
main 