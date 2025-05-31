#!/bin/bash

# SapienToken Deployment Script
# Usage: ./script/token.sh [network]
# Networks: localhost, base-sepolia, base

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create deployment file
create_deployment_file() {
    local network=$1
    local contract_address=$2
    local source=${3:-"deployment-script"}
    
    cat > "deployments/$network.json" << EOF
{
  "network": "$network",
  "sapienToken": "$contract_address",
  "source": "$source",
  "timestamp": $(date +%s)
}
EOF
}

# Function to display deployment details
show_deployment_details() {
    local network=$1
    echo "--- Deployment Details ---"
    cat "deployments/$network.json"
    echo "-------------------------"
}

# Check if network argument is provided
if [ $# -eq 0 ]; then
    print_error "Please specify a network: localhost, base-sepolia, or base"
    echo "Usage: ./script/token.sh [network]"
    exit 1
fi

NETWORK=$1

# Validate network
case $NETWORK in
    localhost)
        print_status "Deploying to localhost (Anvil)..."
        RPC_URL="http://127.0.0.1:8545"
        SCRIPT_CONTRACT="DeployLocalhostSapienToken"
        ;;
    base-sepolia)
        print_status "Deploying to Base Sepolia testnet..."
        RPC_URL="https://sepolia.base.org"
        SCRIPT_CONTRACT="DeploySapienToken"
        ;;
    base)
        print_status "Deploying to Base mainnet..."
        RPC_URL="https://mainnet.base.org"
        SCRIPT_CONTRACT="DeploySapienToken"
        print_warning "You are deploying to MAINNET! Make sure you have the correct admin address set."
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled."
            exit 0
        fi
        ;;
    *)
        print_error "Invalid network: $NETWORK"
        echo "Supported networks: localhost, base-sepolia, base"
        exit 1
        ;;
esac

# Check if .env file exists (only for non-localhost deployments)
if [ "$NETWORK" != "localhost" ] && [ ! -f .env ]; then
    print_warning ".env file not found. Please create one based on script/deploy-config.example"
    exit 1
fi

# Source environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

# Validate required environment variables for non-localhost deployments
if [ "$NETWORK" != "localhost" ]; then
    if [ -z "$ACCOUNT" ]; then
        print_error "ACCOUNT not set in .env file"
        exit 1
    fi
fi

# Create deployments directory if it doesn't exist
mkdir -p deployments

print_status "Network: $NETWORK"
print_status "RPC URL: $RPC_URL"
print_status "Script: $SCRIPT_CONTRACT"

# Run the deployment
if [ "$NETWORK" = "localhost" ]; then
    # For localhost, we can use the default Anvil private key
    print_status "Using default Anvil private key for localhost deployment"
    forge script script/DeploySapienToken.s.sol:$SCRIPT_CONTRACT \
        --rpc-url $RPC_URL \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --broadcast \
        -vvvv
else
    # For testnets and mainnet, use the private key from .env
    if [ -n "$BASESCAN_API_KEY" ] && [ "$BASESCAN_API_KEY" != "your_basescan_api_key" ]; then
        print_status "Contract verification enabled"
        forge script script/DeploySapienToken.s.sol:$SCRIPT_CONTRACT \
            --rpc-url $RPC_URL \
            --account $ACCOUNT \
            --broadcast \
            --verify \
            --etherscan-api-key $BASESCAN_API_KEY \
            -vvvv
    else
        print_warning "Contract verification disabled (BASESCAN_API_KEY not set)"
        forge script script/DeploySapienToken.s.sol:$SCRIPT_CONTRACT \
            --rpc-url $RPC_URL \
            --account $ACCOUNT \
            --broadcast \
            -vvvv
    fi
fi

if [ $? -eq 0 ]; then
    print_status "Deployment completed successfully!"
    
    # Wait a moment for file system to sync
    sleep 1
    
    # Check if deployment file was created
    if [ -f "deployments/$NETWORK.json" ]; then
        print_status "Deployment info saved to deployments/$NETWORK.json"
        show_deployment_details "$NETWORK"
    else
        print_warning "Deployment file not found at deployments/$NETWORK.json"
        print_status "Checking broadcast logs for contract address..."
        
        # Try to find the contract address in broadcast logs
        BROADCAST_DIR="broadcast/DeploySapienToken.s.sol"
        if [ "$NETWORK" = "localhost" ]; then
            BROADCAST_DIR="broadcast/DeploySapienToken.s.sol/31337"
        elif [ "$NETWORK" = "base-sepolia" ]; then
            BROADCAST_DIR="broadcast/DeploySapienToken.s.sol/84532"
        elif [ "$NETWORK" = "base" ]; then
            BROADCAST_DIR="broadcast/DeploySapienToken.s.sol/8453"
        fi
        
        # Check if broadcast directory exists
        if [ ! -d "$BROADCAST_DIR" ]; then
            print_error "No broadcast directory found at: $BROADCAST_DIR"
            exit 1
        fi
        
        # Check if broadcast log exists
        if [ ! -f "$BROADCAST_DIR/run-latest.json" ]; then
            print_error "No broadcast log found at: $BROADCAST_DIR/run-latest.json"
            exit 1
        fi
        
        print_status "Found broadcast log: $BROADCAST_DIR/run-latest.json"
        
        # Extract contract address using jq
        if ! command -v jq &> /dev/null; then
            print_warning "jq not found. Please install jq or check broadcast logs manually at: $BROADCAST_DIR/run-latest.json"
            exit 1
        fi
        
        CONTRACT_ADDRESS=$(jq -r '.transactions[] | select(.transactionType == "CREATE") | .contractAddress' "$BROADCAST_DIR/run-latest.json" | head -n 1)
        
        if [ "$CONTRACT_ADDRESS" = "null" ] || [ -z "$CONTRACT_ADDRESS" ]; then
            print_error "Could not extract contract address from broadcast log"
            exit 1
        fi
        
        print_status "SapienToken deployed at: $CONTRACT_ADDRESS"
        
        # Create deployment file
        create_deployment_file "$NETWORK" "$CONTRACT_ADDRESS" "broadcast-log"
        print_status "Created deployment file manually: deployments/$NETWORK.json"
        show_deployment_details "$NETWORK"
    fi
else
    print_error "Deployment failed!"
    exit 1
fi