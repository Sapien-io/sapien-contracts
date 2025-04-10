import hre, { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  console.log("Pausing Sapien Rewards...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );

  // Attach to contract
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.proxyAddress);
  
  // Check if already paused
  const isPaused = await rewards.paused();
  if (isPaused) {
    console.log("Sapien Rewards is already paused");
    return rewards;
  }

  // Pause the contract
  console.log("Executing pause transaction...");
  const pauseTx = await rewards.pause();
  await pauseTx.wait();
  
  console.log("Sapien Rewards successfully paused");
  return rewards;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error while pausing:", error);
      process.exit(1);
    });
}
