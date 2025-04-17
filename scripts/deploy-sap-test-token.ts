// Script to deploy the SAP Test Token (ERC20)
import hre, {ethers, upgrades} from 'hardhat'
import * as fs from 'fs'
import * as path from 'path'
import {type DeploymentMetadata, type DeploymentConfig} from './utils/types'

import { Contract, loadConfig } from './utils/loadConfig'

export default async function main() {
  console.log("Starting SAP Test Token deployment...");
  
  // Get configuration
  const config = loadConfig(Contract.SapienToken);
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();

  console.log(`Deploying with account: ${deployer.address}`);
  console.log(`Account balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);

  // Deploy the token contract
  console.log("Deploying SAP Test Token...");
  const SapTestToken = await ethers.getContractFactory("SapTestToken");
  console.log('totalSupply:', config.totalSupply);
  const sapTestToken = await upgrades.deployProxy(SapTestToken, 
    [
      config.safe,
      config.totalSupply
    ],
    { kind: 'uups' }
  );
  await sapTestToken.waitForDeployment();
  
  const deployedAddress = await sapTestToken.getAddress();
  console.log("\n==============================================");
  console.log(`SAP Test Token deployed to: ${deployedAddress}`);
  console.log("==============================================\n");

  // Save deployment information
  const deployData: DeploymentMetadata = {
    network: hre.network.name,
    proxyAddress: deployedAddress as `0x${string}`,
    implementationAddress: (await upgrades.erc1967.getImplementationAddress(deployedAddress)) as `0x${string}`,
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
    path.join(deployDir, "SapienToken.json"),
    JSON.stringify(deployData, null, 2)
  );

  console.log("Deployment information saved to:", path.join(deployDir, "SapienToken.json"));
  console.log("SAP Test Token deployment complete!");

  // Return the deployed contract for testing or for deploy-all.js
  return sapTestToken;
}

// Execute the script
//
if (require.main === module) {
  main()
  .then((result) => {
    console.log("Result:", result);
    process.exit(0);
  })
  .catch((error) => {
    console.error("Error during deployment:", error);
    process.exit(1);
  });
}
