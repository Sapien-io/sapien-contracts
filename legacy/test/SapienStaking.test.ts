import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Contract, Signer } from "ethers";
import "@nomicfoundation/hardhat-chai-matchers";

describe("SapienStaking", function () {
  let SapienToken: any;
  let sapienToken: any;
  let SapienStaking: any;
  let sapienStaking: any;
  let owner: Signer;
  let sapienSigner: Signer;
  let user: Signer;
  let gnosisSafe: Signer;
  let domain: {
    name: string;
    version: string;
    chainId: bigint;
    verifyingContract: string;
  };
  let types: {
    Stake: Array<{ name: string; type: string; }>;
  };

  const BASE_STAKE = ethers.parseUnits("1000", 18);
  const ONE_DAY = BigInt(24 * 60 * 60);
  const COOLDOWN_PERIOD = BigInt(2) * ONE_DAY;

  beforeEach(async function () {
    [owner, sapienSigner, user, gnosisSafe] = await ethers.getSigners();

    // Deploy mock ERC20 token
    SapienToken = await ethers.getContractFactory("MockERC20");
    sapienToken = await SapienToken.deploy("Sapien Token", "SAP");

    // Deploy SapienStaking
    SapienStaking = await ethers.getContractFactory("SapienStaking");
    sapienStaking = await upgrades.deployProxy(SapienStaking, [
      await sapienToken.getAddress(),
      await sapienSigner.getAddress(),
      await gnosisSafe.getAddress()
    ]);

    // Mint tokens to user and approve staking contract
    await sapienToken.mint(await user.getAddress(), ethers.parseUnits("10000", 18));
    await sapienToken.connect(user).approve(
      await sapienStaking.getAddress(),
      ethers.MaxUint256
    );

    // Setup EIP-712 domain and types
    domain = {
      name: "SapienStaking",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await sapienStaking.getAddress()
    };

    types = {
      Stake: [
        { name: "userWallet", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "orderId", type: "bytes32" },
        { name: "actionType", type: "uint8" }
      ]
    };
  });

  async function signStakeMessage(
    wallet: string,
    amount: bigint,
    orderId: string,
    actionType: number
  ): Promise<string> {
    const value = {
      userWallet: wallet,
      amount: amount,
      orderId: ethers.id(orderId),
      actionType: actionType
    };

    return await sapienSigner.signTypedData(domain, types, value);
  }

  describe("Staking", function () {
    it("Should allow staking with valid signature", async function () {
      const amount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "order1";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);

      // Get balances before staking
      const userBalanceBefore = await sapienToken.balanceOf(await user.getAddress());
      const contractBalanceBefore = await sapienToken.balanceOf(await sapienStaking.getAddress());

      await expect(sapienStaking.connect(user).stake(
        amount,
        lockUpPeriod,
        ethers.id(orderId),
        signature
      )).to.emit(sapienStaking, "Staked")
        .withArgs(await user.getAddress(), amount, BigInt(10500), lockUpPeriod, ethers.id(orderId));

      // Verify token transfers
      const userBalanceAfter = await sapienToken.balanceOf(await user.getAddress());
      const contractBalanceAfter = await sapienToken.balanceOf(await sapienStaking.getAddress());
      
      expect(userBalanceBefore - userBalanceAfter).to.equal(amount);
      expect(contractBalanceAfter - contractBalanceBefore).to.equal(amount);

      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(orderId));
      expect(stakerInfo.amount).to.equal(amount);
      expect(stakerInfo.isActive).to.be.true;
    });

    it("Should reject staking with amount less than minimum stake", async function () {
      const amount = BASE_STAKE / BigInt(2); // Less than 1,000 SAPIEN
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "order2";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);

      await expect(
        sapienStaking.connect(user).stake(
          amount,
          lockUpPeriod,
          ethers.id(orderId),
          signature
        )
      ).to.be.revertedWith("Minimum 1,000 SAPIEN required");
    });
  });

  describe("Staking Edge Cases", function () {
    it("Should reject staking with zero amount", async function () {
      const amount = 0n;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "zero_stake";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);
      
      await expect(
        sapienStaking.connect(user).stake(amount, lockUpPeriod, ethers.id(orderId), signature)
      ).to.be.reverted;
    });
    
    it("Should reject staking with invalid lock-up period", async function () {
      const amount = BASE_STAKE;
      const invalidPeriod = BigInt(45) * ONE_DAY; // Not 30/90/180/365 days
      const orderId = "invalid_period";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);
      
      await expect(
        sapienStaking.connect(user).stake(amount, invalidPeriod, ethers.id(orderId), signature)
      ).to.be.reverted;
    });
    
    it("Should calculate different multipliers for each lock-up period", async function () {
      // Test for 30 days (ONE_MONTH_MAX_MULTIPLIER = 10500)
      const amount30 = BASE_STAKE;
      const lockUpPeriod30 = BigInt(30) * ONE_DAY;
      const orderId30 = "period_30";
      const signature30 = await signStakeMessage(await user.getAddress(), amount30, orderId30, 0);
      
      await sapienStaking.connect(user).stake(amount30, lockUpPeriod30, ethers.id(orderId30), signature30);
      const info30 = await sapienStaking.stakers(await user.getAddress(), ethers.id(orderId30));
      expect(info30.multiplier).to.equal(10500);
      
      // Test for 90 days (THREE_MONTHS_MAX_MULTIPLIER = 11000)
      const amount90 = BASE_STAKE;
      const lockUpPeriod90 = BigInt(90) * ONE_DAY;
      const orderId90 = "period_90";
      const signature90 = await signStakeMessage(await user.getAddress(), amount90, orderId90, 0);
      
      await sapienStaking.connect(user).stake(amount90, lockUpPeriod90, ethers.id(orderId90), signature90);
      const info90 = await sapienStaking.stakers(await user.getAddress(), ethers.id(orderId90));
      expect(info90.multiplier).to.equal(11000);
      
      // Add similar tests for 180 and 365 days
    });
  });

  describe("Unstaking", function () {
    const stakeOrderId = "stake1";
    const initiateUnstakeOrderId = "unstake1_init";
    const unstakeOrderId = "unstake1_complete";
    let stakedAmount: bigint;
    
    beforeEach(async function () {
      stakedAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      
      const signature = await signStakeMessage(await user.getAddress(), stakedAmount, stakeOrderId, 0);
      await sapienStaking.connect(user).stake(
        stakedAmount, 
        lockUpPeriod, 
        ethers.id(stakeOrderId),
        signature
      );
      
      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(stakeOrderId));
      expect(stakerInfo.isActive).to.be.true;
      expect(stakerInfo.amount).to.equal(stakedAmount);

      await time.increase(BigInt(30) * ONE_DAY);
    });

    it("Should allow initiating unstake", async function () {
      const signature = await signStakeMessage(
        await user.getAddress(), 
        stakedAmount,
        initiateUnstakeOrderId,
        1
      );

      await expect(
        sapienStaking.connect(user).initiateUnstake(
          stakedAmount,
          ethers.id(initiateUnstakeOrderId),
          ethers.id(stakeOrderId),
          signature
        )
      ).to.emit(sapienStaking, "UnstakingInitiated");
    });

    it("Should allow unstaking after cooldown period", async function () {
      const initiateSignature = await signStakeMessage(
        await user.getAddress(), 
        stakedAmount,
        initiateUnstakeOrderId,
        1
      );
      await sapienStaking.connect(user).initiateUnstake(
        stakedAmount,
        ethers.id(initiateUnstakeOrderId),
        ethers.id(stakeOrderId),
        initiateSignature
      );

      await time.increase(COOLDOWN_PERIOD);

      const unstakeSignature = await signStakeMessage(
        await user.getAddress(), 
        stakedAmount,
        unstakeOrderId,
        2
      );
      await expect(
        sapienStaking.connect(user).unstake(
          stakedAmount,
          ethers.id(unstakeOrderId),
          ethers.id(stakeOrderId),
          unstakeSignature
        )
      ).to.emit(sapienStaking, "Unstaked");
    });

    it("Should allow partial unstaking and reset cooldown state", async function () {
      // Initial stake
      const stakeAmount = BASE_STAKE * BigInt(2); // Double the minimum stake to allow partial unstake
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "partial_stake";
      const initiatePartialUnstakeOrderId = "partial_unstake_init";
      const partialUnstakeOrderId = "partial_unstake_complete";
      
      // Get the current totalStaked value before we start
      const initialTotalStaked = await sapienStaking.totalStaked();
      
      // Create and apply the stake
      const stakeSignature = await signStakeMessage(await user.getAddress(), stakeAmount, stakeOrderId, 0);
      await sapienStaking.connect(user).stake(
        stakeAmount, 
        lockUpPeriod, 
        ethers.id(stakeOrderId),
        stakeSignature
      );
      
      // Verify the stake is active
      const initialStakeInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(stakeOrderId));
      expect(initialStakeInfo.isActive).to.be.true;
      expect(initialStakeInfo.amount).to.equal(stakeAmount);
      
      // Complete the lock-up period
      await time.increase(lockUpPeriod);
      
      // Calculate partial unstake amount (50% of original stake)
      const partialAmount = stakeAmount / BigInt(2);
      
      // Initiate partial unstake
      const initiateSignature = await signStakeMessage(
        await user.getAddress(), 
        partialAmount,
        initiatePartialUnstakeOrderId,
        1
      );
      await sapienStaking.connect(user).initiateUnstake(
        partialAmount,
        ethers.id(initiatePartialUnstakeOrderId),
        ethers.id(stakeOrderId),
        initiateSignature
      );
      
      // Verify cooldown started with correct amount
      const cooldownStakeInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(stakeOrderId));
      expect(cooldownStakeInfo.cooldownStart).to.be.greaterThan(0);
      expect(cooldownStakeInfo.cooldownAmount).to.equal(partialAmount);
      
      // Complete cooldown period
      await time.increase(COOLDOWN_PERIOD);
      
      // Get user's token balance before unstaking
      const balanceBefore = await sapienToken.balanceOf(await user.getAddress());
      
      // Complete the partial unstake
      const unstakeSignature = await signStakeMessage(
        await user.getAddress(), 
        partialAmount,
        partialUnstakeOrderId,
        2
      );
      await sapienStaking.connect(user).unstake(
        partialAmount,
        ethers.id(partialUnstakeOrderId),
        ethers.id(stakeOrderId),
        unstakeSignature
      );
      
      // Verify position is still active but with reduced amount
      const finalStakeInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(stakeOrderId));
      expect(finalStakeInfo.isActive).to.be.true;
      expect(finalStakeInfo.amount).to.equal(stakeAmount - partialAmount);
      
      // Verify cooldown state was reset
      expect(finalStakeInfo.cooldownStart).to.equal(0);
      expect(finalStakeInfo.cooldownAmount).to.equal(0);
      
      // Verify user received tokens (without multiplier applied)
      const expectedTransferAmount = partialAmount;
      const balanceAfter = await sapienToken.balanceOf(await user.getAddress());
      expect(balanceAfter - balanceBefore).to.equal(expectedTransferAmount);
      
      // Verify contract's total staked amount was reduced correctly
      expect(await sapienStaking.totalStaked()).to.equal(initialTotalStaked + stakeAmount - partialAmount);
    });
  });

  describe("Instant Unstake", function () {
    beforeEach(async function () {
      // No need to mint tokens to contract anymore
    });

    it("Should allow instant unstake with penalty", async function () {
      const stakeAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "stake2";
      const instantUnstakeOrderId = "instant_unstake2";
      
      // Get initial balances
      const userBalanceBefore = await sapienToken.balanceOf(await user.getAddress());
      const safeBalanceBefore = await sapienToken.balanceOf(await gnosisSafe.getAddress());
      
      const stakeSignature = await signStakeMessage(await user.getAddress(), stakeAmount, stakeOrderId, 0);
      await sapienStaking.connect(user).stake(
        stakeAmount, 
        lockUpPeriod, 
        ethers.id(stakeOrderId),
        stakeSignature
      );
      
      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(stakeOrderId));
      expect(stakerInfo.isActive).to.be.true;

      const unstakeSignature = await signStakeMessage(await user.getAddress(), stakeAmount, instantUnstakeOrderId, 3);
      const expectedPayout = (stakeAmount * BigInt(80)) / BigInt(100);
      const expectedPenalty = (stakeAmount * BigInt(20)) / BigInt(100);
      
      await expect(
        sapienStaking.connect(user).instantUnstake(
          stakeAmount,
          ethers.id(instantUnstakeOrderId),
          ethers.id(stakeOrderId),
          unstakeSignature
        )
      ).to.emit(sapienStaking, "InstantUnstake")
        .withArgs(
          await user.getAddress(), 
          expectedPayout, 
          ethers.id(instantUnstakeOrderId)
        );

      // Verify token transfers
      const userBalanceAfter = await sapienToken.balanceOf(await user.getAddress());
      const safeBalanceAfter = await sapienToken.balanceOf(await gnosisSafe.getAddress());
      
      // User should receive 80% of their stake back
      expect(userBalanceAfter - userBalanceBefore).to.equal(expectedPayout - stakeAmount);
      // Safe should receive 20% penalty
      expect(safeBalanceAfter - safeBalanceBefore).to.equal(expectedPenalty);
    });
  });

  describe("Cross-contract Signature Security", function () {
    it("Should reject signatures from different contract names", async function () {
      // Create domain for SapienRewards contract
      const rewardsDomain = {
        name: "SapienRewards", // Different contract name
        version: "1",
        chainId: domain.chainId,
        verifyingContract: await sapienStaking.getAddress()
      };

      // Create types for SapienRewards contract
      const rewardsTypes = {
        RewardClaim: [
          { name: "userWallet", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "orderId", type: "bytes32" }
        ]
      };

      const orderId = "stake1";
      const amount = BASE_STAKE;
      const value = {
        userWallet: await user.getAddress(),
        amount: amount,
        orderId: ethers.id(orderId)
      };

      // Sign with SapienRewards domain
      const signature = await sapienSigner.signTypedData(rewardsDomain, rewardsTypes, value);

      // Attempt to use SapienRewards signature in SapienStaking contract should fail
      await expect(
        sapienStaking.connect(user).stake(
          amount,
          BigInt(30) * ONE_DAY, // 30 day lock period
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });

    it("Should reject signatures from different contract addresses", async function () {
      // Create domain for same contract name but different address
      const fakeDomain = {
        name: "SapienStaking",
        version: "1",
        chainId: domain.chainId,
        verifyingContract: await user.getAddress() // Different contract address
      };

      const orderId = "stake2";
      const amount = BASE_STAKE;
      const value = {
        userWallet: await user.getAddress(),
        amount: amount,
        orderId: ethers.id(orderId),
        actionType: 0 // STAKE action
      };

      // Sign with fake domain
      const signature = await sapienSigner.signTypedData(fakeDomain, types, value);

      // Attempt to use signature with wrong contract address should fail
      await expect(
        sapienStaking.connect(user).stake(
          amount,
          BigInt(30) * ONE_DAY,
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });

    it("Should reject signatures with mismatched action types", async function () {
      const orderId = "stake3";
      const amount = BASE_STAKE;
      const value = {
        userWallet: await user.getAddress(),
        amount: amount,
        orderId: ethers.id(orderId),
        actionType: 1 // INITIATE_UNSTAKE instead of STAKE
      };

      // Sign with wrong action type
      const signature = await sapienSigner.signTypedData(domain, types, value);

      // Attempt to use signature with wrong action type should fail
      await expect(
        sapienStaking.connect(user).stake(
          amount,
          BigInt(30) * ONE_DAY,
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });
  });

  describe("Owner Functions", function () {
    it("Should allow Gnosis Safe to pause and unpause contract", async function () {
      // Pause the contract
      await sapienStaking.connect(gnosisSafe).pause();
      expect(await sapienStaking.paused()).to.be.true;
      
      // Verify staking is not possible when paused
      const amount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "pause_test";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);
      
      await expect(
        sapienStaking.connect(user).stake(amount, lockUpPeriod, ethers.id(orderId), signature)
      ).to.be.reverted;
      
      // Unpause and verify staking works again
      await sapienStaking.connect(gnosisSafe).unpause();
      expect(await sapienStaking.paused()).to.be.false;
      
      await expect(
        sapienStaking.connect(user).stake(amount, lockUpPeriod, ethers.id(orderId), signature)
      ).not.to.be.reverted;
    });
    
    it("Should not allow non-safe to pause or unpause", async function () {
      await expect(
        sapienStaking.connect(user).pause()
      ).to.be.revertedWith("Only the Safe can perform this");
      
      await expect(
        sapienStaking.connect(user).unpause()
      ).to.be.revertedWith("Only the Safe can perform this");
    });

    it("Should allow Gnosis Safe to transfer ownership", async function () {
      const [_, __, ___, ____, newOwner] = await ethers.getSigners();
      
      await expect(
        sapienStaking.connect(gnosisSafe).transferOwnership(await newOwner.getAddress())
      ).to.emit(sapienStaking, "OwnershipTransferred")
        .withArgs(await gnosisSafe.getAddress(), await newOwner.getAddress());
    });

    it("Should not allow non-safe to transfer ownership", async function () {
      const [_, __, ___, ____, newOwner] = await ethers.getSigners();
      
      await expect(
        sapienStaking.connect(user).transferOwnership(await newOwner.getAddress())
      ).to.be.revertedWith("Only the Safe can perform this");
    });
  });

  describe("Unstaking Error Cases", function () {
    beforeEach(async function () {
      // Setup a stake
      const amount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "error_test_stake";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);
      
      await sapienStaking.connect(user).stake(amount, lockUpPeriod, ethers.id(orderId), signature);
    });
    
    it("Should reject unstake initiation before lock period ends", async function () {
      const orderId = "error_test_stake";
      const initiateOrderId = "early_unstake_init";
      const amount = BASE_STAKE;
      const signature = await signStakeMessage(
        await user.getAddress(), 
        amount,
        initiateOrderId,
        1
      );
      
      // Try to unstake before lock period ends
      await expect(
        sapienStaking.connect(user).initiateUnstake(
          amount,
          ethers.id(initiateOrderId),
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });
    
    it("Should reject unstake without prior initiation", async function () {
      const orderId = "error_test_stake";
      const unstakeOrderId = "no_init_unstake";
      const amount = BASE_STAKE;
      
      // Complete lock period
      await time.increase(BigInt(30) * ONE_DAY);
      
      const signature = await signStakeMessage(
        await user.getAddress(),
        amount,
        unstakeOrderId,
        2
      );
      
      // Try to unstake without initiation
      await expect(
        sapienStaking.connect(user).unstake(
          amount,
          ethers.id(unstakeOrderId),
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });
    
    it("Should reject unstake before cooldown period ends", async function () {
      const orderId = "error_test_stake";
      const initiateOrderId = "early_cooldown_init";
      const unstakeOrderId = "early_cooldown_unstake";
      const amount = BASE_STAKE;
      
      // Complete lock period
      await time.increase(BigInt(30) * ONE_DAY);
      
      // Initiate unstake
      const initiateSignature = await signStakeMessage(
        await user.getAddress(),
        amount,
        initiateOrderId,
        1
      );
      
      await sapienStaking.connect(user).initiateUnstake(
        amount,
        ethers.id(initiateOrderId),
        ethers.id(orderId),
        initiateSignature
      );
      
      // Try to unstake before cooldown period ends
      const unstakeSignature = await signStakeMessage(
        await user.getAddress(),
        amount,
        unstakeOrderId,
        2
      );
      
      await expect(
        sapienStaking.connect(user).unstake(
          amount,
          ethers.id(unstakeOrderId),
          ethers.id(orderId),
          unstakeSignature
        )
      ).to.be.reverted;
    });
  });

  describe("Instant Unstake Restrictions", function () {
    beforeEach(async function () {
      // No need to mint tokens to contract anymore
    });

    it("Should reject instant unstake after lock period", async function () {
      const stakeAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "lock_completed_stake";
      const instantUnstakeOrderId = "lock_completed_unstake";
      
      // Create the stake
      const stakeSignature = await signStakeMessage(
        await user.getAddress(), 
        stakeAmount, 
        stakeOrderId, 
        0
      );
      
      await sapienStaking.connect(user).stake(
        stakeAmount,
        lockUpPeriod,
        ethers.id(stakeOrderId),
        stakeSignature
      );
      
      // Complete the lock period
      await time.increase(lockUpPeriod);
      
      // Try instant unstake after lock period
      const unstakeSignature = await signStakeMessage(
        await user.getAddress(),
        stakeAmount,
        instantUnstakeOrderId,
        3
      );
      
      await expect(
        sapienStaking.connect(user).instantUnstake(
          stakeAmount,
          ethers.id(instantUnstakeOrderId),
          ethers.id(stakeOrderId),
          unstakeSignature
        )
      ).to.be.reverted;
    });
    
    it("Should correctly transfer penalty to owner", async function () {
      const stakeAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "penalty_stake";
      const instantUnstakeOrderId = "penalty_unstake";
      
      // Create the stake
      const stakeSignature = await signStakeMessage(
        await user.getAddress(), 
        stakeAmount, 
        stakeOrderId, 
        0
      );
      
      await sapienStaking.connect(user).stake(
        stakeAmount,
        lockUpPeriod,
        ethers.id(stakeOrderId),
        stakeSignature
      );
      
      // Get gnosis safe balance before
      const safeBalanceBefore = await sapienToken.balanceOf(await gnosisSafe.getAddress());
      
      // Perform instant unstake
      const unstakeSignature = await signStakeMessage(
        await user.getAddress(),
        stakeAmount,
        instantUnstakeOrderId,
        3
      );
      
      await sapienStaking.connect(user).instantUnstake(
        stakeAmount,
        ethers.id(instantUnstakeOrderId),
        ethers.id(stakeOrderId),
        unstakeSignature
      );
      
      // Check penalty was transferred to gnosis safe (20% of stakeAmount)
      const expectedPenalty = (stakeAmount * BigInt(20)) / BigInt(100);
      const safeBalanceAfter = await sapienToken.balanceOf(await gnosisSafe.getAddress());
      
      expect(safeBalanceAfter - safeBalanceBefore).to.equal(expectedPenalty);
    });
  });

  describe("Order ID Security", function () {
    it("Should prevent reusing the same order ID", async function () {
      const amount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "reused_order";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);
      
      // First stake with this order ID should succeed
      await sapienStaking.connect(user).stake(
        amount,
        lockUpPeriod,
        ethers.id(orderId),
        signature
      );
      
      // Second attempt with same order ID should fail
      await expect(
        sapienStaking.connect(user).stake(
          amount,
          lockUpPeriod,
          ethers.id(orderId),
          signature
        )
      ).to.be.reverted;
    });
  });

  describe("Upgradeability", function () {
    let SapienStakingV2: any;
    let sapienStakingV2: any;
    
    beforeEach(async function () {
      // No need to mint tokens to contract anymore
    });
    
    it("Should allow upgrading to a new implementation", async function () {
      const oldTotalSupply = await sapienStaking.totalStaked();
      const SapienStakingV2Factory = await ethers.getContractFactory("SapienStakingV2Mock");

      const sapienStakingV2Address = await upgrades.prepareUpgrade(
        await sapienStaking.getAddress(),
        SapienStakingV2Factory
      );

      // Authorize the upgrade with Gnosis Safe
      await sapienStaking.connect(gnosisSafe).authorizeUpgrade(sapienStakingV2Address);

      // Impersonate the Gnosis Safe
      await ethers.provider.send("hardhat_impersonateAccount", [await gnosisSafe.getAddress()]);
      const impersonatedSafe = await ethers.getImpersonatedSigner(await gnosisSafe.getAddress());

      // Create a new factory instance with the impersonated signer
      const SapienStakingV2FactoryWithSafe = await ethers.getContractFactory("SapienStakingV2Mock", impersonatedSafe);

      // Perform the upgrade as the Safe
      sapienStakingV2 = await upgrades.upgradeProxy(
        await sapienStaking.getAddress(),
        SapienStakingV2FactoryWithSafe
      );

      // Stop impersonating
      await ethers.provider.send("hardhat_stopImpersonatingAccount", [await gnosisSafe.getAddress()]);
      
      // Check that state is preserved
      expect(await sapienStakingV2.totalStaked()).to.equal(oldTotalSupply);
      
      // Check that new functionality is available (assuming the mock has a new function)
      expect(await sapienStakingV2.getVersion()).to.equal("2.0");
    });
    
    it("Should not allow non-owners to upgrade the contract", async function () {
      SapienStakingV2 = await ethers.getContractFactory("SapienStakingV2Mock", user);
      
      await expect(
        upgrades.upgradeProxy(await sapienStaking.getAddress(), SapienStakingV2)
      ).to.be.reverted;
    });
  });
}); 
