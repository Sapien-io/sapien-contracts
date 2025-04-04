const hre = require("hardhat")
const { ethers, upgrades  } = require('hardhat')
const fs = require('fs')
const path = require('path')

export default async function main() {
  console.log('authorizing upgrade for SapienRewards.sol')
  
  const networkName = hre.network.name

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
