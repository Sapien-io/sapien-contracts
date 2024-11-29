import { ethers } from "hardhat";
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

    // Set up a provider and signer
    const provider = new ethers.JsonRpcProvider(ALCHEMY_API_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY!, provider);

    // Get the contract factory
    const SapienStaking = await ethers.getContractFactory(
      "SapienStaking",
      wallet
    );

    console.log("Deploying SapienStaking contract...");

    // Deploy the contract
    const sapienStaking = await SapienStaking.deploy(
      TOKEN_ADDRESS,
      OWNER1_ADDRESS
    );
    await sapienStaking.deployed();

    console.log("SapienStaking deployed to:", sapienStaking.address);
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
