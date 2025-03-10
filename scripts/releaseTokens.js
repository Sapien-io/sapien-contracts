const { ethers } = require("hardhat");

async function main() {
  // Get the contract instance
  const sapTestToken = await ethers.getContractAt(
    "SapTestToken",
    "YOUR_CONTRACT_ADDRESS_HERE" // Replace with your deployed contract address
  );

  // AllocationType enum values:
  // 0: INVESTORS
  // 1: TEAM
  // 2: REWARDS
  // 3: AIRDROP
  // 4: COMMUNITY_TREASURY
  // 5: STAKING_INCENTIVES
  // 6: LIQUIDITY_INCENTIVES

  try {
    // You need to call this from either the Gnosis Safe or the rewards contract
    const allocationType = 0; // Example: releasing INVESTORS tokens
    
    console.log(`Attempting to release tokens for allocation type: ${allocationType}`);
    
    const tx = await sapTestToken.releaseTokens(allocationType);
    await tx.wait();
    
    console.log(`Successfully released tokens. Transaction hash: ${tx.hash}`);

    // Get the updated vesting schedule
    const schedule = await sapTestToken.vestingSchedules(allocationType);
    console.log("Updated vesting schedule:");
    console.log(`- Released amount: ${ethers.formatUnits(schedule.released, 18)} tokens`);
    console.log(`- Total amount: ${ethers.formatUnits(schedule.amount, 18)} tokens`);

  } catch (error) {
    console.error("Error releasing tokens:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 