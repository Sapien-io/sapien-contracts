const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Starting Sapien Rewards contract upgrade process...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load current deployment data
  const deploymentPath = path.join(__dirname, "../deployments", networkName, "SapienRewards.json");
  const currentDeployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  console.log(`Current Rewards contract address: ${currentDeployment.rewardsAddress}`);
  console.log(`Upgrading with account: ${deployer.address}`);
  
  // Get token balance before upgrade
  const SapToken = await ethers.getContractFactory("SapToken");
  const token = await SapToken.attach(currentDeployment.sapTokenAddress);
  const balanceBefore = await token.balanceOf(currentDeployment.rewardsAddress);
  console.log(`Current rewards contract balance: ${ethers.utils.formatEther(balanceBefore)} tokens`);
  
  // Deploy new implementation
  const SapienRewardsV2 = await ethers.getContractFactory("SapienRewards");
  console.log("Upgrading Rewards contract...");
  
  const upgradedRewards = await upgrades.upgradeProxy(
    currentDeployment.rewardsAddress,
    SapienRewardsV2
  );
  
  await upgradedRewards.deployed();
  console.log("Upgrade complete!");
  
  // Verify token balance after upgrade
  const balanceAfter = await token.balanceOf(upgradedRewards.address);
  console.log(`Post-upgrade rewards contract balance: ${ethers.utils.formatEther(balanceAfter)} tokens`);
  
  if (!balanceAfter.eq(balanceBefore)) {
    console.warn("Warning: Token balance changed during upgrade!");
  }
  
  // Verify the contract is still a distributor
  const SapienStaking = await ethers.getContractFactory("SapienStaking");
  const staking = await SapienStaking.attach(currentDeployment.stakingContractAddress);
  
  const isDistributor = await staking.isDistributor(upgradedRewards.address);
  if (!isDistributor) {
    console.log("Re-adding rewards contract as distributor...");
    const tx = await staking.addDistributor(upgradedRewards.address);
    await tx.wait();
    console.log("Distributor status restored");
  }
  
  // Update deployment information
  const upgradeData = {
    ...currentDeployment,
    upgradedAt: new Date().toISOString(),
    upgradeTransaction: upgradedRewards.deployTransaction.hash,
    upgradedBy: deployer.address
  };
  
  fs.writeFileSync(deploymentPath, JSON.stringify(upgradeData, null, 2));
  console.log("Upgrade information saved to:", deploymentPath);
  
  return upgradedRewards;
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