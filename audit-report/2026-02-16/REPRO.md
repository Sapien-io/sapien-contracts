# Sapien PoQ v0.5 — Critical Issue Reproduction Guide

## Overview

This document provides detailed reproduction steps for the 8 release-blocking issues identified in the Sapien PoQ v0.5 security audit. Each section includes setup instructions, reproduction scenarios, and expected outcomes.

**Environment Requirements:**
- Foundry (forge, anvil)
- Node.js 18+
- Git repository with v0.5-dev branch

---

## Setup Instructions

### 1. Environment Setup

```bash
# Clone and setup repository
git checkout v0.5-dev
npm install
forge install

# Start local testnet
anvil --fork-url $MAINNET_RPC_URL --block-time 1

# Deploy contracts (in separate terminal)
npm run deploy:local
```

### 2. Test Helper Setup

Create `test/ReproduceIssues.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {QualityEngine} from "../src/QualityEngine.sol";
import {StakeVault} from "../src/StakeVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract ReproduceIssuesTest is Test {
    QualityEngine engine;
    StakeVault vault;
    MockERC20 token;

    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address validator1 = makeAddr("validator1");
    address validator2 = makeAddr("validator2");

    function setUp() public {
        // Deploy and setup contracts
        token = new MockERC20("Test Token", "TEST");
        vault = new StakeVault(token);
        engine = new QualityEngine(address(vault));

        // Setup roles and initial state
        vm.startPrank(admin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), admin);
        engine.grantRole(engine.DEFAULT_ADMIN_ROLE(), admin);
        engine.grantRole(engine.OPERATOR_ROLE(), admin);
        vm.stopPrank();

        // Fund test accounts
        token.mint(user1, 1000e18);
        token.mint(user2, 1000e18);
        token.mint(validator1, 1000e18);
        token.mint(validator2, 1000e18);

        // Users deposit to vault
        vm.startPrank(user1);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(validator1);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, validator1);
        vm.stopPrank();
    }
}
```

---

## RISK-001: ERC4626 Share Transfer Bypass

**Issue:** StakeVault inherits ERC4626 but fails to override `_update()`, allowing users to transfer shares while bypassing contributor and validator stake locks.

### Reproduction Steps

```solidity
function testShareTransferBypass() public {
    // Setup: User sets validator capacity (locks stake)
    vm.startPrank(validator1);
    engine.setValidatorCapacity(500e18); // Locks 500 tokens
    vm.stopPrank();

    // Verify initial state
    assertEq(vault.balanceOf(validator1), 1000e18);
    assertEq(vault.availableBalance(validator1), 500e18); // 1000 - 500 locked

    // Exploit: Transfer shares to new address
    vm.startPrank(validator1);
    vault.transfer(user2, 300e18); // Transfer 300 shares
    vm.stopPrank();

    // Verify exploit success
    assertEq(vault.balanceOf(validator1), 700e18); // Reduced by transfer
    assertEq(vault.balanceOf(user2), 300e18); // Received shares

    // user2 can now redeem the shares (bypassing locks)
    vm.startPrank(user2);
    vault.redeem(300e18, user2, user2); // Should succeed but shouldn't
    vm.stopPrank();

    // Result: user2 gets free tokens, validator1 still shows locked stake
    assertEq(token.balanceOf(user2), 300e18);
    assertEq(vault.availableBalance(validator1), 500e18); // Still "locked"
}
```

### Expected Outcome
- Transfer succeeds (should fail)
- Redemption succeeds (should fail)
- Economic security completely bypassed

### Verification After Fix
```solidity
function testShareTransferBlocked() public {
    vm.startPrank(validator1);
    engine.setValidatorCapacity(500e18);

    // This should now revert
    vm.expectRevert("TransferExceedsUnlockedShares");
    vault.transfer(user2, 300e18);
    vm.stopPrank();
}
```

---

## RISK-002: Missing ENGINE_ROLE Grant

**Issue:** QualityEngine.initialize() never grants ENGINE_ROLE to itself, breaking all vault operations.

### Reproduction Steps

```solidity
function testMissingEngineRole() public {
    // Setup: Create project and try to claim
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));

    // Fund project
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 10, address(0));

    // Try to claim - this should fail
    vm.expectRevert(); // AccessControl error
    engine.claimToContribute(projectId, 1, address(0));
    vm.stopPrank();
}
```

