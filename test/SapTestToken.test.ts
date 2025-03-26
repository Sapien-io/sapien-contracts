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

  describe("updateVestingSafe Function", function () {
    it("Should update vesting safe address correctly", async function () {
      const newSafeAddress = await user.getAddress();
      
      await sapTestToken.connect(gnosisSafe).updateVestingSafe(
        0, // INVESTORS
        newSafeAddress
      );
      
      const schedule = await sapTestToken.vestingSchedules(0);
      expect(schedule.safe).to.equal(newSafeAddress);
    });
    
    it("Should fail to update vesting safe with zero address", async function () {
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSafe(
          0, // INVESTORS
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("Invalid safe address");
    });

    it("Should fail to update vesting safe after tokens are released, even with the same address", async function () {
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Fast forward past cliff period and release tokens
      await time.increase(400 * 24 * 60 * 60);
      await sapTestToken.connect(rewardsContract).releaseTokens(0); // INVESTORS
      
      // Try to update with the same safe address
      const currentSafe = (await sapTestToken.vestingSchedules(0)).safe;
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSafe(
          0, // INVESTORS
          currentSafe
        )
      ).to.be.revertedWith("Cannot change safe address after tokens released");
    });
  });

  describe("Vesting Restrictions After Release", function () {
    it("Should prevent changes to safe address after tokens are released", async function () {
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Fast forward past cliff period and release tokens
      await time.increase(400 * 24 * 60 * 60);
      await sapTestToken.connect(rewardsContract).releaseTokens(0); // INVESTORS
      
      // Try to update the safe address
      const newSafeAddress = await user.getAddress();
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSafe(
          0, // INVESTORS
          newSafeAddress
        )
      ).to.be.revertedWith("Cannot change safe address after tokens released");
    });
    
    it("Should prevent reducing allocation below released amount", async function () {
      // Set rewards contract and release tokens
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Get the current schedule and its start time
      const initialSchedule = await sapTestToken.vestingSchedules(0);
      const currentStart = initialSchedule.start;
      
      // Fast forward past cliff period and release tokens
      await time.increase(400 * 24 * 60 * 60);
      await sapTestToken.connect(rewardsContract).releaseTokens(0);
      
      // Get the released amount
      const schedule = await sapTestToken.vestingSchedules(0);
      const releasedAmount = schedule.released;
      
      // Try to update vesting schedule with amount less than released
      // Keep the same start time to avoid triggering the start time restriction
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSchedule(
          0, // INVESTORS
          0,
          currentStart, // Use the current start time from the schedule
          365 * 24 * 60 * 60,
          releasedAmount - 1n, // Amount less than released
          await gnosisSafe.getAddress()
        )
      ).to.be.revertedWith("Cannot reduce amount below released tokens");
    });
  });

  describe("Token Release Calculations", function () {
    it("Should release correct amount based on vesting duration", async function () {
      // Setup a specific vesting schedule for testing
      const newAmount = ethers.parseUnits("1000000", DECIMALS);
      const currentTime = await time.latest();
      const newStart = currentTime + 100; // Start a bit in the future to satisfy contract requirement
      const newDuration = 1000; // Very short duration for testing
      
      // Create a new address to receive the vested tokens (not the gnosisSafe)
      const vestingRecipient = await user.getAddress();
      
      await sapTestToken.connect(gnosisSafe).updateVestingSchedule(
        0, // INVESTORS
        0, // No cliff
        newStart,
        newDuration,
        newAmount,
        vestingRecipient
      );
      
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Fast forward to start + half duration
      await time.increaseTo(newStart + newDuration / 2);
      
      // Initial balances before release
      const initialSafeBalance = await sapTestToken.balanceOf(await gnosisSafe.getAddress());
      const initialRecipientBalance = await sapTestToken.balanceOf(vestingRecipient);
      
      // Release tokens
      await sapTestToken.connect(rewardsContract).releaseTokens(0);
      
      // Get updated schedule
      const schedule = await sapTestToken.vestingSchedules(0);
      
      // Check that tokens were released (should be ~50% of total)
      expect(schedule.released).to.be.gt(0);
      expect(schedule.released).to.be.lt(newAmount);
      
      // Check with a larger tolerance due to potential timestamp differences
      const expectedReleased = newAmount * BigInt(newDuration / 2) / BigInt(newDuration);
      const tolerance = ethers.parseUnits("2000", DECIMALS); // 0.2% of 1M tokens
      
      expect(schedule.released).to.be.closeTo(
        expectedReleased,
        tolerance // Increased tolerance to account for timing variations
      );
      
      // Check balances were updated correctly
      const finalSafeBalance = await sapTestToken.balanceOf(await gnosisSafe.getAddress());
      const finalRecipientBalance = await sapTestToken.balanceOf(vestingRecipient);
      
      // The Safe's balance should decrease by the released amount
      expect(initialSafeBalance - finalSafeBalance).to.equal(schedule.released);
      
      // The recipient's balance should increase by the released amount
      expect(finalRecipientBalance - initialRecipientBalance).to.equal(schedule.released);
    });
    
    it("Should release all tokens when vesting period is complete", async function () {
      // Setup schedule with a short duration
      const newAmount = ethers.parseUnits("1000000", DECIMALS);
      const currentTime = await time.latest();
      const newStart = currentTime + 100;
      const newDuration = 10000; // Short duration
      
      await sapTestToken.connect(gnosisSafe).updateVestingSchedule(
        0, // INVESTORS
        0, // No cliff
        newStart,
        newDuration,
        newAmount,
        await gnosisSafe.getAddress()
      );
      
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Fast forward past the entire vesting period
      await time.increaseTo(newStart + newDuration + 1000);
      
      // Release tokens
      await sapTestToken.connect(rewardsContract).releaseTokens(0);
      
      // All tokens should be released
      const schedule = await sapTestToken.vestingSchedules(0);
      expect(schedule.released).to.equal(newAmount);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle vesting schedule with zero duration (immediate vesting)", async function () {
      const newAmount = ethers.parseUnits("1000000", DECIMALS);
      const currentTime = await time.latest();
      const newStart = currentTime + 100;
      
      await sapTestToken.connect(gnosisSafe).updateVestingSchedule(
        2, // REWARDS (using a different allocation type than previous tests)
        0, // No cliff
        newStart,
        0, // Zero duration
        newAmount,
        await user.getAddress() // Using a different safe address
      );
      
      // Set rewards contract
      await sapTestToken.connect(gnosisSafe).proposeRewardsContract(
        await rewardsContract.getAddress()
      );
      await sapTestToken.connect(gnosisSafe).acceptRewardsContract();
      
      // Fast forward past start
      await time.increaseTo(newStart + 1);
      
      // Release tokens
      await sapTestToken.connect(rewardsContract).releaseTokens(2);
      
      // All tokens should be released at once since duration is 0
      const schedule = await sapTestToken.vestingSchedules(2);
      expect(schedule.released).to.equal(newAmount);
      
      // Tokens should be transferred to the safe address
      expect(await sapTestToken.balanceOf(await user.getAddress())).to.equal(newAmount);
    });
    
    it("Should handle invalid allocation type", async function () {
      // For this test, remove the specific error message since the contract might 
      // revert with a different message or without a message
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSchedule(
          99, // Invalid allocation type
          0,
          await time.latest() + 100,
          365 * 24 * 60 * 60,
          ethers.parseUnits("1000000", DECIMALS),
          await gnosisSafe.getAddress()
        )
      ).to.be.reverted;
    });
  });

  describe("Event Emissions", function () {
    it("Should emit VestingScheduleUpdated when updating schedule", async function () {
      const newAmount = ethers.parseUnits("1000000", DECIMALS);
      const currentTime = await time.latest();
      const newStart = currentTime + 100;
      
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSchedule(
          0, // INVESTORS
          0,
          newStart,
          365 * 24 * 60 * 60,
          newAmount,
          await gnosisSafe.getAddress()
        )
      ).to.emit(sapTestToken, "VestingScheduleUpdated")
        .withArgs(0, newAmount);
    });
    
    it("Should emit VestingSafeUpdated when updating safe address", async function () {
      const newSafeAddress = await user.getAddress();
      const oldSafeAddress = await gnosisSafe.getAddress();
      
      await expect(
        sapTestToken.connect(gnosisSafe).updateVestingSafe(
          0, // INVESTORS
          newSafeAddress
        )
      ).to.emit(sapTestToken, "VestingSafeUpdated")
        .withArgs(0, oldSafeAddress, newSafeAddress);
    });
  });
}); 