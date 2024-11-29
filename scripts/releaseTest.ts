// Import Hardhat
import hre from "hardhat";

// Load environment variables for easy configuration
const { TOKEN_ADDRESS, REWARD_CONTRACT, PRIVATE_KEY } = process.env;

async function main() {
  // Define the allocation type you want to release tokens for
  const allocationType = "rewards";
  console.log(
    "Attempting to release tokens for allocation type: rewards",
    REWARD_CONTRACT
  );
  // Connect to the SapienRewards contract
  const SapienRewards = await hre.ethers.getContractFactory("SapienRewards");
  const sapienRewards = await SapienRewards.attach(REWARD_CONTRACT!);

  // Set up wallet using the private key (if needed) for executing the transaction
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, hre.ethers.provider);
  const contractWithSigner = sapienRewards.connect(signer);

  // Call releaseRewardTokens function to release tokens to the Rewards contract
  try {
    const tx = await contractWithSigner.releaseRewardTokens(allocationType);
    await tx.wait(); // Wait for transaction confirmation

    console.log(
      `Tokens successfully released for allocation type: ${allocationType}`
    );
  } catch (error) {
    console.error("Error releasing tokens:", error);
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error in script execution:", error);
    process.exit(1);
  });
