const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Initializing SAP Token...");
  
  const networkName = hre.network.name;
  console.log(`Network: ${networkName}`);
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapToken.json"),
      "utf8"
    )
  );

  const SapToken = await ethers.getContractFactory("SapTestToken");
  const token = await SapToken.attach(tokenData.tokenAddress);
  
  console.log("SAP Token initialization complete!");
  return token;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during initialization:", error);
      process.exit(1);
    });
}

module.exports = { initialize: main }; 
