# SapienQA Contract Documentation

## Overview

**Contract:** SapienQA  
**Purpose:** Provides a signature-based quality assurance system to assess user behavior, apply penalties, and maintain audit trails in the Sapien Protocol.

### Core Features

- Signature-verified QA decisions using EIP-712
- Modular penalty enforcement via Vault contract
- Full user QA history tracking
- Admin/manager role-based architecture
- Replay protection with unique decisionId

---

## Initialization

```solidity
constructor(address _treasury, address _vaultContract, address qaManager, address admin)
```

Initializes contract with treasury address, Vault contract address, and role assignments.

---

## Roles

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Controls configuration and contract upgrades |
| `QA_MANAGER_ROLE` | Can submit signed decisions for processing |
| `QA_SIGNER_ROLE` | Authorized signer for QA decisions (EIP-712) |

---

## Main Function

### `processQualityAssessment(...)`

Signature-based action executor with internal validation:

- Checks input values and replay protection
- Verifies signer is `QA_SIGNER_ROLE`
- Calls `SapienVault.processQAPenalty(...)` if penalty is applied
- Logs decision in `userQAHistory`

#### Parameters

- **`userAddress`**: Target user
- **`actionType`**: Enum (WARNING, MINOR_PENALTY, etc.)
- **`penaltyAmount`**: Amount to penalize user
- **`decisionId`**: Unique hash to prevent replay
- **`reason`**: Human-readable string
- **`signature`**: Signed EIP-712 hash by QA admin

---

## Signature Verification (EIP-712)

### Struct Definition

```solidity
QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,string reason)
```

### QA_DECISION_TYPEHASH

```solidity
keccak256("QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,string reason)")
```

### `_verifySignature(...)`

- Hashes the struct
- Recovers signer address
- Requires `QA_SIGNER_ROLE`

---

## QA Decision Storage

### QARecord Struct Fields

- **`actionType`**: Enum value
- **`penaltyAmount`**: Amount deducted (if any)
- **`decisionId`**: Unique identifier
- **`reason`**: Explanation for the action
- **`timestamp`**: When decision was applied
- **`processor`**: msg.sender that executed the decision

Stored per user in `userQAHistory[address]`.

---

## View Functions

| Function | Description |
|----------|-------------|
| `getUserQAHistory(user)` | Returns all QA records for user |
| `getUserQARecordCount(user)` | Returns count of QA records |
| `isDecisionProcessed(id)` | Prevents decision replay |
| `getQAStatistics()` | Total penalties and warnings |

---

## Admin Functions

| Function | Description |
|----------|-------------|
| `updateTreasury(address)` | Changes penalty destination |
| `updateVaultContract(address)` | Changes the SapienVault reference |

---

## Events

| Event | Description |
|-------|-------------|
| `QualityAssessmentProcessed` | Main execution success event |
| `QAPenaltyPartial` | Penalty applied partially (e.g., low balance) |
| `QAPenaltyFailed` | Penalty processing failed |
| `TreasuryUpdated` | Treasury address changed |
| `VaultContractUpdated` | Vault reference updated |

---

## Errors

- **`ZeroAddress()`** – Null address used
- **`DecisionAlreadyProcessed()`** – Prevents replay
- **`InvalidDecisionId()`** – Empty ID
- **`EmptyReason()`** – Explanation required
- **`InvalidPenaltyForWarning()`** – Non-zero penalty on warning
- **`PenaltyAmountRequired()`** – Required for penalty action types
- **`InvalidSignatureLength()`** – Must be 65 bytes
- **`UnauthorizedSigner(address)`** – Not a valid QA admin signer

---

## Design Considerations

- QA actions are immutable, replay-resistant, and verifiable
- Penalties routed via vault to preserve accounting
- Decouples action review (QA Admin) from execution (QA Manager)
- Fully transparent and audit-friendly structure

---
