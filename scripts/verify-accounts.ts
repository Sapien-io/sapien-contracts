import { ethers } from "ethers";
import { config } from "dotenv";

// Load environment variables
config();

const mnemonic = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("MNEMONIC not found in .env file");
}

// Create an HD wallet from the mnemonic
const hdNode = ethers.HDNodeWallet.fromPhrase(mnemonic);

console.log("First account generated from mnemonic:");
console.log("Address:", hdNode.address);
console.log("Private Key:", hdNode.privateKey);

// Generate a few more accounts from the same mnemonic
for (let i = 1; i < 3; i++) {
  const account = hdNode.deriveChild(i);
  console.log(`\nAccount ${i + 1}:`);
  console.log("Address:", account.address);
  console.log("Private Key:", account.privateKey);
} 