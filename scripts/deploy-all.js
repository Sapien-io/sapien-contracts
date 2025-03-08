// Script to deploy all Sapien contracts in the correct order
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Import individual deployment scripts
const { deploy: deploySapToken } = require("./deploy-sap-test-token");
const { deploy: deploySapienStaking } = require("./deploy-sapien-staking");
const { deploy: deploySapienRewards } = require("./deploy-sapien-rewards");

// Function to wait for confirmations to ensure contract deployments are confirmed
const waitForConfirmations = async (tx, confirmations = 1) => {
  console.log(`Waiting for ${confirmations} confirmations...`);
  await tx.wait(confirmations);
};

// Function to ensure the deployments directory exists
const ensureDeploymentDirExists = () => {
  const deployDir = path.join(__dirname, "../deployments", hre.network.name);
  if (!fs.existsSync(deployDir)) {
    fs.mkdirSync(deployDir, { recursive: true });
  }
  return deployDir;
};

async function main() {
  console.log("Starting deployment of all Sapien contracts...");
  console.log(`Network: ${hre.network.name}`);
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);
  console.log(`Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);
  
  // Ensure deployments directory exists
  const deployDir = ensureDeploymentDirExists();
  
  // Summary to collect all deployment information
  const deploymentSummary = {
    network: hre.network.name,
    deployer: deployer.address,
    deploymentTime: new Date().toISOString(),
    contracts: {}
  };

  try {
    // 1. Deploy SAP Test Token
    console.log("\n===== Step 1: Deploy SAP Test Token =====");
    const sapToken = await deploySapToken();
    deploymentSummary.contracts.sapToken = {
      address: sapToken.address,
      name: await sapToken.name(),
      symbol: await sapToken.symbol(),
      totalSupply: (await sapToken.totalSupply()).toString()
    };
    
    // 2. Deploy Sapien Staking
    console.log("\n===== Step 2: Deploy Sapien Staking =====");
    const stakingContract = await deploySapienStaking();
    deploymentSummary.contracts.staking = {
      address: stakingContract.address,
      minStakeAmount: (await stakingContract.minStakeAmount()).toString(),
      lockPeriod: (await stakingContract.lockPeriod()).toString()
    };
    
    // 3. Deploy Sapien Rewards
    console.log("\n===== Step 3: Deploy Sapien Rewards =====");
    const rewardsContract = await deploySapienRewards();
    deploymentSummary.contracts.rewards = {
      address: rewardsContract.address,
      rewardRate: (await rewardsContract.rewardRate()).toString(),
      rewardInterval: (await rewardsContract.rewardInterval()).toString()
    };
    
    // 4. Transfer ownership of contracts if needed (example)
    console.log("\n===== Step 4: Configure Contract Relationships =====");
    
    // Fund the rewards contract with some tokens for distribution
    console.log("Funding rewards contract with initial tokens...");
    try {
      const initialRewardFund = ethers.utils.parseEther("10000");  // 10,000 tokens
      const transferTx = await sapToken.transfer(rewardsContract.address, initialRewardFund);
      await transferTx.wait();
      console.log(`Transferred ${ethers.utils.formatEther(initialRewardFund)} SAP tokens to rewards contract`);
      
      deploymentSummary.initialFunding = {
        amount: initialRewardFund.toString(),
        recipient: rewardsContract.address
      };
    } catch (error) {
      console.error("Error funding rewards contract:", error.message);
    }
    
    // Save comprehensive deployment summary
    fs.writeFileSync(
      path.join(deployDir, "DeploymentSummary.json"),
      JSON.stringify(deploymentSummary, null, 2)
    );
    
    console.log("\n===== Deployment Complete =====");
    console.log("All contracts have been deployed successfully.");
    console.log("Deployment summary saved to:", path.join(deployDir, "DeploymentSummary.json"));
    
    // Log deployment addresses for quick reference
    console.log("\nDeployed Contract Addresses:");
    console.log(`- SAP Token: ${sapToken.address}`);
    console.log(`- Staking Contract: ${stakingContract.address}`);
    console.log(`- Rewards Contract: ${rewardsContract.address}`);
  } catch (error) {
    console.error("\n===== Deployment Failed =====");
    console.error("Error during deployment:", error);
    
    // Save error information
    deploymentSummary.error = {
      message: error.message,
      stack: error.stack
    };
    
    fs.writeFileSync(
      path.join(deployDir, "DeploymentError.json"),
      JSON.stringify(deploymentSummary, null, 2)
    );
    
    console.error("Error details saved to:", path.join(deployDir, "DeploymentError.json"));
    throw error;
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Unhandled error during deployment:", error);
    process.exit(1);
  }); 