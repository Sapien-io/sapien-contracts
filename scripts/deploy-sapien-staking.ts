// Script to deploy the Sapien Staking contract
import hre, { ethers, upgrades } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { loadConfig, Contract } from "./utils/loadConfig";
import { type DeploymentMetadata } from "./utils/types";
async function main() {
  console.log("Starting Sapien Staking contract deployment...");
  
  // Get configuration
  const config = loadConfig(Contract.SapienStaking);
  
  const [deployer] = await ethers.getSigners();
  if (!deployer) {
    throw new Error("Deployer account not found. Please check your Hardhat configuration.");
  }
  
  console.log(`Deploying with account: ${deployer.address}`);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} ETH`);

  // Get SAP Token address
  const sapTokenAddress = config.token.proxyAddress;
  console.log(`Using SAP Token at address: ${sapTokenAddress}`);

  try {
    // Deploy the implementation and proxy using OpenZeppelin's upgrades plugin
    const SapienStaking = await ethers.getContractFactory("SapienStaking");
    console.log("Deploying proxy and implementation...");
    
    const stakingContract = await upgrades.deployProxy(
      SapienStaking,
      [
        sapTokenAddress,
        deployer.address,
        config.safe
      ],
      {
        initializer: 'initialize',
        kind: 'uups'
      }
    );

    await stakingContract.waitForDeployment();
    const proxyAddress = await stakingContract.getAddress();
    console.log(`Proxy deployed to: ${proxyAddress}`);

    // Get the implementation address
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log(`Implementation deployed to: ${implementationAddress}`);

    // Save deployment information
    const deployData: DeploymentMetadata = {
      network: hre.network.name,
      implementationAddress: implementationAddress as `0x${string}`,
      proxyAddress: proxyAddress as `0x${string}`,
      deploymentTime: new Date().toISOString(),
      deployer: deployer.address as `0x${string}`,
      safe: config.safe
    };

    // Ensure deployment directory exists
    const deployDir = path.join(__dirname, "../deployments", hre.network.name);
    if (!fs.existsSync(deployDir)) {
      fs.mkdirSync(deployDir, { recursive: true });
    }
    
    // Save deployment info to file
    fs.writeFileSync(
      path.join(deployDir, "SapienStaking.json"),
      JSON.stringify(deployData, null, 2)
    );

    console.log("Deployment information saved to:", path.join(deployDir, "SapienStaking.json"));
    console.log("Sapien Staking contract deployment complete!");

    // Verify the initialization
    try {
      const owner = await stakingContract.owner();
      console.log("Contract owner:", owner);
    } catch (error) {
      console.error("Error verifying contract initialization:", error);
      throw error;
    }

    return stakingContract;

  } catch (error) {
    console.error("Deployment failed with error:", error);
    if (error.error) {
      console.error("Additional error details:", error.error);
    }
    throw error;
  }
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

console.log('Private key is present:', !!process.env.PRIVATE_KEY); 
