// Script to deploy the Sapien Staking contract
const hre = require("hardhat");
const { ethers } = require("hardhat");
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
  
  // Get deployer account with better error handling
  const signers = await ethers.getSigners();
  if (!signers || signers.length === 0) {
    throw new Error("No signers found. Please check your Hardhat network configuration and make sure you have a wallet configured.");
  }
  
  const [deployer] = signers;
  if (!deployer) {
    throw new Error("Deployer account not found. Please check your Hardhat configuration.");
  }
  
  console.log(`Deploying with account: ${deployer.address}`);
  const balance = await deployer.getBalance();
  console.log(`Account balance: ${ethers.utils.formatEther(balance)} ETH`);

  // Get SAP Token address
  const sapTokenAddress = getSapTokenAddress(config, hre.network.name);
  console.log(`Using SAP Token at address: ${sapTokenAddress}`);

  // Deploy the staking contract
  const SapienStaking = await ethers.getContractFactory("SapienStaking");
  console.log("Deploying Sapien Staking contract...");
  const stakingContract = await SapienStaking.deploy(
    sapTokenAddress,
    config.minStakeAmount,
    config.lockPeriod,
    config.earlyWithdrawalPenalty
  );
  
  await stakingContract.deployed();
  console.log(`Sapien Staking contract deployed to: ${stakingContract.address}`);

  // Save deployment information
  const deployData = {
    network: hre.network.name,
    stakingAddress: stakingContract.address,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address,
    sapTokenAddress: sapTokenAddress,
    minStakeAmount: config.minStakeAmount.toString(),
    lockPeriod: config.lockPeriod.toString(),
    earlyWithdrawalPenalty: config.earlyWithdrawalPenalty.toString()
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

  // Return the deployed contract for testing or for deploy-all.js
  return stakingContract;
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