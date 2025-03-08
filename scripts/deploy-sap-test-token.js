// Script to deploy the SAP Test Token (ERC20)
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
      tokenName: "Sapien Token",
      tokenSymbol: "SAP",
      initialSupply: ethers.utils.parseEther("1000000") // 1 million tokens with 18 decimals
    };
  }
};

async function main() {
  console.log("Starting SAP Test Token deployment...");
  
  // Get configuration
  const config = loadConfig();
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);
  console.log(`Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);

  // Deploy the token contract
  const SapToken = await ethers.getContractFactory("SapToken");
  console.log("Deploying SAP Test Token...");
  const sapToken = await SapToken.deploy(
    config.tokenName,
    config.tokenSymbol,
    config.initialSupply
  );
  
  await sapToken.deployed();
  console.log(`SAP Test Token deployed to: ${sapToken.address}`);

  // Save deployment information
  const deployData = {
    network: hre.network.name,
    tokenAddress: sapToken.address,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address,
    tokenName: config.tokenName,
    tokenSymbol: config.tokenSymbol,
    initialSupply: config.initialSupply.toString()
  };

  // Ensure deployment directory exists
  const deployDir = path.join(__dirname, "../deployments", hre.network.name);
  if (!fs.existsSync(deployDir)) {
    fs.mkdirSync(deployDir, { recursive: true });
  }
  
  // Save deployment info to file
  fs.writeFileSync(
    path.join(deployDir, "SapToken.json"),
    JSON.stringify(deployData, null, 2)
  );

  console.log("Deployment information saved to:", path.join(deployDir, "SapToken.json"));
  console.log("SAP Test Token deployment complete!");

  // Return the deployed contract for testing or for deploy-all.js
  return sapToken;
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