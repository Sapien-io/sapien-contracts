const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const amount = process.env.DEPOSIT_AMOUNT || "1000000"; // Default 1M tokens
  console.log(`Starting rewards deposit process for ${amount} tokens...`);
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );
  
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienToken.json"),
      "utf8"
    )
  );

  // Attach to contracts
  const SapToken = await ethers.getContractFactory("SapToken");
  const token = await SapToken.attach(tokenData.tokenAddress);
  
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.rewardsAddress);

  // Check token balance
  const balance = await token.balanceOf(deployer.address);
  const depositAmount = ethers.utils.parseEther(amount);
  
  if (balance.lt(depositAmount)) {
    throw new Error(`Insufficient token balance. Have: ${ethers.utils.formatEther(balance)}, Need: ${amount}`);
  }

  // Approve tokens
  console.log("Approving tokens for deposit...");
  const approveTx = await token.approve(rewards.address, depositAmount);
  await approveTx.wait();
  
  // Deposit tokens
  console.log("Depositing tokens...");
  const depositTx = await rewards.depositTokens(depositAmount);
  await depositTx.wait();
  
  // Verify new balance
  const newBalance = await rewards.getContractTokenBalance();
  console.log(`Deposit successful! New rewards contract balance: ${ethers.utils.formatEther(newBalance)} tokens`);
  
  return rewards;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during deposit:", error);
      process.exit(1);
    });
}

module.exports = { deposit: main }; 