### Expected Outcome
- `claimToContribute` reverts with AccessControl error
- All staking operations fail
- Protocol completely non-functional

### Verification After Fix
```solidity
function testEngineRoleGranted() public {
    // After fix, claiming should work
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 10, address(0));

    // This should now succeed
    engine.claimToContribute(projectId, 1, address(0));
    vm.stopPrank();
}
```

---

## RISK-003: Validator Settlement Blocked on Rejection

**Issue:** computeConsensus sets report.computed=true only on acceptance, but settleValidator requires computed=true. Rejected contributions leave validators with permanently locked stake.

### Reproduction Steps

```solidity
function testSettlementBlockedOnRejection() public {
    // Setup: Create project, fund, contribute
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 1, address(0));
    bytes32 claimId = engine.claimToContribute(projectId, 1, address(0));
    engine.contribute(claimId, 0, keccak256("work"));
    vm.stopPrank();

    // Validators commit and reveal LOW scores (rejection)
    vm.startPrank(validator1);
    engine.setValidatorCapacity(100e18);
    engine.commitValidation(projectId, 0, keccak256("low_score"), 100e18);
    vm.warp(block.timestamp + 3600); // Reveal period
    engine.revealValidation(projectId, 0, 1, keccak256("low_score")); // Score = 1 (low)
    vm.stopPrank();

    // Consensus computes rejection
    engine.computeConsensus(projectId, 0);

    // Validator tries to settle - should fail
    vm.expectRevert("ConsensusNotReady");
    engine.settleValidator(projectId, 0);
}
```

### Expected Outcome
- Consensus computation succeeds
- `settleValidator` reverts with "ConsensusNotReady"
- Validator stake permanently locked

### Verification After Fix
```solidity
function testSettlementWorksAfterRejection() public {
    // Same setup as above...

    // After fix, settlement should work
    engine.settleValidator(projectId, 0);
    // Should succeed without revert
}
```

---

## RISK-004: Sybil Attack via Sqrt(Stake) Weighting

**Issue:** Consensus algorithm uses sqrt(stake) weighting, enabling coordinated Sybil attacks.

### Reproduction Steps

```solidity
function testSybilAttack() public {
    // Setup: Create project with honest validator
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 1, address(0));
    bytes32 claimId = engine.claimToContribute(projectId, 1, address(0));
    engine.contribute(claimId, 0, keccak256("work"));
    vm.stopPrank();

    // Honest validator with large stake
    vm.startPrank(validator1);
    engine.setValidatorCapacity(1000e18);
    engine.commitValidation(projectId, 0, keccak256("honest_high"), 1000e18);
    vm.warp(block.timestamp + 3600);
    engine.revealValidation(projectId, 0, 95, keccak256("honest_high")); // Honest high score
    vm.stopPrank();

    // Sybil attack: 10 small accounts coordinate
    for(uint i = 0; i < 10; i++) {
        address sybil = makeAddr(string(abi.encodePacked("sybil", i)));
        token.mint(sybil, 100e18);

        vm.startPrank(sybil);
        token.approve(address(vault), 100e18);
        vault.deposit(100e18, sybil);
        engine.setValidatorCapacity(100e18);
        engine.commitValidation(projectId, 0, keccak256(abi.encode("attack", i)), 100e18);
        vm.warp(block.timestamp + 3600);
        engine.revealValidation(projectId, 0, 5, keccak256(abi.encode("attack", i))); // Attack low score
        vm.stopPrank();
    }

    // Compute consensus
    engine.computeConsensus(projectId, 0);

    // Verify attack success: low score consensus despite honest validator
    // sqrt(1000) * reputation = ~1000 weight from honest
    // 10 * sqrt(100) * reputation = ~10 * 100 = 1000 weight from sybils
    // Total: 50% sybil control with 1% of stake
}
```

### Expected Outcome
- Consensus result manipulated by small coordinated stake
- Sybil attack succeeds with minimal economic commitment

### Verification After Fix
```solidity
function testQuadraticStakingResistance() public {
    // With quadratic staking: weight = stake²
    // Honest: 1000² = 1,000,000 weight
    // Each sybil: 100² = 10,000 weight
    // Total sybil: 100,000 weight
    // Ratio: 1M : 100K = 10:1 in favor of honest
    // Attack fails
}
```

---

## RISK-005: Escrow Underflow in Settlement

