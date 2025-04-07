import hre, { ethers, upgrades } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  console.log("Starting SAP Token upgrade process...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load current deployment data
  const deploymentPath = path.join(__dirname, "../deployments", networkName, "SapienToken.json");
  const currentDeployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  console.log(`Current SAP Token address: ${currentDeployment.proxyAddress}`);
  console.log(`Upgrading with account: ${deployer.address}`);
  
  // Deploy new implementation
  const SapTokenV2 = await ethers.getContractFactory("SapTestToken");
  console.log("Upgrading SAP Test Token...");
  
  const upgradedToken = await upgrades.upgradeProxy(
    currentDeployment.proxyAddress,
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
