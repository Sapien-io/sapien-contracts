#!/bin/bash

# Test Claim Rewards Script for Localhost
# This script runs the TestClaimRewards forge script against localhost (Anvil)

set -e

echo "🧪 Testing Claim Rewards on Localhost"
echo "======================================"

# Check if Anvil is running
if ! curl -s http://localhost:8545 >/dev/null 2>&1; then
    echo "❌ Error: Anvil is not running on localhost:8545"
    echo "Please start Anvil first with: anvil"
    exit 1
fi

echo "✅ Anvil is running"

echo "🔧 Environment:"
echo "  RPC_URL: http://localhost:8545"
echo "  Using default Anvil test accounts"
echo ""

# Run the forge script
echo "🚀 Running claim rewards test..."
echo ""

forge script test/unit/rewards/TestClaimRewards.s.sol:TestClaimRewards \
    --rpc-url http://localhost:8545 \
    --broadcast \
    -vvv

echo ""
echo "✅ Test completed!"
echo ""
echo "💡 Tips:"
echo "  - Modify REWARD_AMOUNT and ORDER_ID in TestClaimRewards.s.sol to test different scenarios"
echo "  - Use different TEST_USER address to test with different accounts"
echo "  - Make sure the rewards safe has enough tokens and has approved the contract" 