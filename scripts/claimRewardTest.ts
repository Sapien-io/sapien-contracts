import {
  Wallet,
  keccak256,
  toUtf8Bytes,
  concat,
  getBytes,
  ethers,
} from "ethers";
import hre from "hardhat";
import dotenv from "dotenv";
dotenv.config();

const { ALCHEMY_API_URL, REWARD_CONTRACT, PRIVATE_KEY, OWNER1_ADDRESS } =
  process.env;

// Step 1: Off-chain Sign Order Function with adjusted hashing
async function signOrder(
  user: string,
  rewardAmount: number,
  orderId: string,
  userWallet: string
) {
  const wallet = new Wallet(PRIVATE_KEY!);

  const userHash = keccak256(
    toUtf8Bytes("0x5B38Da6a701c568545dCfcB03FcB875f56beddC4")
  );
  const rewardAmountBigInt = BigInt(rewardAmount);
  const rewardAmountHex = ethers.toBeHex(rewardAmountBigInt, 32);
  const rewardAmountPadded = getBytes(rewardAmountHex);
  const orderIdHash = keccak256(toUtf8Bytes(orderId));
  const walletHash = keccak256(toUtf8Bytes(userWallet));

  const packedMessage = concat([
    getBytes(userHash),
    rewardAmountPadded,
    getBytes(orderIdHash),
    getBytes(walletHash),
  ]);
  const messageHash = keccak256(packedMessage);

  const ethSignedMessageHash = ethers.hashMessage(getBytes(messageHash));

  console.log("Message Hash:", getBytes(ethSignedMessageHash));
  const signature = await wallet.signMessage(getBytes(ethSignedMessageHash));

  return { signature, messageHash: ethSignedMessageHash };
}

// Step 2: Verification Logic (Simulate the Contract's verifyOrder Function)
function verifyOrderLocally(
  user: string,
  rewardAmount: number,
  orderId: string,
  userWallet: string,
  signature: string
) {
  const userHash = keccak256(toUtf8Bytes(user));
  const rewardAmountBigInt = BigInt(rewardAmount);
  const rewardAmountHex = ethers.toBeHex(rewardAmountBigInt, 32);
  const rewardAmountPadded = getBytes(rewardAmountHex);
  const orderIdHash = keccak256(toUtf8Bytes(orderId));
  const walletHash = keccak256(toUtf8Bytes(userWallet));

  const packedMessage = concat([
    getBytes(userHash),
    rewardAmountPadded,
    getBytes(orderIdHash),
    getBytes(walletHash),
  ]);
  const messageHash = keccak256(packedMessage);

  const ethSignedMessageHash = ethers.hashMessage(getBytes(messageHash));
  const recoveredAddress = ethers.verifyMessage(
    getBytes(ethSignedMessageHash),
    signature
  );

  console.log("Expected address:", OWNER1_ADDRESS);
  console.log("Recovered address:", recoveredAddress);

  return recoveredAddress.toLowerCase() === OWNER1_ADDRESS!.toLowerCase();
}

// Step 3: Call the Contract's claimReward function if the signature is valid
async function claimRewardOnContract(
  rewardAmount: number,
  orderId: string,
  signature: string
) {
  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");

  const rewardContract = new hre.ethers.Contract(
    REWARD_CONTRACT!,
    contract.abi,
    signer
  );

  try {
    console.log("Calling claimReward on the contract...");
    const tx = await rewardContract.claimReward(
      BigInt(rewardAmount),
      orderId,
      signature
    );

    console.log("Transaction sent. Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("Transaction confirmed:", receipt.transactionHash);
  } catch (error) {
    console.error("Error calling claimReward on the contract:", error);
  }
}

// Main function to test the signing, verification, and contract call
async function main() {
  const user = OWNER1_ADDRESS!;
  const rewardAmount = 1;
  const orderId = "testOrder123";
  const userWallet = OWNER1_ADDRESS!;

  const { signature } = await signOrder(
    user,
    rewardAmount,
    orderId,
    userWallet
  );
  console.log("Generated Signature:", signature);

  const isValid = verifyOrderLocally(
    user,
    rewardAmount,
    orderId,
    userWallet,
    signature
  );
  console.log("Is signature valid locally:", isValid);

  if (isValid) {
    await claimRewardOnContract(rewardAmount, orderId, signature);
  } else {
    console.log(
      "Signature verification failed locally. Contract call aborted."
    );
  }
}

// Run the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error running the script:", error);
    process.exit(1);
  });
