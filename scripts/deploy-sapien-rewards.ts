// Script to deploy the Sapien Rewards contract
import hre, { ethers, upgrades } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { loadConfig, Contract } from "./utils/loadConfig";
import { type DeploymentMetadata } from "./utils/types";

async function main() {
  console.log("Starting Sapien Rewards contract deployment...");
  
  // Get configuration
  const config = loadConfig(Contract.SapienRewards);
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);
  
  // Get deployer balance (fixed)
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} ETH`);

  // Deploy the rewards contract
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  console.log("Deploying Sapien Rewards contract...");
  
  // Deploy the implementation contract
  const rewardsContract = await upgrades.deployProxy(
    SapienRewards,
    [
      deployer.address,
      config.safe,
    ], // Pass the authorized signer address (using deployer for now)
    {
      initializer: 'initialize',
      kind: 'uups',
    }
  );
  
  await rewardsContract.waitForDeployment();
  const proxyAddress = await rewardsContract.getAddress();
  console.log(`Sapien Rewards contract deployed to: ${proxyAddress}`);

  // Save deployment information
  const deployData: DeploymentMetadata = {
    network: hre.network.name,
    proxyAddress: proxyAddress as `0x${string}`,
    implementationAddress: await upgrades.erc1967.getImplementationAddress(proxyAddress)as `0x${string}`,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address as `0x${string}`,
    safe: config.safe,
  };

  // Ensure deployment directory exists
  const deployDir = path.join(__dirname, "../deployments", hre.network.name);
  if (!fs.existsSync(deployDir)) {
    fs.mkdirSync(deployDir, { recursive: true });
  }
  
  // Save deployment info to file
  fs.writeFileSync(
    path.join(deployDir, "SapienRewards.json"),
    JSON.stringify(deployData, null, 2)
  );

  console.log("Deployment information saved to:", path.join(deployDir, "SapienRewards.json"));
  console.log("Sapien Rewards contract deployment complete!");

  return rewardsContract;
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error during deployment:", error);
    process.exit(1);
  });

// Export the main function for use in deploy-all.js
module.exports = { deploy: main }; 
