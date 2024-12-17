const { expectRevert } = require('@openzeppelin/test-helpers');
const SapTestToken = artifacts.require("SapTestToken");
const SapienRewards = artifacts.require("SapienRewards");


contract("SapienRewards", (accounts) => {
  let rewardInstance;
  let tokenInstance;
  const owner = "0xd3Eb8BBEf0564dbf35640B209632Ae52EF2fdf5e"
  const key = "f55400748b1ac13c95e6fc9e2db3c97534d46a8e92df2825b04678b0a4e5c206"

  const user = "0x090d4116EaDfcE0aea28f7c81FABEB282B72bCDa"
  console.log(",>>>>>>>>>",user)
  const rewardAmount = web3.utils.toWei("100", "ether");
  const depositAmount = web3.utils.toWei("1000", "ether");
  const totalSupply = web3.utils.toWei("1000000000", "ether"); 

  beforeEach(async () => {
    tokenInstance = await SapTestToken.new();
    rewardInstance = await SapienRewards.new();
    await tokenInstance.initialize(owner, totalSupply);
    await rewardInstance.initialize(tokenInstance.address, owner);
    
    // Transfer tokens to reward contract
    await tokenInstance.transfer(rewardInstance.address, depositAmount, { from: owner });
  });

  it.only("should initialize correctly", async () => {
    const rewardToken = await rewardInstance.rewardToken();
    // const signer = await rewardInstance.authorizedSigner();
    
    assert.equal(rewardToken, tokenInstance.address, "Reward token address should be correct");
    // assert.equal(signer, owner, "Authorized signer should be set correctly");
  });

  it("should allow the authorized signer to claim rewards", async () => {
    const orderId = web3.utils.sha3("order1");
    const messageHash = await rewardInstance.getMessageHash(user, rewardAmount, orderId, user);

    // Sign the message hash using the generated private key
    const signature = web3.eth.accounts.sign(messageHash, key).signature;

    // User claims reward using the signature
    await rewardInstance.claimReward(rewardAmount, orderId, signature, { from: user });
    const userBalance = await tokenInstance.balanceOf(user);

    assert.equal(userBalance.toString(), rewardAmount, "User should receive the correct reward amount");
  });

  it("should revert if reward is claimed with an invalid signature", async () => {
    const orderId = web3.utils.sha3("order1");
    const invalidSignature = web3.eth.sign(orderId, accounts[3]);

    await expectRevert(
      rewardInstance.claimReward(rewardAmount, orderId, invalidSignature, { from: user }),
      "Invalid order or signature"
    );
  });

  it("should revert if the order ID is already used", async () => {
    const orderId = web3.utils.sha3("order1");
    const messageHash = await rewardInstance.getMessageHash(user, rewardAmount, orderId, user);
    const signature = web3.eth.sign(messageHash, authorizedSigner);

    await rewardInstance.claimReward(rewardAmount, orderId, signature, { from: user });
    
    await expectRevert(
      rewardInstance.claimReward(rewardAmount, orderId, signature, { from: user }),
      "Order ID already used"
    );
  });

  it("should allow owner to deposit and withdraw tokens", async () => {
    const withdrawAmount = web3.utils.toWei("500", "ether");
    await rewardInstance.withdrawTokens(withdrawAmount, { from: owner });
    
    const contractBalance = await tokenInstance.balanceOf(rewardInstance.address);
    assert.equal(contractBalance.toString(), depositAmount - withdrawAmount, "Tokens should be withdrawn correctly");
  });

  it("should not allow non-owner to deposit tokens", async () => {
    await expectRevert(
      rewardInstance.withdrawTokens(web3.utils.toWei("500", "ether"), { from: user }),
      "Ownable: caller is not the owner"
    );
  });

  it("should allow only owner to pause and unpause contract", async () => {
    await rewardInstance.pause({ from: owner });
    const paused = await rewardInstance.paused();
    assert.equal(paused, true, "Contract should be paused by owner");

    await rewardInstance.unpause({ from: owner });
    const unpaused = await rewardInstance.paused();
    assert.equal(unpaused, false, "Contract should be unpaused by owner");
  });

  it("should not allow claimReward when paused", async () => {
    const orderId = web3.utils.sha3("order1");
    const messageHash = await rewardInstance.getMessageHash(user, rewardAmount, orderId, user);
    const signature = web3.eth.sign(messageHash, authorizedSigner);

    await rewardInstance.pause({ from: owner });

    await expectRevert(
      rewardInstance.claimReward(rewardAmount, orderId, signature, { from: user }),
      "Pausable: paused"
    );
  });

  it("should correctly add order to user’s Bloom filter", async () => {
    const orderId = web3.utils.sha3("order1");
    await rewardInstance.addOrderToBloomFilter(user, orderId, { from: owner });

    const redeemed = await rewardInstance.isOrderRedeemed(user, orderId);
    assert.equal(redeemed, true, "Order ID should be marked as redeemed in the Bloom filter");
  });

  it("should revert if the contract has insufficient token balance", async () => {
    const excessiveAmount = web3.utils.toWei("2000", "ether"); // Exceeds balance
    const orderId = web3.utils.sha3("order1");
    const messageHash = await rewardInstance.getMessageHash(user, excessiveAmount, orderId, user);
    const signature = web3.eth.sign(messageHash, authorizedSigner);

    await expectRevert(
      rewardInstance.claimReward(excessiveAmount, orderId, signature, { from: user }),
      "Insufficient token balance"
    );
  });
});
