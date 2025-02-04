import { Network } from "alchemy-sdk";
import hre from "hardhat";
import dotenv from "dotenv";
dotenv.config();

const { ALCHEMY_API_URL, TOKEN_ADDRESS, PRIVATE_KEY } = process.env;

const contract = require("../artifacts/contracts/SapTestToken.sol/SapTestToken.json");

async function sapTestRelease() {
  // Create provider for transaction signing
  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);

  // Sign the transaction using the private key
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);

  // Connect to the contract with the signer
  const releaseCon = new hre.ethers.Contract(
    TOKEN_ADDRESS!,
    contract.abi,
    signer
  );

  // Specify the allocation type (e.g., "rewards" as per your mapping)
  const allocationType = "rewards"; // Ensure this matches the exact string used in the contract

  console.log(
    "Attempting to release tokens for allocation type: rewards",
    releaseCon.releaseTokens
  );
  try {
    console.log(
      `Attempting to release tokens for allocation type: ${allocationType}`
    );
    console.log(`Contract address: ${TOKEN_ADDRESS}`);
    console.log(`Signer address: ${signer.address}`);

    // Call the releaseTokens function
    try {
      const tx = await releaseCon.releaseTokens(allocationType);
      console.log("Transaction sent. Waiting for confirmation...");

      // Wait for the transaction to be confirmed
      const receipt = await tx.wait();
      console.log("Transaction successful:", receipt);
      console.log(
        `Tokens released successfully. Transaction hash: ${receipt.transactionHash}`
      );
    } catch (error) {
      console.error("Error releasing tokens:", error);
    }
  } catch (error) {
    console.error("Error releasing tokens:", error);
  }
}

sapTestRelease()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
