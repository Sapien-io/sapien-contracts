import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Contract, Signer } from "ethers";

describe("SapTestToken", function () {
  let sapTestToken: any;
  let owner: Signer;
  let gnosisSafe: Signer;
  let rewardsContract: Signer;
  let user: Signer;

  // Constants from the contract
  const DECIMALS = 18;
  const INVESTORS_ALLOCATION = ethers.parseUnits("300000000", DECIMALS);
  const TEAM_ADVISORS_ALLOCATION = ethers.parseUnits("200000000", DECIMALS);
  const LABELING_REWARDS_ALLOCATION = ethers.parseUnits("150000000", DECIMALS);
  const AIRDROPS_ALLOCATION = ethers.parseUnits("150000000", DECIMALS);
  const COMMUNITY_TREASURY_ALLOCATION = ethers.parseUnits("100000000", DECIMALS);
  const STAKING_INCENTIVES_ALLOCATION = ethers.parseUnits("50000000", DECIMALS);
  const LIQUIDITY_INCENTIVES_ALLOCATION = ethers.parseUnits("50000000", DECIMALS);
  const TOTAL_SUPPLY = INVESTORS_ALLOCATION + 
    TEAM_ADVISORS_ALLOCATION + 
    LABELING_REWARDS_ALLOCATION + 
    AIRDROPS_ALLOCATION + 
    COMMUNITY_TREASURY_ALLOCATION + 
    STAKING_INCENTIVES_ALLOCATION + 
    LIQUIDITY_INCENTIVES_ALLOCATION;

  beforeEach(async function () {
    [owner, gnosisSafe, rewardsContract, user] = await ethers.getSigners();
    
    const SapTestToken = await ethers.getContractFactory("SapTestToken");
    sapTestToken = await upgrades.deployProxy(SapTestToken, [
      await gnosisSafe.getAddress(),
      TOTAL_SUPPLY
    ]);
  });

  describe("Initialization", function () {
    it("Should initialize with correct values", async function () {
      expect(await sapTestToken.name()).to.equal("SapTestToken");
      expect(await sapTestToken.symbol()).to.equal("PTSPN");
      expect(await sapTestToken.balanceOf(await gnosisSafe.getAddress())).to.equal(TOTAL_SUPPLY);
    });

    it("Should fail to initialize with zero address", async function () {
      const SapTestToken = await ethers.getContractFactory("SapTestToken");
      await expect(
        upgrades.deployProxy(SapTestToken, [ethers.ZeroAddress, TOTAL_SUPPLY])
      ).to.be.revertedWith("Invalid Gnosis Safe address");
    });

    it("Should fail to initialize with incorrect total supply", async function () {
      const SapTestToken = await ethers.getContractFactory("SapTestToken");
      await expect(
        upgrades.deployProxy(SapTestToken, [await gnosisSafe.getAddress(), 0])
      ).to.be.revertedWith("Total supply must be greater than zero");
    });
  });

  describe("Vesting Schedules", function () {
    it("Should update vesting schedule correctly", async function () {
      const newCliff = 180 * 24 * 60 * 60; // 180 days
      const currentTime = await time.latest();
      const newStart = currentTime + 1000; // Set start time in the future
      const newDuration = 365 * 24 * 60 * 60; // 1 year
      const newAmount = ethers.parseUnits("1000000", DECIMALS);

      await sapTestToken.connect(gnosisSafe).updateVestingSchedule(
        0, // INVESTORS
        newCliff,
        newStart,
        newDuration,
        newAmount,
        await gnosisSafe.getAddress() // Use gnosisSafe instead of user
      );

      const schedule = await sapTestToken.vestingSchedules(0);
      expect(schedule.cliff).to.equal(newCliff);
      expect(schedule.start).to.equal(newStart);
      expect(schedule.duration).to.equal(newDuration);
      expect(schedule.amount).to.equal(newAmount);
      expect(schedule.safe).to.equal(await gnosisSafe.getAddress());
    });

    it("Should fail to update vesting schedule from non-safe address", async function () {
      await expect(
        sapTestToken.connect(user).updateVestingSchedule(
          0,
          0,
          await time.latest(),
          365 * 24 * 60 * 60,
          ethers.parseUnits("1000000", DECIMALS),
          await user.getAddress()
        )
      ).to.be.revertedWith("Only the Safe can perform this");
    });
  });

  describe("Rewards Contract Management", function () {
    it("Should properly set rewards contract in two steps", async function () {
      // Step 1: Propose new rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      
      // Step 2: Accept the proposed rewards contract
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      expect(await sapTestToken.rewardsContract()).to.equal(
        await rewardsContract.getAddress()
      );
    });

    it("Should fail to accept rewards contract without proposal", async function () {
      await expect(
        sapTestToken.connect(gnosisSafe).acceptRewardsContract()
      ).to.be.revertedWith("No pending rewards contract");
    });
  });

  describe("Token Release", function () {
    it("Should release tokens after cliff period", async function () {
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();

      // Fast forward past cliff period
      await time.increase(400 * 24 * 60 * 60); // 400 days

      // Release tokens
      await expect(
        sapTestToken.connect(rewardsContract).releaseTokens(0) // INVESTORS
      ).to.emit(sapTestToken, "TokensReleased");
    });

    it("Should fail to release tokens before cliff", async function () {
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();

      await expect(
        sapTestToken.connect(rewardsContract).releaseTokens(0) // INVESTORS
      ).to.be.revertedWith("Cliff not reached");
    });
  });

  describe("Pause Functionality", function () {
    it("Should pause and unpause correctly", async function () {
      await sapTestToken.connect(gnosisSafe).pause();
      expect(await sapTestToken.paused()).to.be.true;

      await sapTestToken.connect(gnosisSafe).unpause();
      expect(await sapTestToken.paused()).to.be.false;
    });

    it("Should prevent token releases while paused", async function () {
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();

      await sapTestToken.connect(gnosisSafe).pause();
      
      await time.increase(400 * 24 * 60 * 60); // 400 days

      await expect(
        sapTestToken.connect(rewardsContract).releaseTokens(0)
      ).to.be.reverted;
    });
  });
}); 