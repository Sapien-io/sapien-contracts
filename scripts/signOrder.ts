import {
  Wallet,
  solidityPackedKeccak256,
  hashMessage,
  recoverAddress,
  getBytes,
} from "ethers";
import dotenv from "dotenv";
dotenv.config();

const { PRIVATE_KEY, OWNER1_ADDRESS } = process.env;

/**
 * Generate a message hash that matches the Solidity getMessageHash function.
 * @param user - The user's Ethereum address
 * @param rewardAmount - The reward amount as a BigInt
 * @param orderId - The order ID as a string
 * @returns The message hash as a bytes32 string
 */
function getMessageHash(
  user: string,
  rewardAmount: bigint,
  orderId: string
): string {
  // Use solidityPackedKeccak256 to match Solidity's abi.encodePacked and keccak256
  return solidityPackedKeccak256(
    ["address", "uint256", "string"],
    [user, rewardAmount, orderId]
  );
}

/**
 * Generate a signed message using the wallet's private key, applying the Ethereum prefix.
 * @param user - The user's Ethereum address
 * @param rewardAmount - The reward amount as a number
 * @param orderId - The order ID
 * @returns The signature and message hash
 */
async function signOrder(user: string, rewardAmount: number, orderId: string) {
  const wallet = new Wallet(PRIVATE_KEY!);
  const messageHash = getMessageHash(user, BigInt(rewardAmount), orderId);

  // Apply the Ethereum-specific prefix for EIP-191
  const ethSignedMessageHash = hashMessage(getBytes(messageHash));
  const signature = await wallet.signMessage(getBytes(messageHash)); // Make sure this is consistent

  return { signature, messageHash: ethSignedMessageHash };
}

/**
 * Verify the signature by recovering the signer address and comparing it to the authorized signer.
 * @param user - The user's Ethereum address
 * @param rewardAmount - The reward amount as a number
 * @param orderId - The order ID
 * @param signature - The generated signature
 * @returns The recovered signer's address
 */
function verifySignature(
  user: string,
  rewardAmount: number,
  orderId: string,
  signature: string
): string {
  const messageHash = getMessageHash(user, BigInt(rewardAmount), orderId);
  const ethSignedMessageHash = hashMessage(getBytes(messageHash));
  return recoverAddress(ethSignedMessageHash, signature);
}

// Testing the function
(async function testSignature() {
  const user = OWNER1_ADDRESS!;
  const rewardAmount = 1;
  const orderId = "testOrder12";

  // Generate signature
  const { signature, messageHash } = await signOrder(
    user,
    rewardAmount,
    orderId
  );
  console.log("Generated Signature:", signature);
  console.log("Message Hash:", messageHash);

  // Verify signature
  const recoveredSigner = verifySignature(
    user,
    rewardAmount,
    orderId,
    signature
  );
  console.log("Recovered Signer:", recoveredSigner);
  console.log("Authorized Signer:", OWNER1_ADDRESS!);

  const isValid =
    recoveredSigner.toLowerCase() === OWNER1_ADDRESS!.toLowerCase();
  console.log("Is signature valid:", isValid);
})();
