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
    [owner, sapienSigner, user] = await ethers.getSigners();

    // Deploy mock ERC20 token
    SapienToken = await ethers.getContractFactory("MockERC20");
    sapienToken = await SapienToken.deploy("Sapien Token", "SAP");

    // Deploy SapienStaking
    SapienStaking = await ethers.getContractFactory("SapienStaking");
    sapienStaking = await upgrades.deployProxy(SapienStaking, [
      await sapienToken.getAddress(),
      await sapienSigner.getAddress()
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

      await expect(sapienStaking.connect(user).stake(
        amount,
        lockUpPeriod,
        ethers.id(orderId),
        signature
      )).to.emit(sapienStaking, "Staked")
        .withArgs(await user.getAddress(), amount, BigInt(10500), lockUpPeriod, ethers.id(orderId));

      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(orderId));
      expect(stakerInfo.amount).to.equal(amount);
      expect(stakerInfo.isActive).to.be.true;
    });

    it("Should allow staking with amount less than base stake and calculate correct multiplier", async function () {
      const amount = BASE_STAKE / BigInt(2);
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "order2";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);

      await sapienStaking.connect(user).stake(
        amount, 
        lockUpPeriod, 
        ethers.id(orderId),
        signature
      );
      
      const stakingInfo = await sapienStaking.stakers(await user.getAddress(), ethers.id(orderId));
      expect(stakingInfo.multiplier).to.equal(10250);
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
      
      // Fund the staking contract with additional tokens to cover multiplier bonuses
      // For 30-day stake, multiplier is 10500 (105%), so we need at least 5% extra tokens
      const bonusTokens = (stakedAmount * BigInt(500)) / BigInt(10000); // 5% of stake
      await sapienToken.mint(await sapienStaking.getAddress(), bonusTokens);
      
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
      const stakeAmount = BASE_STAKE;
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
      
      // Verify user received tokens with multiplier applied
      const expectedTransferAmount = (partialAmount * cooldownStakeInfo.multiplier) / BigInt(10000);
      const balanceAfter = await sapienToken.balanceOf(await user.getAddress());
      expect(balanceAfter - balanceBefore).to.equal(expectedTransferAmount);
      
      // Verify contract's total staked amount was reduced correctly
      expect(await sapienStaking.totalStaked()).to.equal(initialTotalStaked + stakeAmount - partialAmount);
    });
  });

  describe("Instant Unstake", function () {
    it("Should allow instant unstake with penalty", async function () {
      const stakeAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "stake2";
      const instantUnstakeOrderId = "instant_unstake2";
      
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
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
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
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
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
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });
  });
}); 