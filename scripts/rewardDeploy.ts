import hre from "hardhat";
import { ethers } from "ethers";

// Load environment variables
const { TOKEN_ADDRESS, OWNER1_ADDRESS, PRIVATE_KEY, ALCHEMY_API_URL } =
  process.env;

async function deploySapienRewards() {
  // Validate required environment variables
  if (!TOKEN_ADDRESS || !OWNER1_ADDRESS) {
    throw new Error(
      "TOKEN_ADDRESS and AUTHORIZED_SIGNER must be defined in the environment variables"
    );
  }

  console.log("Deploying SapienRewards contract...");

  // Get the contract factory for SapienRewards
  const SapienRewards = await hre.ethers.getContractFactory("SapienRewards");

  // Deploy the proxy contract using UUPS upgradeability pattern
  const contract = await hre.upgrades.deployProxy(
    SapienRewards,
    [OWNER1_ADDRESS],
    { initializer: "initialize", kind: "uups" }
  );

  // Wait for the deployment to be mined
  const address = await contract.getAddress();
  console.log("Contract deployed to", address);
}

// Execute the script
deploySapienRewards()
  .then(() => process.exit(0)) // Exit successfully
  .catch((error) => {
    console.error("Error deploying SapienRewards contract:", error);
    process.exit(1); // Exit with an error
  });
