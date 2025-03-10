const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const amount = process.env.WITHDRAW_AMOUNT || "0"; // Must be specified or 0
  console.log(`Starting rewards withdrawal process for ${amount} tokens...`);
  
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const rewardsData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienRewards.json"),
      "utf8"
    )
  );

  // Attach to contract
  const SapienRewards = await ethers.getContractFactory("SapienRewards");
  const rewards = await SapienRewards.attach(rewardsData.rewardsAddress);

  // Check contract balance
  const contractBalance = await rewards.getContractTokenBalance();
  const withdrawAmount = ethers.utils.parseEther(amount);
  
  if (contractBalance.lt(withdrawAmount)) {
    throw new Error(`Insufficient contract balance. Have: ${ethers.utils.formatEther(contractBalance)}, Want to withdraw: ${amount}`);
  }

  // Withdraw tokens
  console.log("Withdrawing tokens...");
  const withdrawTx = await rewards.withdrawTokens(withdrawAmount);
  await withdrawTx.wait();
  
  // Verify new balance
  const newBalance = await rewards.getContractTokenBalance();
  console.log(`Withdrawal successful! New rewards contract balance: ${ethers.utils.formatEther(newBalance)} tokens`);
  
  return rewards;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during withdrawal:", error);
      process.exit(1);
    });
}

module.exports = { withdraw: main }; 