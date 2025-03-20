// Script to deploy all Sapien contracts in the correct order
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Import individual deployment scripts - note these should return Promises
const deploySapToken = require("./deploy-sap-test-token");
const deploySapienStaking = require("./deploy-sapien-staking");
const deploySapienRewards = require("./deploy-sapien-rewards");

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
  console.log(`Account balance: ${ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
  
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
    // Get the tx receipt and wait for it to be mined
    console.log("Deploying SAP Token...");
    const sapToken = await deploySapToken.deploy();
    
    // Verify token deployment was successful by checking the contract code
    const tokenCode = await ethers.provider.getCode(sapToken.address);
    if (tokenCode === '0x' || tokenCode === '0x0') {
      throw new Error("SAP Token deployment failed - no contract code at address");
    }
    console.log(`SAP Token deployed at ${sapToken.address} - verified contract exists on chain`);
    console.log("SAP Token deployment complete");
    
    // Wait for blockchain to stabilize before next deployment
    await new Promise(resolve => setTimeout(resolve, 5000));

    // 2. Deploy Sapien Staking
    console.log("\n===== Step 2: Deploy Sapien Staking =====");
    console.log("Deploying Staking Contract...");
    const stakingContract = await deploySapienStaking.deployAndSetup();
    
    // Verify staking deployment was successful
    const stakingCode = await ethers.provider.getCode(stakingContract.address);
    if (stakingCode === '0x' || stakingCode === '0x0') {
      throw new Error("Staking contract deployment failed - no contract code at address");
    }
    console.log(`Staking Contract deployed at ${stakingContract.address} - verified contract exists on chain`);
    console.log("Staking Contract deployment complete");
    
    // Wait for blockchain to stabilize before next deployment
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    // 3. Deploy Sapien Rewards
    console.log("\n===== Step 3: Deploy Sapien Rewards =====");
    console.log("Deploying Rewards Contract...");
    const rewardsContract = await deploySapienRewards.deployAndSetup();
    
    // Verify rewards deployment was successful
    const rewardsCode = await ethers.provider.getCode(rewardsContract.address);
    if (rewardsCode === '0x' || rewardsCode === '0x0') {
      throw new Error("Rewards contract deployment failed - no contract code at address");
    }
    console.log(`Rewards Contract deployed at ${rewardsContract.address} - verified contract exists on chain`);
    console.log("Rewards Contract deployment complete");
    
    // Wait for blockchain to stabilize before continuing
    await new Promise(resolve => setTimeout(resolve, 5000));

    deploymentSummary.contracts.sapToken = {
      address: sapToken.address,
      name: await sapToken.name(),
      symbol: await sapToken.symbol(),
      totalSupply: (await sapToken.totalSupply()).toString()
    };
    
    // Small delay to ensure file system sync
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 4. Transfer ownership of contracts if needed (example)
    console.log("\n===== Step 4: Configure Contract Relationships =====");
    
    // Fund the rewards contract with some tokens for distribution
    console.log("Funding rewards contract with initial tokens...");
    try {
      const initialRewardFund = ethers.utils.parseEther("10000");  // 10,000 tokens
      const transferTx = await sapToken.transfer(rewardsContract.address, initialRewardFund);
      await transferTx.wait();
      console.log(`Transferred ${ethers.formatEther(initialRewardFund)} SAP tokens to rewards contract`);
      
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