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
        { name: "orderId", type: "string" },
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
      orderId: orderId,
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
        orderId,
        signature
      )).to.emit(sapienStaking, "Staked")
        .withArgs(await user.getAddress(), amount, BigInt(105), lockUpPeriod, orderId);

      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), orderId);
      expect(stakerInfo.amount).to.equal(amount);
      expect(stakerInfo.isActive).to.be.true;
    });

    it("Should reject staking with invalid amount", async function () {
      const amount = BASE_STAKE / BigInt(2);
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const orderId = "order2";
      const signature = await signStakeMessage(await user.getAddress(), amount, orderId, 0);

      await expect(
        sapienStaking.connect(user).stake(amount, lockUpPeriod, orderId, signature)
      ).to.be.revertedWith("Amount must be greater than base stake");
    });
  });

  describe("Unstaking", function () {
    const stakeOrderId = "stake1";
    const initiateUnstakeOrderId = "unstake1_init";
    const unstakeOrderId = "unstake1_complete";
    let stakedAmount: bigint;
    
    beforeEach(async function () {
      // Setup a stake first
      stakedAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const signature = await signStakeMessage(await user.getAddress(), stakedAmount, stakeOrderId, 0);
      await sapienStaking.connect(user).stake(stakedAmount, lockUpPeriod, stakeOrderId, signature);
      
      // Verify the stake was created correctly
      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), stakeOrderId);
      expect(stakerInfo.isActive).to.be.true;
      expect(stakerInfo.amount).to.equal(stakedAmount);
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
          initiateUnstakeOrderId,
          stakeOrderId,
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
        initiateUnstakeOrderId,
        stakeOrderId,
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
          unstakeOrderId,
          stakeOrderId,
          unstakeSignature
        )
      ).to.emit(sapienStaking, "Unstaked");
    });
  });

  describe("Instant Unstake", function () {
    it("Should allow instant unstake with penalty", async function () {
      const stakeAmount = BASE_STAKE;
      const lockUpPeriod = BigInt(30) * ONE_DAY;
      const stakeOrderId = "stake2";
      const instantUnstakeOrderId = "instant_unstake2";
      
      // Setup initial stake
      const stakeSignature = await signStakeMessage(await user.getAddress(), stakeAmount, stakeOrderId, 0);
      await sapienStaking.connect(user).stake(stakeAmount, lockUpPeriod, stakeOrderId, stakeSignature);
      
      // Verify stake is active
      const stakerInfo = await sapienStaking.stakers(await user.getAddress(), stakeOrderId);
      expect(stakerInfo.isActive).to.be.true;

      // Perform instant unstake
      const unstakeSignature = await signStakeMessage(await user.getAddress(), stakeAmount, instantUnstakeOrderId, 3);
      const expectedPayout = (stakeAmount * BigInt(80)) / BigInt(100);
      
      await expect(
        sapienStaking.connect(user).instantUnstake(
          stakeAmount,
          instantUnstakeOrderId,
          stakeOrderId,
          unstakeSignature
        )
      ).to.emit(sapienStaking, "InstantUnstake")
        .withArgs(await user.getAddress(), expectedPayout, stakeOrderId);
    });
  });
}); 