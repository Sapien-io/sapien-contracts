import {
  ethers,
  BigNumberish,
  getAddress,
  ZeroAddress,
  JsonRpcProvider,
  Eip1193Provider,
} from "ethers";
import { SafeMultisigConfirmation, SafeMultisigTransaction } from "./services"; // Ensure these types are defined
import SafeApiKit from "@safe-global/api-kit";
import Safe, { SafeFactory } from "@safe-global/protocol-kit";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

const { ALCHEMY_API_URL, PRIVATE_KEY, GNOSIS_SAFE_ADDRESS } = process.env;

const SAFE_ABI = [
  "function isModuleEnabled(address module) public view returns (bool)",
  "function nonce() public view returns (uint256)",
  "function enableModule(address module) public",
  "function execTransaction(address to,uint256 value,bytes calldata data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address payable refundReceiver,bytes memory signatures) public payable returns (bool success)",
];

export const getSafe = async (address: string): Promise<ethers.Contract> => {
  const provider = new ethers.JsonRpcProvider(ALCHEMY_API_URL);
  return new ethers.Contract(address, SAFE_ABI, provider);
};

// Function to estimate gas
const estimateGas = async (
  safe: ethers.Contract,
  to: string,
  data: string
): Promise<BigNumberish> => {
  return await safe.estimateGas.execTransaction(
    to,
    "0",
    data,
    0,
    0,
    0,
    "0x",
    ZeroAddress,
    "0x"
  );
};

// Function to sign the transaction
const signTransaction = async (
  safe: ethers.Contract,
  tx: any,
  ownerSigner: ethers.Wallet
): Promise<string> => {
  const signature = await ownerSigner.signMessage(ethers.getBytes(tx.data));

  const confirmations: SafeMultisigConfirmation[] = [
    {
      owner: ownerSigner.address,
      signature,
      submissionDate: new Date().toISOString(),
    },
  ];

  return buildSignatureBytes(confirmations);
};

export const signAndExecuteTransaction = async (
  safeAddress: string,
  transaction: SafeMultisigTransaction,
  ownerSigner: ethers.Wallet,
  provider: JsonRpcProvider
): Promise<void> => {
  const safe = await getSafe(safeAddress);

  // Get current nonce
  const nonce = await safe.nonce();

  console.log("Current nonce:", nonce, transaction.to);

  // Check if the 'to' address is a valid address before executing
  if (!ethers.isAddress(transaction.to)) {
    throw new Error("Invalid address provided for transaction.");
  }

  // Build the transaction data
  const { to, data } = await buildExecuteTx(transaction);

  console.log("Transaction data:", to);

  // Prepare to execute the transaction
  // const safeTxGas = await estimateGas(safe, to, data);
  const txData = await safe.execTransaction.populateTransaction(
    to,
    transaction.value,
    data || "0x",
    transaction.operation,
    "100000",
    transaction.baseGas,
    transaction.gasPrice,
    transaction.gasToken,
    transaction.refundReceiver || ZeroAddress,
    "0x" // Placeholder for signatures
  );

  const tx = await {
    to: safeAddress,
    value: "0",
    data: txData.data,
  };

  // Sign the transaction
  const signatures = await signTransaction(safe, tx, ownerSigner);

  // Execute the transaction
  try {
    const txResponse = await safe.execTransaction(
      tx.to,
      tx.value,
      tx.data,
      transaction.operation,
      "100000",
      transaction.baseGas,
      transaction.gasPrice,
      transaction.gasToken,
      transaction.refundReceiver || ZeroAddress,
      signatures
    );

    await txResponse.wait(); // Wait for the transaction to be mined
    console.log("Transaction executed:", txResponse);
  } catch (error) {
    console.error("Transaction execution failed:", error);
    // Further error handling can be done here
  }
};

export const isModuleEnabled = async (
  safeAddress: string,
  module: string
): Promise<boolean> => {
  const safe = await getSafe(safeAddress);
  return await safe.isModuleEnabled(module);
};

