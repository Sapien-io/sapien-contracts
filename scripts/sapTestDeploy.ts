import hre from "hardhat";
import { getSafe, isEnsSupported } from "./safe";
import { SafeMultisigTransaction } from "./services";
import { ContractInterface } from "ethers";
import { proposeTransaction } from "./safe-utils";

// Load environment variables
const { GNOSIS_SAFE_ADDRESS, PRIVATE_KEY, ALCHEMY_API_URL } = process.env;

// Define the ABI for the Gnosis Safe contract
// const SAFE_ABI: ContractInterface = [
//   "function initialize(address, uint256) public", // Method to initialize the contract
// ];

async function sapTestInit() {
  // Validate required environment variables
  if (!GNOSIS_SAFE_ADDRESS || !PRIVATE_KEY) {
    throw new Error(
      "GNOSIS_SAFE_ADDRESS and PRIVATE_KEY must be defined in the environment variables"
    );
  }

  // Get the contract factory for deploying SapTestToken
  const SapTestToken = await hre.ethers.getContractFactory("SapTestToken");
  console.log("Starting deployment...");

  // Define the total supply of tokens to be deployed
  const totalSupply = hre.ethers.parseUnits("1000000000000000000000000000", 18);
  console.log(
    "Preparing to deploy contract via Gnosis Safe...",
    GNOSIS_SAFE_ADDRESS
  );

  // Deploy the proxy contract using UUPS
  const contract = await hre.upgrades.deployProxy(
    SapTestToken,
    [GNOSIS_SAFE_ADDRESS, totalSupply],
    { kind: "uups" }
  );

  // Get the address of the deployed contract
  const address = await contract.getAddress();
  console.log("Contract deployed to", address);

  // Fetch the safe contract instance
  const safe = await getSafe(GNOSIS_SAFE_ADDRESS);
  console.log("Safe fetched...", await safe.getAddress());

  // Prepare transaction data for the multisig
  const txData: SafeMultisigTransaction = {
    safe: GNOSIS_SAFE_ADDRESS,
    to: address, // Use the deployed contract's address
    value: "0", // No ETH sent with the transaction
    data: "0x", // Encode the initialize function call
    operation: 0, // Standard operation
    safeTxGas: 0, // Gas for the safe transaction
    baseGas: 50000, // Base gas limit
    gasPrice: "0", // Gas price
    gasToken: "0x", // No gas token specified
    nonce: 1, // Set the transaction nonce
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
  const signer = new hre.ethers.Wallet(PRIVATE_KEY, provider);
  const signature = await signer.signTransaction(txData);

  // Add the signature to the transaction data
  txData.signatures = signature;

  // Propose the transaction to the Gnosis Safe
  await proposeTransaction(txData, eip1193Provider);
}

// Execute the script
sapTestInit()
  .then(() => process.exit(0)) // Exit successfully
  .catch((error) => {
    console.error(error); // Log any errors
    process.exit(1); // Exit with an error
  });
