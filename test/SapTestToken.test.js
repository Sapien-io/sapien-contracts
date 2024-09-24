const SapTestToken = artifacts.require("SapTestToken");


contract("SapTestToken", (accounts) => {
  let tokenInstance;
  const gnosisSafeAddress = accounts[0]; // Using the first account as the Gnosis Safe address
  const userAddress = accounts[1]; // Another account to simulate a user
  const totalSupply = web3.utils.toWei("1000000000", "ether"); // 1 billion tokens

  // The vesting amounts
  const TEAM_ADVISORS_ALLOCATION = web3.utils.toWei("200000000", "ether");

  beforeEach(async () => {
    // Deploy and initialize the token contract
    tokenInstance = await SapTestToken.new();
    await tokenInstance.initialize(gnosisSafeAddress, totalSupply);
  });

  it("should deploy and initialize the contract correctly", async () => {
    const name = await tokenInstance.name();
    const symbol = await tokenInstance.symbol();
    const supply = await tokenInstance.totalSupply();

    assert.equal(name, "SapTestToken", "Token name should be SapTestToken");
    assert.equal(symbol, "SAPTEST", "Token symbol should be SAPTEST");
    assert.equal(supply.toString(), totalSupply, "Total supply should match the input");
  });

  it("should create a vesting schedule for the team", async () => {
    const vesting = await tokenInstance.vestingSchedules("team");
    
    assert.equal(vesting.amount.toString(), TEAM_ADVISORS_ALLOCATION, "Team allocation should match the hardcoded value");
  });

  it("should not allow non-Gnosis Safe address to pause", async () => {
    try {
      await tokenInstance.pause({ from: userAddress });
      assert.fail("Pause should only be callable by the Gnosis Safe");
    } catch (error) {
      assert(error.message.includes("Only the Safe can perform this"), "Expected Only the Safe can perform this error");
    }
  });

  it("should allow Gnosis Safe to pause", async () => {
    await tokenInstance.pause({ from: gnosisSafeAddress });
    const paused = await tokenInstance.paused();
    assert.equal(paused, true, "The contract should be paused");
  });

  it("should not allow non-Gnosis Safe to unpause", async () => {
    await tokenInstance.pause({ from: gnosisSafeAddress });
    try {
      await tokenInstance.unpause({ from: userAddress });
      assert.fail("Unpause should only be callable by the Gnosis Safe");
    } catch (error) {
      assert(error.message.includes("Only the Safe can perform this"), "Expected Only the Safe can perform this error");
    }
  });

  it("should allow Gnosis Safe to unpause", async () => {
    await tokenInstance.pause({ from: gnosisSafeAddress });
    await tokenInstance.unpause({ from: gnosisSafeAddress });
    const paused = await tokenInstance.paused();
    assert.equal(paused, false, "The contract should be unpaused");
  });
});
