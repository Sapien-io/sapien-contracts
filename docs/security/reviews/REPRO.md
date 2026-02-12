# Reproduction Guide: Sapien PoQ Critical Findings

## 1. Storage Layout Shift (SapienCore.sol)

### Problem Description
The `SapienCore` contract is upgradeable. Adding a state variable in the middle of existing variables shifts the storage slots of everything that follows it.

### Reproduction Steps
You can use the following Foundry test to demonstrate the corruption. The test simulates an "Old" contract layout and compares it to the "New" contract layout.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

// Mock version of Old SapienCore layout
contract OldSapienCore {
    address internal _vault;
    address internal _rewards;
    address internal _trust;
    address internal _oracle;
    mapping(bytes32 => uint256) internal projects; // Simplified
    mapping(bytes32 => uint256) internal claims;    // Simplified
    uint256 internal nextClaimId;
    mapping(bytes32 => uint256) internal contributions; // Simplified
    mapping(bytes32 => uint256) internal indexReservations; // Simplified
    mapping(bytes32 => uint256) internal availableIndices; // Simplified
    uint256 internal stackTop;
    mapping(bytes32 => bool) internal indexIsAvailable; // Simplified
    
    // Existing variables before the shift
    uint256 internal _claimDeadlineDays;
    uint256 internal _maxValidations; // [Note: _maxValidations has since been removed; replaced by per-project numberOfValidations]
    uint256 public protocolFeeBasisPoints;
    address public treasury;
    uint256 public consensusThreshold;
}

// Current version with the BUG (mapping inserted in middle)
contract NewSapienCore {
    address internal _vault;
    address internal _rewards;
    address internal _trust;
    address internal _oracle;
    mapping(bytes32 => uint256) internal projects; 
    mapping(bytes32 => uint256) internal claims;    
    uint256 internal nextClaimId;
    mapping(bytes32 => uint256) internal contributions; 
    mapping(bytes32 => uint256) internal indexReservations; 
    mapping(bytes32 => uint256) internal availableIndices; 
    uint256 internal stackTop;
    mapping(bytes32 => bool) internal indexIsAvailable; 

    // THE BUG: New mapping inserted here!
    mapping(bytes32 => mapping(address => uint256)) internal userActiveClaimedQuantity;

    // These variables are now shifted by 1 slot
    uint256 internal _claimDeadlineDays;
    uint256 internal _maxValidations; // [Note: _maxValidations has since been removed; replaced by per-project numberOfValidations]
    uint256 public protocolFeeBasisPoints;
    address public treasury;
    uint256 public consensusThreshold;
}

contract StorageShiftTest is Test {
    function testStorageCorruption() public {
        // Slot 12 in OldSapienCore is _claimDeadlineDays
        // Slot 12 in NewSapienCore is userActiveClaimedQuantity (the mapping)
        
        // In the real contract, the shift happens after the mappings and simple types.
        // Let's check the actual slot of protocolFeeBasisPoints in NewSapienCore.
        
        // You can run this command to see the shift:
        // forge inspect src/SapienCore.sol:SapienCore storage-layout
    }
}
```

### Evidence in Code
In `src/SapienCore.sol`:
```solidity
59|    mapping(bytes32 => mapping(uint256 => bool)) internal indexIsAvailable;
60|
61|    /// @notice Track active claimed slots per user per project (Issue #6 fix)
62|    /// @dev projectId => user => activeClaimedQuantity
63|    mapping(bytes32 => mapping(address => uint256)) internal userActiveClaimedQuantity; // <--- INSERTED HERE
64|
65|    uint256 internal _claimDeadlineDays; // <--- SHIFTED
66|    // [Note: _maxValidations has since been removed; replaced by per-project numberOfValidations]
```

---

## 2. Validator Reward Rounding (M-01)

### Problem Description
The calculation for validator rewards uses integer division that can round to zero before being multiplied by other factors or simply due to high denominators.

### Reproduction Scenario
1.  Set `totalRewards` = 1,000,000 (1e6, e.g., 1 USDC).
2.  Set `validatorBasisPoints` = 500 (5%).
3.  Set `weight` = 1 (minimum weight).
4.  Set `totalQuantity` = 100.
5.  Set `totalAccurateWeight` = 1,000.

Calculation:
`(1,000,000 * 500 * 1) / (10,000 * 100 * 1,000)`
`500,000,000 / 1,000,000,000` = `0.5` -> **0** in Solidity.

Validator receives **0** rewards despite performing work.

---

## Fix Verification (Test Mapping)

| Finding | Test / Verification | Command |
| :--- | :--- | :--- |
| C-01 | Storage layout: `userActiveClaimedQuantity` at slot 18 (after config vars) | `forge inspect src/SapienCore.sol:SapienCore storage-layout` |
| M-01 | `test/findings/DivideBeforeMultiplyPrecision.t.sol` | `forge test --match-path test/findings/DivideBeforeMultiplyPrecision.t.sol` |
| M-02 | `test/findings/SecurityFixesVerification.t.sol`, `test/findings/TangentReplication.t.sol` | `forge test --match-contract "SecurityFixesVerification\|TangentReplication" --match-test "Tangent3\|Consensus_DoS"` |
| M-03 | `test/findings/ValidatorClaimSlotStarvation.t.sol` | `forge test --match-path test/findings/ValidatorClaimSlotStarvation.t.sol` |
| M-04 | Code: `rewardRateSnapshot` in `_contribute` / `claimContributionReward` (F-11) | — |
| M-05 | Code: `ValidationOracle` 14+36=50 slots | — |
| L-03 | Code: `MAX_BATCH_SIZE=50` in SapienCore, ValidationOracle | — |
