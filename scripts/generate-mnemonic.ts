import { ethers } from "ethers";

// Generate a new random mnemonic
const mnemonic = ethers.Wallet.createRandom().mnemonic?.phrase;

if (!mnemonic) {
  throw new Error("Failed to generate mnemonic");
}

console.log("Generated mnemonic:");
console.log(mnemonic);
console.log("\nAdd this to your .env file as:");
console.log(`MNEMONIC="${mnemonic}"`); 