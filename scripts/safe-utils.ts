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

const { ALCHEMY_API_URL, PRIVATE_KEY, GNOSIS_SAFE_ADDRESS, OWNER1_ADDRESS } =
  process.env;

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

export const proposeTransaction = async (
  safeTx: SafeMultisigTransaction,
  provider: Eip1193Provider
) => {
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
    safeAddress: GNOSIS_SAFE_ADDRESS!,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: OWNER1_ADDRESS!,
    senderSignature: signature.data,
  });
};
