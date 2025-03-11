// Script to deploy the SAP Test Token (ERC20)
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");
const { upgrades } = require("hardhat");

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
      initialSupply: ethers.parseEther("1000000"),
      gnosisSafeAddress: "0xf21d8BCCf352aEa0D426F9B0Ee4cA94062cfc51f",
      totalSupply: ethers.parseEther("1000000")
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
  console.log(`Account balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);

  // Deploy the token contract
  console.log("Deploying SAP Test Token...");
  const SapTestToken = await ethers.getContractFactory("SapTestToken");
  const sapTestToken = await upgrades.deployProxy(SapTestToken, 
    [
      config.gnosisSafeAddress,  // _gnosisSafeAddress
      config.totalSupply         // _totalSupply
    ],
    { kind: 'uups' }
  );
  await sapTestToken.waitForDeployment();
  
  console.log(`SAP Test Token deployed to: ${sapTestToken.address}`);

  // Save deployment information
  const deployData = {
    network: hre.network.name,
    tokenAddress: sapTestToken.address,
    deploymentTime: new Date().toISOString(),
    deployer: deployer.address,
    tokenName: config.tokenName,
    tokenSymbol: config.tokenSymbol,
    initialSupply: config.initialSupply.toString(),
    gnosisSafeAddress: config.gnosisSafeAddress,
    totalSupply: config.totalSupply.toString()
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
  return sapTestToken;
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