const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Pausing SAP Token...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienToken.json"),
      "utf8"
    )
  );

  // Attach to contract
  const SapToken = await ethers.getContractFactory("SapToken");
  const token = await SapToken.attach(tokenData.tokenAddress);
  
  // Check if already paused
  const isPaused = await token.paused();
  if (isPaused) {
    console.log("SAP Token is already paused");
    return token;
  }

  // Pause the contract
  console.log("Executing pause transaction...");
  const pauseTx = await token.pause();
  await pauseTx.wait();
  
  console.log("SAP Token successfully paused");
  return token;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error while pausing:", error);
      process.exit(1);
    });
}

module.exports = { pause: main }; 
