import hre, { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  console.log("Starting reward token setup process...");
  
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
      path.join(__dirname, "../deployments", networkName, "SapienToken.json"),
      "utf8"
    )
  );

  // Attach to rewards contract
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.proxyAddress);

  // Set reward token
  console.log(`Setting reward token to: ${tokenData.proxyAddress}`);
  const setTx = await rewards.setRewardToken(tokenData.proxyAddress);
  await setTx.wait();
  
  console.log("Reward token successfully set!");
  
  return rewards;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error setting reward token:", error);
      process.exit(1);
    });
}
