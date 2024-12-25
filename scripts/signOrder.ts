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
  const rewardAmount = 1000;
  const orderId = "f4e5ca6b-84e9-48b9-b2b6-a4e890b28405";

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
    "created sig",
    "0x4d145d7428caceffbaddb0f3c05d91a84d26a134b381b8ae12cbcb8f1bdcdd302a491be9ef852d2300ad09cd79c026bc9f0dce948d0122b5976e4b95890070931b"
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
