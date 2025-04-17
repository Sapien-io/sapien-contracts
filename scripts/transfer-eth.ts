import hre, {ethers} from 'hardhat'

export default async function main() {
  const [deployer] = await ethers.getSigners()

  return await deployer.sendTransaction({
    to: '0x3b8FA406dDb2Fb1bfFB933A4e05835708018fA87',
    value: ethers.parseEther('0.1')
  })
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
