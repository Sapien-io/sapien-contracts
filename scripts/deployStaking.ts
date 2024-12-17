import { ethers } from "hardhat";
import hre from "hardhat";
import dotenv from "dotenv";
dotenv.config();

const { TOKEN_ADDRESS, OWNER1_ADDRESS, PRIVATE_KEY, ALCHEMY_API_URL } =
  process.env;

async function deploySapienStaking() {
  try {
    // Ensure environment variables are set
    if (!TOKEN_ADDRESS || !OWNER1_ADDRESS || !PRIVATE_KEY || !ALCHEMY_API_URL) {
      throw new Error("Missing environment variables!");
    }

    // Get the contract factory for SapienRewards
    const SapienStaking = await hre.ethers.getContractFactory("SapienStaking");

    // Deploy the proxy contract using UUPS upgradeability pattern
    const contract = await hre.upgrades.deployProxy(
      SapienStaking,
      [TOKEN_ADDRESS, OWNER1_ADDRESS],
      { initializer: "initialize", kind: "uups" }
    );

    // Wait for the deployment to be mined
    const address = await contract.getAddress();
    console.log("Contract deployed to", address);

    console.log("SapienStaking contract initialized successfully!");
  } catch (error) {
    console.error("Error deploying contract:", error);
    process.exit(1);
  }
}

deploySapienStaking()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment script failed:", error);
    process.exit(1);
  });
