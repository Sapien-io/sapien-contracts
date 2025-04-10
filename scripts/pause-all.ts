import hre from "hardhat";

import pauseToken from "./pause-sap-token";
import pauseStaking from "./pause-sapien-staking";
import pauseRewards from "./pause-sapien-rewards";
export default async function main() {
  console.log("Starting emergency pause of all contracts...");

  try {
    // Pause in reverse order of dependency to minimize risks
    console.log("\n1. Pausing Rewards Contract...");
    await pauseRewards();
    
    console.log("\n2. Pausing Staking Contract...");
    await pauseStaking();
    
    console.log("\n3. Pausing SAP Token...");
    await pauseToken();

    console.log("\nAll contracts successfully paused!");
  } catch (error) {
    console.error("\nError during pause process:", error);
    console.log("Some contracts may still be active. Please check each contract's status individually.");
    throw error;
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error in pause-all script:", error);
      process.exit(1);
    });
}
