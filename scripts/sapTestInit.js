const { ethers, upgrades } = require("hardhat");


async function main() {
    // Get the contract factory
    const SapTestToken = await ethers.getContractFactory("SapTestToken");

    // Specify the Gnosis Safe address and total supply
    const gnosisSafeAddress = process.env.GNOSIS_SAFE_ADDRESS
    const totalSupply = "1000000000000000000000000000";

    // Deploy the contract using OpenZeppelin Upgrades
    await upgrades.deployProxy(SapTestToken, [gnosisSafeAddress, totalSupply], { initializer: "initialize" });


}

// Execute the script
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


