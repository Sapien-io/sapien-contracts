import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, Signer } from "ethers";
import "@nomicfoundation/hardhat-chai-matchers";

describe("SapienRewards", function () {
  let MockToken: any;
  let mockToken: Contract;
  let SapienRewards: any;
  let sapienRewards: any;
  let owner: Signer;
  let authorizedSigner: Signer;
  let user: Signer;
  let domain: {
    name: string;
    version: string;
    chainId: bigint;
    verifyingContract: string;
  };
  let types: {
    RewardClaim: Array<{ name: string; type: string }>;
  };

  const REWARD_AMOUNT = ethers.parseUnits("100", 18);

  beforeEach(async function () {
    [owner, authorizedSigner, user] = await ethers.getSigners();

    // Deploy mock token (representing IRewardToken)
    MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock Reward Token", "MRT");

    // Deploy SapienRewards
    SapienRewards = await ethers.getContractFactory("SapienRewards");
    sapienRewards = await upgrades.deployProxy(SapienRewards, [
      await authorizedSigner.getAddress()
    ]);

    // Set reward token
    await sapienRewards.setRewardToken(await mockToken.getAddress());

    // Fund the rewards contract
    await mockToken.mint(await sapienRewards.getAddress(), ethers.parseUnits("1000000", 18));

    // Setup EIP-712 domain and types
    domain = {
      name: "SapienRewards",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await sapienRewards.getAddress()
    };

    types = {
      RewardClaim: [
        { name: "userWallet", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "orderId", type: "bytes32" }
      ]
    };
  });

  async function signRewardClaim(
    wallet: string,
    amount: bigint,
    orderId: string
  ): Promise<string> {
    const value = {
      userWallet: wallet,
      amount: amount,
      orderId: ethers.encodeBytes32String(orderId)
    };

    return await authorizedSigner.signTypedData(domain, types, value);
  }

  describe("Initialization", function () {
    it("Should set the correct authorized signer", async function () {
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        "test1"
      );
      
      // Try to claim reward - if it doesn't revert with signature error, signer is correct
      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT, 
          ethers.encodeBytes32String("test1"),
          signature
        )
      ).to.not.be.revertedWith("Invalid signature or mismatched parameters");
    });

    it("Should set the reward token correctly", async function () {
      expect(await sapienRewards.rewardToken()).to.equal(await mockToken.getAddress());
    });
  });

  describe("Reward Claims", function () {
    it("Should allow claiming rewards with valid signature", async function () {
      const orderId = "claim1";
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        orderId
      );

      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT, 
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.emit(sapienRewards, "RewardClaimed")
        .withArgs(await user.getAddress(), REWARD_AMOUNT, ethers.encodeBytes32String(orderId));
    });

    it("Should prevent duplicate claims", async function () {
      const orderId = "claim2";
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        orderId
      );

      await sapienRewards.connect(user).claimReward(
        REWARD_AMOUNT, 
        ethers.encodeBytes32String(orderId),
        signature
      );

      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT, 
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Order ID already used");
    });

    it("Should fail with invalid signature", async function () {
      const orderId = "claim3";
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        "different-order-id"
      );

      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT, 
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });

    it("Should fail if contract has insufficient balance", async function () {
      // Withdraw all tokens from contract first
      const balance = await mockToken.balanceOf(await sapienRewards.getAddress());
      await sapienRewards.connect(owner).withdrawTokens(balance);

      const orderId = "claim4";
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        orderId
      );

      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT, 
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Insufficient token balance");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to deposit tokens", async function () {
      const depositAmount = ethers.parseUnits("1000", 18);
      await mockToken.mint(await owner.getAddress(), depositAmount);
      await mockToken.approve(await sapienRewards.getAddress(), depositAmount);

      await expect(
        sapienRewards.depositTokens(depositAmount)
      ).to.not.be.reverted;
    });

    it("Should allow owner to withdraw tokens", async function () {
      const withdrawAmount = ethers.parseUnits("100", 18);
      
      await expect(
        sapienRewards.withdrawTokens(withdrawAmount)
      ).to.not.be.reverted;
    });

    it("Should allow owner to update reward token", async function () {
      const newToken = await MockToken.deploy("New Token", "NEW");
      
      await expect(
        sapienRewards.setRewardToken(await newToken.getAddress())
      ).to.emit(sapienRewards, "RewardTokenUpdated")
        .withArgs(await newToken.getAddress());
    });
  });
}); 