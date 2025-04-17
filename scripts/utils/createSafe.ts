import hre, { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { mine  } from "@nomicfoundation/hardhat-network-helpers";

import Safe, {
  SafeFactory, SafeAccountConfig, PredictedSafeProps } from '@safe-global/protocol-kit'


export default async function main() {
  //await mine(1) // https://github.com/NomicFoundation/hardhat/issues/5511#issuecomment-2288072104
  const [owner] = await ethers.getSigners();

  const mnemonic = ethers.Mnemonic.fromPhrase(process.env.MNEMONIC)
  const hdNode = await ethers.HDNodeWallet.fromMnemonic(mnemonic)
  console.log('hdnode', hdNode.address)
  console.log('owner', owner.address)
  if (hdNode.address !== owner.address) {
    throw new Error("Invalid mnemonic")
  }
  
  const safeAccountConfig:SafeAccountConfig = {
    owners: [owner.address],
    threshold: 1
  }
  const predictedSafe: PredictedSafeProps = {
    safeAccountConfig
  }
  let providerUrl;
  if (hre.network.name === "hardhat" || hre.network.name === "localhost") {
    providerUrl = "http://localhost:8545";
  } else {
    providerUrl = `${process.env.ALCHEMY_API_URL}${process.env.ALCHEMY_API_KEY}`
  }
  const protocolKit = await Safe.init({
    provider: providerUrl,
    signer: hdNode.privateKey,
    predictedSafe,

  })
  const deploymentTransaction = await protocolKit.createSafeDeploymentTransaction()
  
  const client = await protocolKit.getSafeProvider().getExternalSigner()
  const transactionHash = await client.sendTransaction({
    to: deploymentTransaction.to,
    value: BigInt(deploymentTransaction.value),
    data: deploymentTransaction.data as `0x${string}`
  })
  console.log('address', await protocolKit.getAddress())



  return true
}

if (require.main === module) {
  main()
    .then((result) =>{ 
      console.log("Result:", result);
      process.exit(0)
    })
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
