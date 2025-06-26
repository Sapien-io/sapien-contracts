#!/bin/bash

# Tenderly Integration Test Setup Verification Script
# This script helps verify that your environment is correctly configured
# for running Tenderly integration tests.

echo "🔍 Tenderly Integration Test Setup Verification"
echo "=============================================="
echo

# Check if required environment variables are set
echo "📋 Environment Variables:"
echo "------------------------"

if [ -z "$TENDERLY_VIRTUAL_TESTNET_RPC_URL" ]; then
    echo "❌ TENDERLY_VIRTUAL_TESTNET_RPC_URL is not set"
    echo "   Please set it with: export TENDERLY_VIRTUAL_TESTNET_RPC_URL=\"https://virtual.mainnet.rpc.tenderly.co/...\""
    exit 1
else
    echo "✅ TENDERLY_VIRTUAL_TESTNET_RPC_URL is set"
    echo "   URL: $TENDERLY_VIRTUAL_TESTNET_RPC_URL"
fi

if [ -z "$TENDERLY_TEST_PRIVATE_KEY" ]; then
    echo "❌ TENDERLY_TEST_PRIVATE_KEY is not set"
    echo "   Please set it with: export TENDERLY_TEST_PRIVATE_KEY=\"0x...\""
    exit 1
else
    echo "✅ TENDERLY_TEST_PRIVATE_KEY is set"
    echo "   Length: ${#TENDERLY_TEST_PRIVATE_KEY} characters"
fi

echo

# Check if the RPC URL is accessible
echo "🌐 Network Connectivity:"
echo "------------------------"

# Simple HTTP check for the RPC endpoint
if curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$TENDERLY_VIRTUAL_TESTNET_RPC_URL" | grep -q "200"; then
    echo "✅ RPC endpoint is accessible"
else
    echo "❌ RPC endpoint is not accessible or not responding"
    echo "   Please check your TENDERLY_VIRTUAL_TESTNET_RPC_URL"
    exit 1
fi

echo

# Check private key format and derive address
echo "🔑 Private Key Verification:"
echo "---------------------------"

# Validate private key format (should be 66 characters: 0x + 64 hex chars)
if [[ $TENDERLY_TEST_PRIVATE_KEY =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "✅ Private key format is valid"
    
    # Derive address from private key using cast (if available)
    if command -v cast &> /dev/null; then
        DERIVED_ADDRESS=$(cast wallet address --private-key "$TENDERLY_TEST_PRIVATE_KEY")
        EXPECTED_ADDRESS="0x0C6F86b338417B3b7FCB9B344DECC51d072919c9"
        
        echo "   Derived address: $DERIVED_ADDRESS"
        echo "   Expected address: $EXPECTED_ADDRESS"
        
        if [ "$DERIVED_ADDRESS" = "$EXPECTED_ADDRESS" ]; then
            echo "✅ Private key corresponds to the correct address"
        else
            echo "❌ Private key does NOT correspond to the expected address"
            echo "   You need a private key that generates address $EXPECTED_ADDRESS"
            exit 1
        fi
    else
        echo "⚠️  Cast not found - cannot verify address derivation"
        echo "   Please ensure your private key corresponds to address:"
        echo "   0x0C6F86b338417B3b7FCB9B344DECC51d072919c9"
    fi
else
    echo "❌ Private key format is invalid"
    echo "   Expected format: 0x followed by 64 hexadecimal characters"
    exit 1
fi

echo

# Check if foundry is available and configured
echo "🔨 Foundry Configuration:"
echo "------------------------"

if command -v forge &> /dev/null; then
    echo "✅ Forge is available"
else
    echo "❌ Forge not found"
    echo "   Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

echo

# Run a simple test to verify everything works
echo "🧪 Running Basic Test:"
echo "---------------------"

echo "Running a simple compilation check..."
if FOUNDRY_PROFILE=tenderly forge build --quiet; then
    echo "✅ Compilation successful"
else
    echo "❌ Compilation failed"
    echo "   Please check your project setup"
    exit 1
fi

echo

echo "🎉 Setup Verification Complete!"
echo "==============================="
echo
echo "Your environment appears to be correctly configured for Tenderly integration tests."
echo "You can now run the tests with:"
echo
echo "  FOUNDRY_PROFILE=tenderly forge test --match-path \"test/integration/\" -v"
echo
echo "For debugging specific tests, use:"
echo "  FOUNDRY_PROFILE=tenderly forge test --match-test \"test_name\" -vvv" 