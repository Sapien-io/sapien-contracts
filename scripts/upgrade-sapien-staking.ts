
import hre, { ethers, upgrades } from "hardhat";
import * as fs from "fs";
import * as path from "path";
export default async function main() {
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
    currentDeployment.proxyAddress,
    SapienStakingV2,
    {
      useDeployedImplementation: true,
      implementationAddress: currentDeployment.authorizedUpgradedImplementation,
      //kind: "uups",
    }
  );
  
  await upgradedStaking.waitForDeployment();
  console.log("Upgrade complete!");
  
  
  // Verify existing distributors are still set correctly
  /*
  console.log("Verifying distributor settings...");
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );
  */

  const upgradeData = {
    ...currentDeployment,
    upgradedAt: new Date().toISOString(),
    upgradeTransaction: upgradedStaking.deployTransaction.hash,
    upgradedBy: deployer.address
  };
  
  fs.writeFileSync(deploymentPath, JSON.stringify(upgradeData, null, 2));
  
  // Check if rewards contract is still a distributor
  /*
  const isDistributor = await upgradedStaking.isDistributor(rewardsData.proxyAddress);
  if (!isDistributor) {
    console.log("Re-adding rewards contract as distributor...");
    const tx = await upgradedStaking.addDistributor(rewardsData.rewardsAddress);
    await tx.wait();
    console.log("Rewards contract restored as distributor");
  }
  
  // Update deployment information
   */
  console.log("Upgrade information saved to:", deploymentPath);
  
  return upgradedStaking;
}

if (require.main === module) {
  main()
    .then((result) =>{ 
      console.log("Result:", result);
      process.exit(0)
    })
    .catch((error) => {
      console.error("Error during upgrade:", error);
      process.exit(1);
    });
}
