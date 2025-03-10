const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Starting SAP Token upgrade process...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load current deployment data
  const deploymentPath = path.join(__dirname, "../deployments", networkName, "SapToken.json");
  const currentDeployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  console.log(`Current SAP Token address: ${currentDeployment.tokenAddress}`);
  console.log(`Upgrading with account: ${deployer.address}`);
  
  // Deploy new implementation
  const SapTokenV2 = await ethers.getContractFactory("SapToken");
  console.log("Upgrading SAP Token...");
  
  const upgradedToken = await upgrades.upgradeProxy(
    currentDeployment.tokenAddress,
    SapTokenV2
  );
  
  await upgradedToken.deployed();
  console.log("Upgrade complete!");
  
  // Update deployment information
  const upgradeData = {
    ...currentDeployment,
    upgradedAt: new Date().toISOString(),
    upgradeTransaction: upgradedToken.deployTransaction.hash,
    upgradedBy: deployer.address
  };
  
  fs.writeFileSync(deploymentPath, JSON.stringify(upgradeData, null, 2));
  console.log("Upgrade information saved to:", deploymentPath);
  
  return upgradedToken;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during upgrade:", error);
      process.exit(1);
    });
}

module.exports = { upgrade: main }; 