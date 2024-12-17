import hre from "hardhat";
import dotenv from "dotenv";
dotenv.config();

const { ALCHEMY_API_URL, TOKEN_ADDRESS, REWARD_CONTRACT, PRIVATE_KEY } =
  process.env;

async function setRewardToken() {
  // Create provider
  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);

  // Initialize wallet with private key and provider
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);

  // Import contract ABI
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");

  // Connect to the rewards contract
  const rewardContract = new hre.ethers.Contract(
    REWARD_CONTRACT!,
    contract.abi,
    signer
  );

  try {
    console.log(`Setting new reward token address: ${TOKEN_ADDRESS}`);

    const tx = await rewardContract.setRewardToken(TOKEN_ADDRESS);
    console.log("Transaction sent. Waiting for confirmation...");

    // Wait for the transaction to be confirmed
    const receipt = await tx.wait();
    console.log("Transaction confirmed:", receipt);
    console.log(
      `Reward token set successfully. Transaction hash: ${receipt.transactionHash}`
    );
  } catch (error) {
    console.error("Error setting reward token:", error);
  }
}

setRewardToken()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
