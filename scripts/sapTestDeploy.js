

async function main() {
    const hre = require("hardhat");
    const { ethers } = hre;
    const SapTestToken = await ethers.getContractFactory("SapTestToken");
    const sapTestToken = await SapTestToken.deploy();

    console.log("SapTestToken deployed to:", sapTestToken.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });