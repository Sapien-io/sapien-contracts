import hre, { ethers, upgrades } from 'hardhat'
import * as fs from 'fs'
import * as path from 'path'

import { loadConfig, Contract } from './utils/loadConfig'

import SafeApiKit from '@safe-global/api-kit'
import Safe, {
  SafeFactory, SafeAccountConfig, PredictedSafeProps } from '@safe-global/protocol-kit'

import {
  MetaTransactionData,
  OperationType
} from '@safe-global/types-kit'

export default async function main() {
  const config = loadConfig(Contract.SapienToken);

  const [owner] = await ethers.getSigners();

  const mnemonic = ethers.Mnemonic.fromPhrase(process.env.MNEMONIC)
  const hdNode = await ethers.HDNodeWallet.fromMnemonic(mnemonic)

  let providerUrl;
  if (hre.network.name === "hardhat" || hre.network.name === "localhost") {
    providerUrl = "http://localhost:8545";
  } else {
    providerUrl = `${process.env.ALCHEMY_API_URL}${process.env.ALCHEMY_API_KEY}`
  }

  const protocolKit = await Safe.init({
    provider: providerUrl,
    signer: hdNode.privateKey,
    safeAddress: config.safe,
  })

  const sapToken = await ethers.getContractAt("SapTestToken", config.token.proxyAddress)

 const SapV2 = await ethers.getContractFactory("SapTestToken") 

 const upgradedImpl = await upgrades.deployImplementation(SapV2, {
  kind: "uups" 
 })

  const callData = await sapToken.interface.encodeFunctionData(
    "authorizeUpgrade",
    [upgradedImpl]
  )

  const tx: MetaTransactionData = {
    to: config.token.proxyAddress,
    value: '0',
    data: callData,
    operation: OperationType.Call
  }

  const safeTx =  await protocolKit.createTransaction({
    transactions: [tx]
  })


  console.log('safeTx', safeTx)

  const safeHash = await protocolKit.getTransactionHash(safeTx)
  console.log('safeHash', safeHash)

  const signature = await protocolKit.signHash(safeHash)

  console.log('signature', signature)

  console.log('authorizing upgrade')
  return true
}

if (require.main == module) {
  main()
  .then((result) => {
    console.log("Result:", result);
    process.exit(0);

  })
  .catch((error) => {
    console.error(error);
    process.exit(1);

  });
}