export const getCurrentNonce = async (
  safeAddress: string
): Promise<BigNumberish> => {
  const safe = await getSafe(safeAddress);
  return await safe.nonce();
};

export const buildEnableModule = async (
  safeAddress: string,
  module: string
): Promise<{ to: string; value: string; data: string }> => {
  const safe = await getSafe(safeAddress);
  return {
    to: safeAddress,
    value: "0",
    data: (await safe.enableModule.populateTransaction(module)).data,
  };
};

export const buildSignatureBytes = (
  signatures: SafeMultisigConfirmation[]
): string => {
  const SIGNATURE_LENGTH_BYTES = 65;
  signatures.sort((left, right) =>
    left.owner.toLowerCase().localeCompare(right.owner.toLowerCase())
  );

  let signatureBytes = "0x";
  let dynamicBytes = "";
  for (const sig of signatures) {
    if (sig.signatureType === "CONTRACT_SIGNATURE") {
      const dynamicPartPosition = (
        signatures.length * SIGNATURE_LENGTH_BYTES +
        dynamicBytes.length / 2
      )
        .toString(16)
        .padStart(64, "0");

      const dynamicPartLength = (sig.signature.slice(2).length / 2)
        .toString(16)
        .padStart(64, "0");
      const staticSignature = `${sig.owner
        .slice(2)
        .padStart(64, "0")}${dynamicPartPosition}00`;
      const dynamicPartWithLength = `${dynamicPartLength}${sig.signature.slice(
        2
      )}`;

      signatureBytes += staticSignature;
      dynamicBytes += dynamicPartWithLength;
    } else {
      signatureBytes += sig.signature.slice(2);
    }
  }

  return signatureBytes + dynamicBytes;
};

export const getExecuteTxData = async (
  safeTx: SafeMultisigTransaction,
  provider: Eip1193Provider,
  signer: ethers.Wallet
): Promise<string> => {
  const apiKit = new SafeApiKit({
    chainId: 84532n,
  });
  const safe = await getSafe(safeTx.safe);
  console.log("Safe Address:", safeTx.safe);

  const safeTransactionData: MetaTransactionData = {
    to: safeTx.to,
    data: safeTx.data || "0x",
    value: "0",
  };

  const protocolKitOwner1 = await Safe.init({
    provider: provider,
    signer: PRIVATE_KEY,
    safeAddress: safeTx.safe,
  });

  const safeTransaction = await protocolKitOwner1.createTransaction({
    transactions: [safeTransactionData],
  });

  const safeTxHash = await protocolKitOwner1.getTransactionHash(
    safeTransaction
  );
  const signature = await protocolKitOwner1.signHash(safeTxHash);

  // Propose transaction to the service
  await apiKit.proposeTransaction({
    safeAddress: SAFE_ADDRESS,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: OWNER_1_ADDRESS,
    senderSignature: signature.data,
  });
};

export const buildExecuteTx = async (
  tx: SafeMultisigTransaction,
  provider: JsonRpcProvider,
  signer: ethers.Wallet
): Promise<{ to: string; data: string }> => {
  console.log("Building execute transaction...", getAddress(tx.safe));
  return {
    to: getAddress(tx.safe),
    data: await getExecuteTxData(tx, provider, signer),
  };
};

export const isEnsSupported = async (provider: JsonRpcProvider) => {
  try {
    await provider.resolveName("base-sepolia.eth");
    return true;
  } catch (error) {
    return false;
  }
};

export const initSafe = async () => {
  const apiKit = new SafeApiKit({
    chainId: 84532n,
  });

  const safeFactory = await SafeFactory.init({
    provider: ALCHEMY_API_URL!,
    signer: PRIVATE_KEY,
  });
};

export const sendTransaction = async () => {
  const apiKit = new SafeApiKit({
    chainId: 84532n,
  });
  const safeTransaction = await apiKit.createTransaction({ transactions });
};
