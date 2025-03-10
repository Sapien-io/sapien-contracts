const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Initializing Sapien Staking...");
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const stakingData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienStaking.json"),
      "utf8"
    )
  );
  
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapToken.json"),
      "utf8"
    )
  );

  // Attach to contracts
  const SapToken = await ethers.getContractFactory("SapToken");
  const token = await SapToken.attach(tokenData.tokenAddress);
  
  const SapienStaking = await ethers.getContractFactory("SapienStaking");
  const staking = await SapienStaking.attach(stakingData.stakingAddress);

  // Approve staking contract to spend tokens
  console.log("Approving staking contract to spend tokens...");
  const maxApproval = ethers.constants.MaxUint256;
  const approveTx = await token.approve(staking.address, maxApproval);
  await approveTx.wait();
  console.log("Staking contract approved to spend tokens");

  console.log("Sapien Staking initialization complete!");
  return staking;
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