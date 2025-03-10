const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Initializing Sapien Rewards...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );
  
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapToken.json"),
      "utf8"
    )
  );

  // Attach to contracts
  const SapToken = await ethers.getContractFactory("SapToken");
  const token = await SapToken.attach(tokenData.tokenAddress);
  
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.rewardsAddress);

  // Fund rewards contract with tokens
  console.log("Funding rewards contract with initial tokens...");
  const fundAmount = ethers.utils.parseEther("100000"); // Fund with 100,000 tokens
  const transferTx = await token.transfer(rewards.address, fundAmount);
  await transferTx.wait();
  console.log(`Funded rewards contract with ${ethers.utils.formatEther(fundAmount)} tokens`);

  console.log("Sapien Rewards initialization complete!");
  return rewards;
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