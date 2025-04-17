import hre, { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  const amount = process.env.DEPOSIT_AMOUNT;
  if (!amount) {
    throw new Error("Must specify amount to deposit");
  }
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
  const SapToken = await ethers.getContractFactory("SapTestToken");
  const token = await SapToken.attach(tokenData.proxyAddress);
  
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.proxyAddress);

  // Check token balance
  const balance = await token.balanceOf(deployer.address);
  const depositAmount = ethers.utils.parseEther(amount);
  
  if (balance.lt(depositAmount)) {
    throw new Error(`Insufficient token balance. Have: ${ethers.formatEther(balance)}, Need: ${amount}`);
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
  console.log(`Deposit successful! New rewards contract balance: ${ethers.formatEther(newBalance)} tokens`);
  
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