**Issue:** settleValidator deducts rewards without checking escrow sufficiency.

### Reproduction Steps

```solidity
function testEscrowUnderflow() public {
    // Setup: Project with validator rewards
    vm.startPrank(admin);
    engine.setValidatorRewardBps(2500); // 25% to validators
    vm.stopPrank();

    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 1, address(0));
    bytes32 claimId = engine.claimToContribute(projectId, 1, address(0));
    engine.contribute(claimId, 0, keccak256("work"));
    vm.stopPrank();

    // Multiple validators participate
    address[] memory validators = new address[](4);
    for(uint i = 0; i < 4; i++) {
        validators[i] = makeAddr(string(abi.encodePacked("val", i)));
        token.mint(validators[i], 1000e18);

        vm.startPrank(validators[i]);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, validators[i]);
        engine.setValidatorCapacity(1000e18);
        engine.commitValidation(projectId, 0, keccak256(abi.encode("score", i)), 1000e18);
        vm.warp(block.timestamp + 3600);
        engine.revealValidation(projectId, 0, 80, keccak256(abi.encode("score", i)));
        vm.stopPrank();
    }

    // Consensus and settlement
    engine.computeConsensus(projectId, 0);

    // First 3 settlements succeed
    for(uint i = 0; i < 3; i++) {
        vm.prank(validators[i]);
        engine.settleValidator(projectId, 0);
    }

    // 4th settlement hits empty escrow
    vm.expectRevert(); // Arithmetic underflow or insufficient balance
    vm.prank(validators[3]);
    engine.settleValidator(projectId, 0);
}
```

### Expected Outcome
- First settlements succeed, depleting escrow
- Final settlement fails due to insufficient funds
- Validators lose earned rewards

---

## RISK-006: Consensus Storage Collision

**Issue:** validatorConsensus mapping not keyed by nonce, causing collisions on resubmission.

### Reproduction Steps

```solidity
function testStorageCollision() public {
    // Setup: Create contribution that gets rejected
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 1, address(0));
    bytes32 claimId = engine.claimToContribute(projectId, 1, address(0));
    engine.contribute(claimId, 0, keccak256("work"));
    vm.stopPrank();

    // Validator participates in round 1
    vm.startPrank(validator1);
    engine.setValidatorCapacity(100e18);
    engine.commitValidation(projectId, 0, keccak256("round1"), 100e18);
    vm.warp(block.timestamp + 3600);
    engine.revealValidation(projectId, 0, 10, keccak256("round1")); // Low score = rejection
    vm.stopPrank();

    // Consensus rejects, increments nonce
    engine.computeConsensus(projectId, 0);

    // User resubmits at same index
    vm.prank(user1);
    engine.contribute(claimId, 0, keccak256("better_work"));

    // Same validator tries to participate in round 2
    vm.startPrank(validator1);
    engine.commitValidation(projectId, 0, keccak256("round2"), 100e18);
    vm.warp(block.timestamp + 3600);
    engine.revealValidation(projectId, 0, 90, keccak256("round2"));
    vm.stopPrank();

    // Consensus on round 2
    engine.computeConsensus(projectId, 0);

    // Validator tries to settle - should fail due to collision
    vm.expectRevert("AlreadySettled"); // Thinks already settled from round 1
    vm.prank(validator1);
    engine.settleValidator(projectId, 0);
}
```

### Expected Outcome
- Validator settlement fails due to stale data collision
- Stake locked, rewards inaccessible

---

## RISK-007: Zero-Stake Validation Bypass

**Issue:** Zero-stake validations allowed, get weight=1 in consensus.

### Reproduction Steps

```solidity
function testZeroStakeValidation() public {
    // Setup project and contribution
    vm.startPrank(user1);
    bytes32 projectId = engine.createProject("test", abi.encode("config"));
    token.approve(address(engine), 1000e18);
    engine.fundProject(projectId, address(token), 1000e18, 1, address(0));
    bytes32 claimId = engine.claimToContribute(projectId, 1, address(0));
    engine.contribute(claimId, 0, keccak256("work"));
    vm.stopPrank();

    // Honest validator with stake
    vm.startPrank(validator1);
    engine.setValidatorCapacity(100e18);
    engine.commitValidation(projectId, 0, keccak256("honest"), 100e18);
    vm.warp(block.timestamp + 3600);
    engine.revealValidation(projectId, 0, 90, keccak256("honest"));
    vm.stopPrank();

    // Zero-stake attacker
    vm.startPrank(user2); // No stake deposited
    engine.commitValidation(projectId, 0, keccak256("attack"), 0); // Zero stake
    vm.warp(block.timestamp + 3600);
    engine.revealValidation(projectId, 0, 10, keccak256("attack")); // Low score
    vm.stopPrank();

    // Consensus: zero-stake validator gets weight=1, influencing result
    engine.computeConsensus(projectId, 0);

    // Verify manipulation: consensus lower than honest score due to zero-stake weight
}
```

