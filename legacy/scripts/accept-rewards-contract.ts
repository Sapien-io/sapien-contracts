import { ethers } from "hardhat";
import { loadConfig, Contract } from "./utils/loadConfig";
export default async function main() {
  const config = loadConfig(Contract.All);

  // Get the contract instance
  const sapTestToken = await ethers.getContractAt(
    "SapTestToken",
    config.token.proxyAddress // Replace with your deployed contract address
  );

  try {
    // Get the pending rewards contract address for verification
    const pendingAddress = await sapTestToken.pendingRewardsContract();
    console.log(`Accepting pending rewards contract: ${pendingAddress}`);
    
    const tx = await sapTestToken.acceptRewardsContract();
    await tx.wait();
    
    console.log(`Successfully accepted new rewards contract. Transaction hash: ${tx.hash}`);

    // Verify the change
    const newRewardsContract = await sapTestToken.rewardsContract();
    console.log(`New active rewards contract: ${newRewardsContract}`);

  } catch (error) {
    console.error("Error accepting rewards contract:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 
