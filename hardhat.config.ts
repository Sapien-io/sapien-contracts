import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// Ensure private key is available
const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) {
  throw new Error("Private key not found in .env file");
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      gas: 12000000,
      blockGasLimit: 12000000,
    },
    "base-sepolia": {
      url: "https://sepolia.base.org",
      accounts: [PRIVATE_KEY],
    },
  },
};

export default config;
