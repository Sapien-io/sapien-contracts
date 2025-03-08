// Script to deploy the Sapien Rewards contract
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Load configuration
const loadConfig = () => {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(__dirname, "../config/deploy-config.json"), "utf8")
    );
  } catch (error) {
    console.error("Error loading config file. Using default values.", error.message);
    return {
      rewardRate: 100, // 1% as basis points (10000 = 100%)
      rewardInterval: 30 * 24 * 60 * 60, // 30 days in seconds
      bonusThreshold: ethers.utils.parseEther("1000"), // Bonus for staking more than 1000 tokens
      bonusRate: 50, // Additional 0.5% bonus as basis points
      sapTokenAddress: "", // This should be provided or fetched from deployment files
      stakingContractAddress: "" // This should be provided or fetched from deployment files
    };
  }
};

// Load addresses from deployment files if not provided in config
const getDeployedAddresses = (config, networkName) => {
  let sapTokenAddress = config.sapTokenAddress;
  let stakingContractAddress = config.stakingContractAddress;
  
  if (!sapTokenAddress) {
    try {
      const tokenData = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "../deployments", networkName, "SapToken.json"),
          "utf8"
        )
      );
      sapTokenAddress = tokenData.tokenAddress;
    } catch (error) {
      console.error("Error fetching SAP Token address. Please deploy SAP Token first or provide address in config.");
      throw error;
    }
  }
  
  if (!stakingContractAddress) {
    try {
      const stakingData = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "../deployments", networkName, "SapienStaking.json"),
          "utf8"
        )
      );
      stakingContractAddress = stakingData.stakingAddress;
    } catch (error) {
      console.error("Error fetching Staking contract address. Please deploy Staking contract first or provide address in config.");
      throw error;
    }
  }
  
  return {
    sapTokenAddress,
    stakingContractAddress
  };
};

async function main() {
  console.log("Starting Sapien Rewards contract deployment...");
  
  // Get configuration
  const config = loadConfig();
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);
  console.log(`Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);

  // Get deployed addresses
  const addresses = getDeployedAddresses(config, hre.network.name);
  console.log(`Using SAP Token at address: ${addresses.sapTokenAddress}`);
  console.log(`Using Staking contract at address: ${addresses.stakingContractAddress}`);

  // Deploy the rewards contract
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  console.log("Deploying Sapien Rewards contract...");
  const rewardsContract = await SapienRewards.deploy(
    addresses.sapTokenAddress,
    addresses.stakingContractAddress,
    config.rewardRate,
    config.rewardInterval,
    config.bonusThreshold,
    config.bonusRate
  );
  
  await rewardsContract.deployed();
  console.log(`Sapien Rewards contract deployed to: ${rewardsContract.address}`);

  // Save deployment information
  const deployData = {
    network: hre.network.name,
    rewardsAddress: rewardsContract.address,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address,
    sapTokenAddress: addresses.sapTokenAddress,
    stakingContractAddress: addresses.stakingContractAddress,
    rewardRate: config.rewardRate.toString(),
    rewardInterval: config.rewardInterval.toString(),
    bonusThreshold: config.bonusThreshold.toString(),
    bonusRate: config.bonusRate.toString()
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
  
  // Set up the rewards contract as a distributor in the staking contract
  console.log("Setting up rewards contract as distributor in staking contract...");
  try {
    const SapienStaking = await ethers.getContractFactory("SapienStaking");
    const stakingContract = await SapienStaking.attach(addresses.stakingContractAddress);
    
    const tx = await stakingContract.addDistributor(rewardsContract.address);
    await tx.wait();
    console.log("Rewards contract successfully set as distributor");
  } catch (error) {
    console.error("Error setting rewards contract as distributor:", error.message);
    console.log("You may need to manually set the rewards contract as distributor.");
  }

  console.log("Sapien Rewards contract deployment complete!");

  // Return the deployed contract for testing or for deploy-all.js
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