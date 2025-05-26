import hre, {ethers} from "hardhat";
import * as fs from "fs";
import * as path from "path";

export default async function main() {
  console.log("Initializing SAP Token...");
  
  const networkName = hre.network.name;
  console.log(`Network: ${networkName}`);
  const [deployer] = await ethers.getSigners();
  
  // Load deployment data
  const tokenData = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployments", networkName, "SapienToken.json"),
      "utf8"
    )
  );

  const SapToken = await ethers.getContractFactory("SapTestToken");
  const token = await SapToken.attach(tokenData.proxyAddress);
  
  console.log("SAP Token initialization complete!");
  return token;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error during initialization:", error);
      process.exit(1);
    });
}

