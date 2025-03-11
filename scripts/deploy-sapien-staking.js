// Script to deploy the Sapien Staking contract
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

// Load configuration
const loadConfig = () => {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(__dirname, "../config/deploy-config.json"), "utf8")
    );
  } catch (error) {
    console.error("Error loading config file. Using default values.", error.message);
    return {
      minStakeAmount: ethers.utils.parseEther("100"), // 100 tokens minimum stake
      lockPeriod: 7 * 24 * 60 * 60,  // 7 days in seconds
      earlyWithdrawalPenalty: 1000,  // 10% as basis points (10000 = 100%)
      sapTokenAddress: "" // This should be provided or fetched from deployment files
    };
  }
};

// Load token address from deployment files if not provided in config
const getSapTokenAddress = (config, networkName) => {
  if (config.sapTokenAddress) return config.sapTokenAddress;
  
  try {
    const deployData = JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "../deployments", networkName, "SapToken.json"),
        "utf8"
      )
    );
    return deployData.tokenAddress;
  } catch (error) {
    console.error("Error fetching SAP Token address. Please deploy SAP Token first or provide address in config.");
    throw error;
  }
};

async function main() {
  console.log("Starting Sapien Staking contract deployment...");
  
  // Get configuration
  const config = loadConfig();
  
  const [deployer] = await ethers.getSigners();
  if (!deployer) {
    throw new Error("Deployer account not found. Please check your Hardhat configuration.");
  }
  
  console.log(`Deploying with account: ${deployer.address}`);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} ETH`);

  // Get SAP Token address
  const sapTokenAddress = getSapTokenAddress(config, hre.network.name);
  console.log(`Using SAP Token at address: ${sapTokenAddress}`);

  try {
    // Deploy the implementation and proxy using OpenZeppelin's upgrades plugin
    const SapienStaking = await ethers.getContractFactory("SapienStaking");
    console.log("Deploying proxy and implementation...");
    
    const stakingContract = await upgrades.deployProxy(
      SapienStaking,
      [sapTokenAddress, deployer.address],
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
    const deployData = {
      network: hre.network.name,
      implementationAddress: implementationAddress,
      proxyAddress: proxyAddress,
      deploymentTime: new Date().toISOString(),
      deployer: deployer.address,
      sapTokenAddress: sapTokenAddress
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