import {
  keccak256,
  toUtf8Bytes,
  AbiCoder,
  concat,
  recoverAddress,
  Wallet,
} from "ethers";

import hre from "hardhat";
import dotenv from "dotenv";
dotenv.config();

const { ALCHEMY_API_URL, REWARD_CONTRACT, PRIVATE_KEY, OWNER1_ADDRESS } =
  process.env;

function getLocalDomainSeparator() {
  const domainTypeHash = keccak256(
    toUtf8Bytes(
      "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    )
  );
  const nameHash = keccak256(toUtf8Bytes("SapienRewards"));
  const versionHash = keccak256(toUtf8Bytes("1"));
  const chainId = 84532; // Base Sepolia chain ID
  const verifyingContract = REWARD_CONTRACT; // the contract address

  const abiCoder = new AbiCoder();

  // Then do an ABI encode and keccak:
  const encoded = abiCoder.encode(
    ["bytes32", "bytes32", "bytes32", "uint256", "address"],
    [domainTypeHash, nameHash, versionHash, chainId, verifyingContract]
  );

  return keccak256(encoded);
}

//@ts-ignore
function computeStructHash(walletAddress, rewardAmount, orderId) {
  // REWARD_TYPEHASH for "RewardClaim(address walletAddress,uint256 rewardAmount,string orderId)"
  const rewardClaimTypeHash = keccak256(
    toUtf8Bytes(
      "RewardClaim(address walletAddress,uint256 rewardAmount,string orderId)"
    )
  );

  // For the string field, your contract does keccak256(bytes(orderId)) in the abi.encode(...)
  const orderIdHash = keccak256(toUtf8Bytes(orderId));

  const abiCoder = new AbiCoder();
  // Then encode:
  const encoded = abiCoder.encode(
    ["bytes32", "address", "uint256", "bytes32"],
    [rewardClaimTypeHash, walletAddress, rewardAmount, orderIdHash]
  );

  return keccak256(encoded);
}

//@ts-ignore
function computeDigest(domainSeparator, structHash) {
  const prefix = new Uint8Array([0x19, 0x01]); // EIP-712 prefix
  const encoded = concat([prefix, domainSeparator, structHash]);
  return keccak256(encoded);
}

async function testStruct() {
  const localDomainSeparator = getLocalDomainSeparator();
  console.log("Local domain separator:", localDomainSeparator);

  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");

  const rewardContract = new hre.ethers.Contract(
    REWARD_CONTRACT!,
    contract.abi,
    signer
  );

  const walletAddress = OWNER1_ADDRESS;
  const rewardAmount = 1000;
  const orderId = "test-order-123";

  // Compute local struct hash
  const localStructHash = computeStructHash(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("Local struct hash:", localStructHash);

  // Fetch on-chain struct hash
  const onChainStructHash = await rewardContract.getStructHash(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("On-chain struct hash:", onChainStructHash);

  // Check if they match
  if (localStructHash === onChainStructHash) {
    console.log("✅ Struct hash matches!");
  } else {
    console.log("❌ Struct hash mismatch!");
  }
}

async function testDomainSeparator() {
  const localDomainSeparator = getLocalDomainSeparator();
  console.log("Local domain separator:", localDomainSeparator);

  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);

  // Initialize wallet with private key and provider
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);

  // Import contract ABI
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");

  // Connect to the rewards contract
  const rewardContract = new hre.ethers.Contract(
    REWARD_CONTRACT!,
    contract.abi,
    signer
  );

  // Compare to on-chain:
  const onChainDomainSeparator = await rewardContract.getDomainSeparator();

  console.log("On-chain domain separator:", onChainDomainSeparator);
}

async function signDigest(digest: string) {
  const signer = new Wallet(PRIVATE_KEY!);
  return await signer.signMessage(Buffer.from(digest.slice(2), "hex"));
}

//@ts-ignore
async function compareDigest() {
  const walletAddress = OWNER1_ADDRESS;
  const rewardAmount = 1000;
  const orderId = "test-order-123";
  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");

  const rewardContract = new hre.ethers.Contract(
    REWARD_CONTRACT!,
    contract.abi,
    signer
  );

  // Step 1: Get the Domain Separator from the contract
  const domainSeparator = await rewardContract.getDomainSeparator();
  console.log("Domain Separator (On-Chain):", domainSeparator);

  // Step 2: Compute the local struct hash
  const localStructHash = computeStructHash(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("Local Struct Hash:", localStructHash);

  // Step 3: Get the on-chain struct hash
  const onChainStructHash = await rewardContract.getStructHash(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("On-Chain Struct Hash:", onChainStructHash);

  // Step 4: Compute the local digest
  const localDigest = computeDigest(domainSeparator, localStructHash);
  console.log("Local Digest:", localDigest);

  // Step 5: Get the on-chain digest
  const onChainDigest = await rewardContract.getDigest(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("On-Chain Digest:", onChainDigest);

  // Step 6: Compare local and on-chain digests
  if (localDigest === onChainDigest) {
    console.log("✅ Digest matches!");
  } else {
    console.log("❌ Digest mismatch!");
  }

  const domain = {
    name: "SapienRewards", // Must match the contract's DOMAIN_SEPARATOR setup
    version: "1", // Must match the contract version
    chainId: 84532, // Base Sepolia chain ID
    verifyingContract: REWARD_CONTRACT, // Contract address
  };

  const types = {
    RewardClaim: [
      { name: "walletAddress", type: "address" },
      { name: "rewardAmount", type: "uint256" },
      { name: "orderId", type: "string" },
    ],
  };

  const message = {
    walletAddress: walletAddress,
    rewardAmount: rewardAmount,
    orderId: orderId,
  };

  const signature = await signer.signTypedData(domain, types, message);

  console.log("Signature:", signature);

  // Step 7: Recover the signer off-chain
  const recoveredOffChain = recoverAddress(localDigest, signature);
  console.log("Recovered Address (Off-Chain):", recoveredOffChain);

  // Step 8: Recover the signer on-chain (optional)
  const recoveredOnChain = await rewardContract.getRecoveredSigner(
    walletAddress,
    rewardAmount,
    orderId,
    signature
  );
  console.log("Recovered Address (On-Chain):", recoveredOnChain);

  // Step 9: Compare recovered addresses
  if (recoveredOffChain.toLowerCase() === recoveredOnChain.toLowerCase()) {
    console.log("✅ Recovered addresses match!");
  } else {
    console.log("❌ Recovered address mismatch!");
  }
}

async function recoverSigner() {
  const provider = new ethers.JsonRpcProvider(ALCHEMY_API_URL);
  const contract = require("../artifacts/contracts/Rewards.sol/SapienRewards.json");
  const signature =
    "0x9c710368256fb924b956e19572bd962bd95311c97761ca28c30c54d39cff16006c5774dca1d42e207835e71c8410dff0fcf10db0cbea520ba7b5e5a85089d2e01c";
  const rewardContract = new ethers.Contract(
    REWARD_CONTRACT,
    contract.abi,
    provider
  );

  const walletAddress = OWNER1_ADDRESS;
  const rewardAmount = BigInt("1000000000000000000000"); // Matching the on-chain call
  const orderId = "c6d049b6-0f6f-4b76-aec7-da0dc54aa10b"; // Exact orderId used on-chain

  // Fetch domain separator and compute struct hash
  const domainSeparator = await rewardContract.getDomainSeparator();
  console.log("On-Chain Domain Separator:", domainSeparator);

  const structHash = computeStructHash(walletAddress, rewardAmount, orderId);
  console.log("Local Struct Hash:", structHash);

  const onChainStructHash = await rewardContract.getStructHash(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("On-Chain Struct Hash:", onChainStructHash);

  // Compare struct hashes
  if (structHash === onChainStructHash) {
    console.log("✅ Struct hashes match!");
  } else {
    console.log("❌ Struct hash mismatch!");
  }

  // Compute the digest
  const digest = computeDigest(domainSeparator, structHash);
  console.log("Local Digest:", digest);

  const onChainDigest = await rewardContract.getDigest(
    walletAddress,
    rewardAmount,
    orderId
  );
  console.log("On-Chain Digest:", onChainDigest);

  // Compare digests
  if (digest === onChainDigest) {
    console.log("✅ Digests match!");
  } else {
    console.log("❌ Digest mismatch!");
  }

  // Recover the address
  const recoveredAddress = ethers.recoverAddress(digest, signature);
  console.log("Recovered Address:", recoveredAddress);
}

recoverSigner()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
