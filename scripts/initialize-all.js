const hre = require("hardhat");
const { ethers } = require("hardhat");
const { initialize: initializeToken } = require("./initialize-sap-token");
const { initialize: initializeStaking } = require("./initialize-sapien-staking");
const { initialize: initializeRewards } = require("./initialize-sapien-rewards");

async function main() {
  console.log("Starting complete initialization process...");

  // Initialize contracts in order
  console.log("\n1. Initializing SAP Token...");
  const token = await initializeToken();
  
  console.log("\n2. Initializing Staking Contract...");
  const staking = await initializeStaking();
  
  console.log("\n3. Initializing Rewards Contract...");
  const rewards = await initializeRewards();

  console.log("\nAll contracts initialized successfully!");
  
  // Return all initialized contracts
  return {
    token,
    staking,
    rewards
  };
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during initialization:", error);
      process.exit(1);
    });
}

module.exports = { initialize: main }; 