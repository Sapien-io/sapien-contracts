const { ethers } = require("hardhat");

async function main() {
  // Get the contract instance
  const sapTestToken = await ethers.getContractAt(
    "SapTestToken",
    "YOUR_CONTRACT_ADDRESS_HERE" // Replace with your deployed contract address
  );

  // Get parameters from environment variables
  const params = {
    allocationType: process.env.ALLOCATION_TYPE,
    cliff: process.env.CLIFF_DAYS,
    start: process.env.START_TIMESTAMP,
    duration: process.env.DURATION_DAYS,
    amount: process.env.AMOUNT,
    safe: process.env.SAFE_ADDRESS
  };

  // Validate all required parameters are present
  const missingParams = Object.entries(params)
    .filter(([_, value]) => !value)
    .map(([key]) => key);

  if (missingParams.length > 0) {
    throw new Error(`Missing required parameters: ${missingParams.join(", ")}`);
  }

  try {
    // Convert parameters to the correct format
    const cliff = ethers.parseUnits((params.cliff * 24 * 60 * 60).toString(), 0); // Convert days to seconds
    const duration = ethers.parseUnits((params.duration * 24 * 60 * 60).toString(), 0); // Convert days to seconds
    const amount = ethers.parseUnits(params.amount, 18); // Convert to wei (18 decimals)
    const start = ethers.parseUnits(params.start, 0); // Unix timestamp

    console.log("Updating vesting schedule with parameters:");
    console.log(`- Allocation Type: ${params.allocationType}`);
    console.log(`- Cliff: ${params.cliff} days`);
    console.log(`- Start: ${new Date(params.start * 1000).toISOString()}`);
    console.log(`- Duration: ${params.duration} days`);
    console.log(`- Amount: ${params.amount} tokens`);
    console.log(`- Safe Address: ${params.safe}`);

    const tx = await sapTestToken.updateVestingSchedule(
      params.allocationType,
      cliff,
      start,
      duration,
      amount,
      params.safe
    );
    await tx.wait();

    console.log(`Successfully updated vesting schedule. Transaction hash: ${tx.hash}`);

    // Fetch and display the updated schedule
    const schedule = await sapTestToken.vestingSchedules(params.allocationType);
    console.log("\nUpdated vesting schedule:");
    console.log(`- Cliff: ${schedule.cliff / (24 * 60 * 60)} days`);
    console.log(`- Start: ${new Date(schedule.start * 1000).toISOString()}`);
    console.log(`- Duration: ${schedule.duration / (24 * 60 * 60)} days`);
    console.log(`- Amount: ${ethers.formatUnits(schedule.amount, 18)} tokens`);
    console.log(`- Released: ${ethers.formatUnits(schedule.released, 18)} tokens`);
    console.log(`- Safe Address: ${schedule.safe}`);

  } catch (error) {
    console.error("Error updating vesting schedule:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 