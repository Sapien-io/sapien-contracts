import {
  Wallet,
  solidityPackedKeccak256,
  hashMessage,
  recoverAddress,
  getBytes,
  verifyMessage,
  Signature,
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
  console.log("Message Hash:", messageHash);
  // Apply the Ethereum-specific prefix for EIP-191
  const ethSignedMessageHash = hashMessage(getBytes(messageHash));
  const signature = await wallet.signMessage(getBytes(messageHash));

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
  // const ethSignedMessageHash = hashMessage(getBytes(messageHash));
  const recoveredSigner = verifyMessage(messageHash, signature);

  const parsedSignature = Signature.from(signature);
  console.log("JS r:", parsedSignature.r);
  console.log("JS s:", parsedSignature.s);
  console.log("JS v:", parsedSignature.v);
  // console.log(
  //   "Recovered Signer (JS):",
  //   verifyMessage(ethSignedMessageHash, signature)
  // );

  return recoveredSigner;
}

// Testing the function
(async function testVerifyOrder() {
  const user = "0x090d4116EaDfcE0aea28f7c81FABEB282B72bCDa"; // Replace with an actual address
  const rewardAmount = 1000000000000000000000;
  const orderId = "fd989e27-79bb-40af-83a5-0bb56485433c";

  console.log("Testing order verification...");

  // Generate signature
  const { signature, messageHash } = await signOrder(
    user,
    rewardAmount,
    orderId
  );
  //2592000
  console.log("Signature:", signature);

  console.log(
    "block sig:",
    "0x9479138d8150792d36cba4d73b5e78fbf4faaae73d14fdebe5f1311c820d06da29db13d612409eea99240fea30a91d7a68455892f40ae8a1c809d62cda572f3e1c"
  );

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
