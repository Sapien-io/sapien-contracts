import { Alchemy, Network } from "alchemy-sdk";
import { Contract, Provider } from "ethers";
import { ethers } from "hardhat";

const { ALCHEMY_API_KEY, NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA, PRIVATE_KEY } =
  process.env;

const settings = {
  apiKey: ALCHEMY_API_KEY,
  network: Network.BASE_SEPOLIA,
};
const alchemy = new Alchemy(settings);

const contract = require("../artifacts/contracts/SapTestToken.sol/SapTestToken.json");

async function sapTestRelease() {
  const signer = new ethers.Wallet(PRIVATE_KEY!, ethers.provider);

  const relaseCon = await new ethers.Contract(
    NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA!,
    contract.abi,
    signer
  );

  try {
    const tx = await relaseCon.releaseTokens("investors");
    console.log("Transaction sent:", tx.hash);

    // Wait for the transaction to be confirmed
    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
  } catch (error) {
    console.error("Error calling releaseTokens:", error);
  }
}

sapTestRelease()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
