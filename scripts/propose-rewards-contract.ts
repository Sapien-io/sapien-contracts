import hre, { ethers } from "hardhat";

export default async function main() {
  const network = hre.network.name;

  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", network, "SapienToken.json"),
      "utf8"
    )
  )
  // Get the contract instance
  const sapTestToken = await ethers.getContractAt(
    "SapTestToken",
    tokenData.proxyAddress // Replace with your deployed contract address
  );

  // Get the new rewards contract address from environment variable
  const newRewardsContract = process.env.NEW_REWARDS_CONTRACT;
  if (!newRewardsContract) {
    throw new Error("NEW_REWARDS_CONTRACT environment variable must be set");
  }

  try {
    console.log(`Proposing new rewards contract: ${newRewardsContract}`);
    
    const tx = await sapTestToken.proposeRewardsContract(newRewardsContract);
    await tx.wait();
    
    console.log(`Successfully proposed new rewards contract. Transaction hash: ${tx.hash}`);
    console.log("Note: You must now call acceptRewardsContract to complete the change.");

  } catch (error) {
    console.error("Error proposing rewards contract:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 
