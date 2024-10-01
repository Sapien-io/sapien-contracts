import { Alchemy, Network } from "alchemy-sdk";
import hre from "hardhat";
import { getSafe, proposeTransaction } from "./safe-utils";
import { SafeMultisigTransaction } from "./services";

const {
  ALCHEMY_API_KEY,
  NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA,
  PRIVATE_KEY,
  GNOSIS_SAFE_ADDRESS,
  ALCHEMY_API_URL,
} = process.env;

const settings = {
  apiKey: ALCHEMY_API_KEY,
  network: Network.BASE_SEPOLIA,
};
const alchemy = new Alchemy(settings);

const contract = require("../artifacts/contracts/SapTestToken.sol/SapTestToken.json");

async function sapTestRelease() {
  const safe = await getSafe(GNOSIS_SAFE_ADDRESS!);
  console.log("Safe fetched...", await safe.getAddress());

  // Create provider for transaction signing
  const provider = new hre.ethers.JsonRpcProvider(ALCHEMY_API_URL);

  // Create EIP-1193 compatible provider
  const eip1193Provider = {
    send: (method: string, params: any[]) => {
      return provider.send(method, params);
    },
    request: (request: { method: string; params?: any[] }) => {
      return provider.send(request.method, request.params || []);
    },
  };

  // Sign the transaction using the private key
  const signer = new hre.ethers.Wallet(PRIVATE_KEY!, provider);

  const releaseCon = await new hre.ethers.Contract(
    NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA!,
    contract.abi,
    signer
  );

  const txData: SafeMultisigTransaction = {
    safe: GNOSIS_SAFE_ADDRESS!,
    to: NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA!, // Address of the contract
    value: "0", // No ETH sent with the transaction
    data: releaseCon.interface.encodeFunctionData("releaseTokens", ["team"]),
    operation: 0, // Standard operation
    safeTxGas: 0, // Gas for the safe transaction, you can estimate this
    baseGas: 50000, // Base gas limit
    gasPrice: "0", // Gas price
    gasToken: "0x", // No gas token specified
    nonce: 0, // Set the transaction nonce dynamically
    submissionDate: new Date().toISOString(), // Current date for submission
    executionDate: "", // Will be filled after execution
    modified: "", // Modified after execution if needed
    transactionHash: "", // Placeholder for transaction hash
    safeTxHash: "", // Placeholder for safe transaction hash
    isExecuted: false, // Initially not executed
    origin: "External", // Specify transaction origin
    confirmationsRequired: 1, // Required confirmations
    trusted: true, // Trusted transaction
    signatures: "", // Placeholder for signatures
  };

  const signature = await signer.signTransaction(txData);
  txData.signatures = signature;

  await proposeTransaction(txData, eip1193Provider);
}

sapTestRelease()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