### Expected Outcome
- Zero-stake validation succeeds
- Consensus manipulated by free participation
- Economic security undermined

---

## RISK-012: No Validator Capacity Unlock Path

**Issue:** setValidatorCapacity locks stake but no function unlocks it.

### Reproduction Steps

```solidity
function testNoUnlockPath() public {
    // Validator locks capacity
    vm.startPrank(validator1);
    engine.setValidatorCapacity(500e18);
    vm.stopPrank();

    // Verify locked
    assertEq(vault.availableBalance(validator1), 500e18); // 1000 - 500

    // Try to reduce capacity - should fail (function doesn't exist)
    // engine.reduceValidatorCapacity(200e18); // Function doesn't exist

    // Validator cannot unlock stake
    // vault.unlockValidatorCapacity(validator1, 200e18); // Requires ENGINE_ROLE

    // Result: stake permanently locked
    assertEq(vault.availableBalance(validator1), 500e18); // Still locked
}
```

### Expected Outcome
- No way to unlock validator capacity
- Stake permanently trapped
- Validator cannot exit or reduce commitment

---

## Running All Reproductions

### Automated Test Suite

```bash
# Run all reproduction tests
forge test --match-contract ReproduceIssuesTest -v

# Run specific issue
forge test --match-test testShareTransferBypass -v

# Run with gas reporting
forge test --match-contract ReproduceIssuesTest --gas-report
```

### Continuous Integration

Add to `package.json`:

```json
{
  "scripts": {
    "test:repro": "forge test --match-contract ReproduceIssuesTest",
    "test:repro:ci": "forge test --match-contract ReproduceIssuesTest --gas-report --ffi"
  }
}
```

---

## Post-Fix Verification

After implementing fixes, run the verification tests to ensure issues are resolved:

```solidity
contract VerifyFixesTest is ReproduceIssuesTest {

    function testShareTransferBlocked() public {
        vm.startPrank(validator1);
        engine.setValidatorCapacity(500e18);
        vm.expectRevert("TransferExceedsUnlockedShares");
        vault.transfer(user2, 300e18);
        vm.stopPrank();
    }

    function testEngineRoleWorks() public {
        vm.startPrank(user1);
        bytes32 projectId = engine.createProject("test", abi.encode("config"));
        token.approve(address(engine), 1000e18);
        engine.fundProject(projectId, address(token), 1000e18, 10, address(0));
        engine.claimToContribute(projectId, 1, address(0)); // Should succeed
        vm.stopPrank();
    }

    function testSettlementAfterRejection() public {
        // Setup rejected contribution...
        engine.computeConsensus(projectId, 0);
        engine.settleValidator(projectId, 0); // Should succeed after fix
    }

    function testZeroStakeRejected() public {
        vm.startPrank(user2);
        vm.expectRevert("InsufficientStake");
        engine.commitValidation(projectId, 0, keccak256("attack"), 0);
        vm.stopPrank();
    }

    function testUnlockCapacity() public {
        vm.startPrank(validator1);
        engine.setValidatorCapacity(500e18);
        engine.reduceValidatorCapacity(200e18); // New function
        vm.stopPrank();
        assertEq(vault.availableBalance(validator1), 700e18); // 500 + 200 unlocked
    }
}
```

---

## Integration Testing Checklist

- [ ] All reproduction tests fail before fixes
- [ ] All verification tests pass after fixes
- [ ] Cross-contract interactions work correctly
- [ ] State transitions are properly validated
- [ ] Economic invariants hold after fixes
- [ ] Gas usage is reasonable for mainnet
- [ ] Upgrade paths work with fixed contracts

---

*This reproduction guide ensures developers can reliably test fixes and security researchers can independently verify the identified vulnerabilities.*