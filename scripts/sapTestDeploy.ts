import hre from "hardhat";

async function sapTestInit() {
  // Get the contract factory
  const SapTestToken = await hre.ethers.getContractFactory("SapTestToken");

  // Specify the Gnosis Safe address and total supply
  const gnosisSafeAddress = process.env.GNOSIS_SAFE_ADDRESS;
  const totalSupply = hre.ethers.parseUnits("1000000000000000000000000000", 18);

  // Deploy the contract using OpenZeppelin Upgrades
  const contract = await hre.upgrades.deployProxy(
    SapTestToken,
    [gnosisSafeAddress, totalSupply],
    {
      kind: "uups",
    }
  );
  const address = await contract.getAddress();
  console.log("Contract deployed to   ", address);
}

// Execute the script
sapTestInit()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
