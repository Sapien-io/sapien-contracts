#!/bin/bash

# Exit on error
set -e

# Configuration
RPC_URL="http://localhost:8545"
BROADCAST_FILE="broadcast/DeployToAnvil.s.sol/31337/run-latest.json"
APP_CONFIG_DIR="app/src/config"
APP_ABI_DIR="app/src/abis"

echo "Starting local deployment process..."

# 1. Start Anvil in the background if it's not already running
if ! lsof -i:8545 > /dev/null; then
    echo "Anvil is not running. Starting Anvil..."
    anvil > anvil.log 2>&1 &
    ANVIL_PID=$!
    echo "Anvil started (PID: $ANVIL_PID). Logs at anvil.log"
    sleep 3 # Wait for Anvil to initialize
else
    echo "Anvil is already running on port 8545."
fi

# 2. Run the Forge deployment script
echo "Deploying contracts to Anvil..."
forge script script/DeployToAnvil.s.sol:DeployToAnvil \
    --rpc-url $RPC_URL \
    --broadcast \
    --unlocked \
    -vvvv

# 3. Extract addresses from the broadcast file using jq
echo "Extracting contract addresses..."

if [ ! -f "$BROADCAST_FILE" ]; then
    echo "Error: Broadcast file $BROADCAST_FILE not found. Deployment might have failed."
    exit 1
fi

# Helper to get address of proxy by its order in the script
get_proxy_address() {
    local index=$1
    jq -r ".transactions[] | select(.transactionType == \"CREATE\" and .contractName == \"ERC1967Proxy\") | .contractAddress" "$BROADCAST_FILE" | sed -n "${index}p"
}

# Helper to get address of a contract by its name and occurrence
get_contract_address() {
    local name=$1
    local occurrence=$2
    jq -r ".transactions[] | select(.transactionType == \"CREATE\" and .contractName == \"$name\") | .contractAddress" "$BROADCAST_FILE" | sed -n "${occurrence}p"
}

# Helper to checksum an address using viem in the app folder
checksum_address() {
    local addr=$1
    if [ -z "$addr" ] || [ "$addr" == "null" ]; then
        echo ""
        return
    fi
    # Use node from the app directory where viem is installed
    (cd app && node -e "const { getAddress } = require(\"viem\"); console.log(getAddress(\"$addr\"))" 2>/dev/null) || echo "$addr"
}

# Mapping based on DeployToAnvil.s.sol order
SAPIEN_TOKEN=$(checksum_address $(get_contract_address "MockERC20" 1))
USDC=$(checksum_address $(get_contract_address "MockERC20" 2))
SAPIEN_VAULT=$(checksum_address $(get_proxy_address 1))
REWARDS=$(checksum_address $(get_proxy_address 2))
SAPIEN_TRUST=$(checksum_address $(get_proxy_address 3))
VALIDATION_ORACLE=$(checksum_address $(get_proxy_address 4))
SAPIEN_CORE=$(checksum_address $(get_proxy_address 5))

# 4. Generate deployments.json
mkdir -p "$APP_CONFIG_DIR"
cat <<EOF > "$APP_CONFIG_DIR/deployments.json"
{
  "SAPIEN_CORE": "$SAPIEN_CORE",
  "VALIDATION_ORACLE": "$VALIDATION_ORACLE",
  "SAPIEN_TRUST": "$SAPIEN_TRUST",
  "SAPIEN_VAULT": "$SAPIEN_VAULT",
  "REWARDS": "$REWARDS",
  "SAPIEN_TOKEN": "$SAPIEN_TOKEN",
  "USDC": "$USDC"
}
EOF

echo "Generated $APP_CONFIG_DIR/deployments.json"

# 5. Sync ABIs to the frontend
echo "Syncing ABIs to $APP_ABI_DIR..."
mkdir -p "$APP_ABI_DIR"

copy_abi() {
    local source_name=$1
    local target_file=$2
    local var_name=$3
    local json_path="out/$source_name.sol/$source_name.json"
    
    if [ -f "$json_path" ]; then
        echo "export const $var_name = $(jq -c '.abi' "$json_path") as const;" > "$APP_ABI_DIR/$target_file.ts"
        echo "  Updated $target_file.ts"
    else
        echo "  Warning: $json_path not found"
    fi
}

copy_abi "SapienCore" "sapienCore" "sapienCoreABI"
copy_abi "ValidationOracle" "validationOracle" "validationOracleABI"
copy_abi "SapienTrust" "sapienTrust" "sapienTrustABI"
copy_abi "SapienVault" "sapienVault" "sapienVaultABI"
copy_abi "Rewards" "rewards" "rewardsABI"
copy_abi "MockERC20" "erc20" "erc20ABI"

echo "=== Local Deployment & Sync Complete ==="
