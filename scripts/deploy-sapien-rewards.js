// Script to deploy the Sapien Rewards contract
const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
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
      bonusThreshold: ethers.utils.parseEther("1000"),
      gnosisSafeAddress: "0xf21d8BCCf352aEa0D426F9B0Ee4cA94062cfc51f",
      // Bonus for staking more than 1000 tokens
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
      config.gnosisSafeAddress,
    ], // Pass the authorized signer address (using deployer for now)
    {
      initializer: 'initialize',
      kind: 'uups',
    }
  );
  
  await rewardsContract.waitForDeployment();
  const rewardsAddress = await rewardsContract.getAddress();
  console.log(`Sapien Rewards contract deployed to: ${rewardsAddress}`);

  // Save deployment information
  const deployData = {
    network: hre.network.name,
    rewardsAddress: rewardsAddress,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address,
    gnosisSafeAddress: config.gnosisSafeAddress,
    authorizedSigner: deployer.address // Save the authorized signer address
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
