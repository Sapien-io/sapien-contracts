require("dotenv").config();
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Fetch Gnosis Safe address and total supply from environment variables
  const gnosisSafeAddress = process.env.OWNER1_ADDRESS;
  const totalSupply = ethers.parseUnits("1000000000000000000000000000", 18);


  if (!gnosisSafeAddress || !totalSupply) {
    throw new Error(
      "GNOSIS_SAFE_ADDRESS and TOTAL_SUPPLY must be defined in .env"
    );
  }

  console.log("Deploying SapTestToken contract...");

  // Deploy the proxy contract
  const SapTestToken = await ethers.getContractFactory("SapTestToken");
  const contract = await upgrades.deployProxy(
    SapTestToken,
    [gnosisSafeAddress, totalSupply],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );

  // Wait for the deployment to be mined
  const address = await contract.getAddress();
  console.log("Contract deployed to", address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
