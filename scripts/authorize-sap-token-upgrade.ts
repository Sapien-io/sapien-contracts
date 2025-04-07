import hre, { ethers, upgrades } from 'hardhat'
import * as fs from 'fs'
import * as path from 'path'

export default async function main() {
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
