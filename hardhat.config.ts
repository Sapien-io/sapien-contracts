import "@nomicfoundation/hardhat-toolbox";

require("dotenv").config({ path: __dirname + "/.env" });

require("hardhat-deploy");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");

const { ALCHEMY_API_URL, PRIVATE_KEY, BASESCAN_API_KEY } = process.env;

module.exports = {
  solidity: "0.8.24",
  defaultNetwork: "base-sepolia",
  networks: {
    hardhat: {},
    sepolia: {
      url: ALCHEMY_API_URL,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    "base-sepolia": {
      url: "https://sepolia.base.org",
      accounts: [`0x${PRIVATE_KEY}`],
      gasPrice: 1000000000,
    },
  },
  etherscan: {
    apiKey: BASESCAN_API_KEY,
  },
};
