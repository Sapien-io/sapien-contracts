import hre, { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  console.log("Pausing Sapien Staking...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const stakingData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienStaking.json"),
      "utf8"
    )
  );

  // Attach to contract
  const SapienStaking = await ethers.getContractFactory("SapienStaking");
  const staking = SapienStaking.attach(stakingData.proxyAddress);
  
  // Check if already paused
  const isPaused = await staking.paused();
  if (isPaused) {
    console.log("Sapien Staking is already paused");
    return staking;
  }

  // Pause the contract
  console.log("Executing pause transaction...");
  const pauseTx = await staking.pause();
  await pauseTx.wait();
  
  console.log("Sapien Staking successfully paused");
  return staking;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error while pausing:", error);
      process.exit(1);
    });
}
