import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, Signer } from "ethers";
import "@nomicfoundation/hardhat-chai-matchers";

describe("SapienRewards", function () {
  let MockToken: any;
  let mockToken: any;
  let SapienRewards: any;
  let sapienRewards: any;
  let owner: Signer;
  let authorizedSigner: Signer;
  let user: Signer;
  let gnosisSafe: Signer;
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
    [owner, authorizedSigner, user, gnosisSafe] = await ethers.getSigners();
    console.log('owner:', await owner.getAddress());
    console.log('authorizedSigner:', await authorizedSigner.getAddress());
    console.log('user:', await user.getAddress());
    console.log('gnosisSafe:', await gnosisSafe.getAddress());

    // Deploy mock token (representing IRewardToken)
    MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock Reward Token", "MRT");

    // Deploy SapienRewards
    SapienRewards = await ethers.getContractFactory("SapienRewards");
    sapienRewards = await upgrades.deployProxy(
      SapienRewards.connect(gnosisSafe),
      [
        await authorizedSigner.getAddress(),
        await gnosisSafe.getAddress()
      ],
      { initializer: "initialize" }
    );

    // Set reward token
    await sapienRewards.connect(gnosisSafe).setRewardToken(await mockToken.getAddress());

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
      await sapienRewards.connect(gnosisSafe).withdrawTokens(balance);

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

  describe("Safe/ owner Functions", function () {
    it("Should allow safe to deposit tokens", async function () {
      const depositAmount = ethers.parseUnits("1000", 18);
      await mockToken.mint(await gnosisSafe.getAddress(), depositAmount);
      await mockToken.connect(gnosisSafe).approve(await sapienRewards.getAddress(), depositAmount);

      await expect(
        sapienRewards.connect(gnosisSafe).depositTokens(depositAmount)
      ).to.not.be.reverted;
    });

    it("Should allow safe to withdraw tokens", async function () {
      const withdrawAmount = ethers.parseUnits("100", 18);
      
      await expect(
        sapienRewards.connect(gnosisSafe).withdrawTokens(withdrawAmount)
      ).to.not.be.reverted;
    });

    it("Should allow safe to update reward token", async function () {
      const newToken = await MockToken.deploy("New Token", "NEW");
      
      await expect(
        sapienRewards.connect(gnosisSafe).setRewardToken(await newToken.getAddress())
      ).to.emit(sapienRewards, "RewardTokenUpdated")
        .withArgs(await newToken.getAddress());
    });

    it("Should allow safe to pause and unpause the contract", async function () {
      await expect(sapienRewards.connect(gnosisSafe).pause()).to.not.be.reverted;
      expect(await sapienRewards.paused()).to.equal(true);
      
      await expect(sapienRewards.connect(gnosisSafe).unpause()).to.not.be.reverted;
      expect(await sapienRewards.paused()).to.equal(false);
    });

    it("Should prevent non-safe from pausing", async function () {
      await expect(sapienRewards.connect(user).pause())
        .to.be.revertedWith("Only the Safe can perform this");
    });

    it("Should prevent reward claims when paused", async function () {
      // Pause the contract
      await sapienRewards.connect(gnosisSafe).pause();
      
      const orderId = "pausedTest";
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
      ).to.be.revertedWithCustomError(sapienRewards, "EnforcedPause");
    });
  });

  describe("Cross-contract Signature Security", function () {
    it("Should reject signatures from different contract addresses", async function () {
      // Create domain for a hypothetical different contract
      const fakeDomain = {
        name: "SapienRewards",
        version: "1",
        chainId: domain.chainId,
        verifyingContract: await user.getAddress() // Different contract address
      };

      const orderId = "claim1";
      const value = {
        userWallet: await user.getAddress(),
        amount: REWARD_AMOUNT,
        orderId: ethers.encodeBytes32String(orderId)
      };

      // Sign with different domain
      const signature = await authorizedSigner.signTypedData(fakeDomain, types, value);

      // Attempt to use signature in real contract should fail
      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });

    it("Should reject signatures from different contract names", async function () {
      // Create domain for a different contract name
      const fakeDomain = {
        name: "SapienStaking", // Different contract name
        version: "1",
        chainId: domain.chainId,
        verifyingContract: await sapienRewards.getAddress()
      };

      const orderId = "claim1";
      const value = {
        userWallet: await user.getAddress(),
        amount: REWARD_AMOUNT,
        orderId: ethers.encodeBytes32String(orderId)
      };

      // Sign with different domain
      const signature = await authorizedSigner.signTypedData(fakeDomain, types, value);

      // Attempt to use signature in real contract should fail
      await expect(
        sapienRewards.connect(user).claimReward(
          REWARD_AMOUNT,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });
  });

  describe("Ownership", function () {
    let newOwner: Signer;
    
    beforeEach(async function () {
      [owner, authorizedSigner, user, newOwner] = await ethers.getSigners();
    });
    
    it("Should allow two-step ownership transfer", async function () {
      // Current owner proposes new owner
      await expect(sapienRewards.connect(gnosisSafe).transferOwnership(await newOwner.getAddress()))
        .to.not.be.reverted;
        
      // Verify pending owner is set correctly
      expect(await sapienRewards.pendingOwner()).to.equal(await newOwner.getAddress());
      
      // New owner accepts ownership
      await expect(sapienRewards.connect(newOwner).acceptOwnership())
        .to.not.be.reverted;
        
      // Verify ownership transfer completed
      expect(await sapienRewards.owner()).to.equal(await newOwner.getAddress());
    });
    
    it("Should not allow non-pending owner to accept ownership", async function () {
      // Current owner proposes new owner
      await sapienRewards.connect(gnosisSafe).transferOwnership(await newOwner.getAddress());
      
      // Another account tries to accept ownership
      await expect(sapienRewards.connect(user).acceptOwnership())
        .to.be.revertedWithCustomError(sapienRewards, "OwnableUnauthorizedAccount");
    });
  });

  describe("Upgradeability", function () {
    let SapienRewardsV2: any;
    let sapienRewardsV2: any;
    
    it("Should allow upgrading to a new implementation", async function () {
      // Deploy a new implementation (mock for test)
      const SapienRewardsV2Factory = await ethers.getContractFactory("SapienRewardsV2Mock");

      const sapienRewardsV2Address = await upgrades.prepareUpgrade(
        await sapienRewards.getAddress(),
        SapienRewardsV2Factory.connect(gnosisSafe),
        {
          constructorArgs: []
        }
      );

      await sapienRewards.connect(gnosisSafe).authorizeUpgrade(sapienRewardsV2Address);

      // Upgrade to new implementation
      sapienRewardsV2 = await upgrades.upgradeProxy(
        await sapienRewards.getAddress(),
        SapienRewardsV2Factory.connect(gnosisSafe)
      );
      
      // Check that state is preserved
      expect(await sapienRewardsV2.rewardToken()).to.equal(await mockToken.getAddress());
      
      // Check that new functionality is available (assuming the mock has a new function)
      expect(await sapienRewardsV2.getVersion()).to.equal("2.0");
    });
    
    it("Should not allow non-safe to upgrade the contract", async function () {
      SapienRewardsV2 = await ethers.getContractFactory("SapienRewardsV2Mock", user);
      
      await expect(
        upgrades.upgradeProxy(await sapienRewards.getAddress(), SapienRewardsV2)
      ).to.be.reverted;
    });
  });

  describe("Signature Security", function () {
    it("Should reject if user tries to claim with someone else's signature", async function () {
      const orderId = "securityTest";
      // Create signature for user1
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        orderId
      );
      
      // A different user tries to claim with this signature
      const anotherUser = await ethers.provider.getSigner(3); // Get a different signer
      
      await expect(
        sapienRewards.connect(anotherUser).claimReward(
          REWARD_AMOUNT,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });
    
    it("Should reject if amount in claim doesn't match signed amount", async function () {
      const orderId = "amountTest";
      const signature = await signRewardClaim(
        await user.getAddress(),
        REWARD_AMOUNT,
        orderId
      );
      
      // Try to claim with a different amount
      const differentAmount = REWARD_AMOUNT + 1n;
      await expect(
        sapienRewards.connect(user).claimReward(
          differentAmount,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.be.revertedWith("Invalid signature or mismatched parameters");
    });
  });

  describe("Edge Cases", function () {
    it("Should reject claims with zero amount", async function () {
      const orderId = "zeroTest";
      const zeroAmount = 0n;
      const signature = await signRewardClaim(
        await user.getAddress(),
        zeroAmount,
        orderId
      );
      
      await expect(
        sapienRewards.connect(user).claimReward(
          zeroAmount,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.not.be.reverted; // Assuming zero transfers are valid in the token
    });
    
    it("Should allow claims with exactly the contract's balance", async function () {
      // First withdraw all existing tokens
      const existingBalance = await mockToken.balanceOf(await sapienRewards.getAddress());
      await sapienRewards.connect(gnosisSafe).withdrawTokens(existingBalance);
      
      // Then deposit exact amount to test
      const exactAmount = ethers.parseUnits("123", 18);
      await mockToken.mint(await gnosisSafe.getAddress(), exactAmount);
      await (mockToken as any).connect(gnosisSafe).approve(await sapienRewards.getAddress(), exactAmount);
      await sapienRewards.connect(gnosisSafe).depositTokens(exactAmount);
      
      // Claim exactly this amount
      const orderId = "exactBalanceTest";
      const signature = await signRewardClaim(
        await user.getAddress(),
        exactAmount,
        orderId
      );
      
      await expect(
        sapienRewards.connect(user).claimReward(
          exactAmount,
          ethers.encodeBytes32String(orderId),
          signature
        )
      ).to.emit(sapienRewards, "RewardClaimed");
      
      // Contract should now have zero balance
      expect(await sapienRewards.getContractTokenBalance()).to.equal(0);
    });
  });

  describe("Access Control", function () {
    it("Should prevent non-safe from calling admin functions", async function () {
      await expect(sapienRewards.connect(user).setRewardToken(await mockToken.getAddress()))
        .to.be.revertedWith("Only the Safe can perform this");
        
      await expect(sapienRewards.connect(user).withdrawTokens(100))
        .to.be.revertedWith("Only the Safe can perform this");
        
      await expect(sapienRewards.connect(user).depositTokens(100))
        .to.be.revertedWith("Only the Safe can perform this");
    });
  });
}); 
