const SapienStaking = artifacts.require("SapienStaking");
const { ethers } = require("ethers");

contract("SapienStaking", (accounts) => {
  let stakingInstance;
  const [sapienAddress, userWallet] = accounts; // Use first account as Sapien and second as a user
  const rewardAmount = web3.utils.toWei("1000", "ether"); // 1,000 tokens in wei
  const orderId = "fd989e27-79bb-40af-83a5-0bb56485433c";
  let signature;

  beforeEach(async () => {
    // Deploy and initialize the SapienStaking contract
    stakingInstance = await SapienStaking.new();
    await stakingInstance.initialize(sapienAddress, sapienAddress);

    // Generate signature for the test
    const privateKey = "0x4c0883a69102937d6231471b5dbb6204fe512961708279ee5f1620c1fd01219b"; // Replace with a valid private key
    const wallet = new ethers.Wallet(privateKey);

    const messageHash = ethers.utils.solidityKeccak256(
      ["address", "uint256", "string"],
      [userWallet, rewardAmount, orderId]
    );

    const ethSignedMessageHash = ethers.utils.solidityKeccak256(
      ["bytes"],
      [ethers.utils.solidityPack(["string", "bytes32"], ["\x19Ethereum Signed Message:\n32", messageHash])]
    );

    signature = await wallet.signMessage(ethers.utils.arrayify(ethSignedMessageHash));
  });

  it("should correctly verify a valid signature", async () => {
    const result = await stakingInstance.verifyOrder(
      userWallet,
      rewardAmount,
      orderId,
      signature,
      { from: sapienAddress }
    );

    assert.equal(result, true, "The signature should be valid");
  });

  it("should fail for an invalid signature", async () => {
    const invalidSignature = signature.substring(0, signature.length - 2) + "00"; // Corrupt the signature

    const result = await stakingInstance.verifyOrder(
      userWallet,
      rewardAmount,
      orderId,
      invalidSignature,
      { from: sapienAddress }
    );

    assert.equal(result, false, "The signature should be invalid");
  });

  it("should fail if the signer is not the authorized Sapien address", async () => {
    const otherAccount = accounts[2];
    const result = await stakingInstance.verifyOrder(
      otherAccount,
      rewardAmount,
      orderId,
      signature,
      { from: sapienAddress }
    );

    assert.equal(result, false, "The signature should fail for an unauthorized signer");
  });
});
