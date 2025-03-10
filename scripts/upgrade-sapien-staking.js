const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Starting Sapien Staking contract upgrade process...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load current deployment data
  const deploymentPath = path.join(__dirname, "../deployments", networkName, "SapienStaking.json");
  const currentDeployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  console.log(`Current Staking contract address: ${currentDeployment.stakingAddress}`);
  console.log(`Upgrading with account: ${deployer.address}`);
  
  // Deploy new implementation
  const SapienStakingV2 = await ethers.getContractFactory("SapienStaking");
  console.log("Upgrading Staking contract...");
  
  const upgradedStaking = await upgrades.upgradeProxy(
    currentDeployment.stakingAddress,
    SapienStakingV2
  );
  
  await upgradedStaking.deployed();
  console.log("Upgrade complete!");
  
  // Verify existing distributors are still set correctly
  console.log("Verifying distributor settings...");
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );
  
  // Check if rewards contract is still a distributor
  const isDistributor = await upgradedStaking.isDistributor(rewardsData.rewardsAddress);
  if (!isDistributor) {
    console.log("Re-adding rewards contract as distributor...");
    const tx = await upgradedStaking.addDistributor(rewardsData.rewardsAddress);
    await tx.wait();
    console.log("Rewards contract restored as distributor");
  }
  
  // Update deployment information
  const upgradeData = {
    ...currentDeployment,
    upgradedAt: new Date().toISOString(),
    upgradeTransaction: upgradedStaking.deployTransaction.hash,
    upgradedBy: deployer.address
  };
  
  fs.writeFileSync(deploymentPath, JSON.stringify(upgradeData, null, 2));
  console.log("Upgrade information saved to:", deploymentPath);
  
  return upgradedStaking;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during upgrade:", error);
      process.exit(1);
    });
}

module.exports = { upgrade: main }; 