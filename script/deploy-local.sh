#!/bin/bash

# Exit on error
set -e

# Configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
BROADCAST_FILE="broadcast/DeployToAnvil.s.sol/31337/run-latest.json"
DEPLOYMENTS_JSON="deployments/local.json"
APP_CONFIG_DIR="app/src/config"
APP_ABI_DIR="app/src/abis"
VERBOSITY="${VERBOSITY:--v}"

echo "=== Sapien Protocol - Local Anvil Deployment ==="

# 1. Start Anvil in the background if it's not already running
if ! lsof -i:8545 > /dev/null 2>&1; then
    echo "Starting Anvil..."
    anvil > anvil.log 2>&1 &
    ANVIL_PID=$!
    echo "Anvil started (PID: $ANVIL_PID). Logs: anvil.log"
    sleep 3
else
    echo "Anvil already running on port 8545."
fi

# 2. Run the Forge deployment script (deploys full protocol)
echo ""
echo "Deploying full protocol to Anvil..."
forge script script/DeployToAnvil.s.sol:DeployToAnvil \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --unlocked \
    $VERBOSITY

# 3. Extract addresses from the broadcast file
echo ""
echo "Extracting contract addresses..."

if [ ! -f "$BROADCAST_FILE" ]; then
    echo "Error: Broadcast file $BROADCAST_FILE not found. Deployment may have failed."
    exit 1
fi

# Helper to get address of proxy by its order in the script
get_proxy_address() {
    local index=$1
    jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "ERC1967Proxy") | .contractAddress' "$BROADCAST_FILE" | sed -n "${index}p"
}

# Helper to get address of a contract by its name and occurrence
get_contract_address() {
    local name=$1
    local occurrence=$2
    jq -r ".transactions[] | select(.transactionType == \"CREATE\" and .contractName == \"$name\") | .contractAddress" "$BROADCAST_FILE" | sed -n "${occurrence}p"
}

# Normalize address (checksum if viem available, else use as-is)
normalize_address() {
    local addr=$1
    if [ -z "$addr" ] || [ "$addr" = "null" ]; then
        echo ""
        return
    fi
    if [ -d "app" ] && [ -f "app/package.json" ]; then
        (cd app && node -e "const { getAddress } = require('viem'); console.log(getAddress('$addr'))" 2>/dev/null) || echo "$addr"
    else
        echo "$addr"
    fi
}

# Mapping based on DeployToAnvil.s.sol order
SAPIEN_TOKEN=$(normalize_address "$(get_contract_address "MockERC20" 1)")
USDC=$(normalize_address "$(get_contract_address "MockERC20" 2)")
SAPIEN_VAULT=$(normalize_address "$(get_proxy_address 1)")
REWARDS=$(normalize_address "$(get_proxy_address 2)")
SAPIEN_TRUST=$(normalize_address "$(get_proxy_address 3)")
VALIDATION_ORACLE=$(normalize_address "$(get_proxy_address 4)")
SAPIEN_CORE=$(normalize_address "$(get_proxy_address 5)")

# 4. Write deployments to deployments/local.json (always)
mkdir -p deployments
cat <<EOF > "$DEPLOYMENTS_JSON"
{
  "chainId": 31337,
  "SAPIEN_CORE": "$SAPIEN_CORE",
  "VALIDATION_ORACLE": "$VALIDATION_ORACLE",
  "SAPIEN_TRUST": "$SAPIEN_TRUST",
  "SAPIEN_VAULT": "$SAPIEN_VAULT",
  "REWARDS": "$REWARDS",
  "SAPIEN_TOKEN": "$SAPIEN_TOKEN",
  "USDC": "$USDC"
}
EOF
echo "Wrote $DEPLOYMENTS_JSON"

# 5. Optionally sync to app (only when app/ exists)
if [ -d "app" ]; then
    echo ""
    echo "Syncing to app..."
    mkdir -p "$APP_CONFIG_DIR" "$APP_ABI_DIR"
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
    echo "  Updated $APP_CONFIG_DIR/deployments.json"

    copy_abi() {
        local source_name=$1
        local target_file=$2
        local var_name=$3
        local json_path="out/$source_name.sol/$source_name.json"
        if [ -f "$json_path" ]; then
            echo "export const $var_name = $(jq -c '.abi' "$json_path") as const;" > "$APP_ABI_DIR/$target_file.ts"
            echo "  Updated $target_file.ts"
        fi
    }
    copy_abi "SapienCore" "sapienCore" "sapienCoreABI"
    copy_abi "ValidationOracle" "validationOracle" "validationOracleABI"
    copy_abi "SapienTrust" "sapienTrust" "sapienTrustABI"
    copy_abi "SapienVault" "sapienVault" "sapienVaultABI"
    copy_abi "Rewards" "rewards" "rewardsABI"
    copy_abi "MockERC20" "erc20" "erc20ABI"
fi

echo ""
echo "=== Local deployment complete ==="
echo "Addresses: $DEPLOYMENTS_JSON"
echo ""
echo "Verify deployment: forge test --match-contract LocalDeploymentVerification --fork-url $RPC_URL"
