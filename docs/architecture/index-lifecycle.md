# Data Index Lifecycle

This document explains how the Sapien v0.5 protocol uses onchain indices to manage offchain data stored in external systems (e.g., S3 buckets, IPFS).

## Overview

The "index" is the unique identifier that bridges onchain logic with offchain storage. The contracts treat each index as a "logical unit of work" that requires one submission and multiple validations. The association between an index and specific data files is maintained by the frontend and offchain infrastructure.

## Slot Allocation: Range + Return-Stack Hybrid

v0.5 uses a hybrid allocator that combines contiguous range allocation with a LIFO return stack for recycled indices.

### Storage Layout

```solidity
mapping(bytes32 => IndexRange) indexRange;           // projectId → {start, count}
mapping(bytes32 => mapping(uint256 => uint256)) returnStack;  // projectId → stack
mapping(bytes32 => uint256) returnStackTop;           // projectId → stack height
```

### Allocation Flow

When `claimToContribute` assigns indices:

1. **Return stack first**: Recycle previously returned indices (from rejections/expirations)
2. **Range fallback**: Allocate fresh indices from the contiguous range

```
claimToContribute(projectId, quantity=3)
  │
  ├─ returnStackTop > 0?
  │   ├─ Yes: Pop from returnStack (LIFO)
  │   └─ Repeat until filled or stack empty
  │
  └─ remaining > 0?
      └─ Allocate from indexRange (decrement count)
```

### Return Flow

Indices are returned to the stack when:
- **Contribution rejected**: `computeConsensus` returns the slot when score < threshold
- **Claim expired**: `expireClaim` returns unsubmitted slots

```solidity
returnStack[projectId][returnStackTop[projectId]] = index;
returnStackTop[projectId]++;
project.availableSlots++;
```

## Sequence Diagram

```mermaid
sequenceDiagram
    participant S3 as S3 Bucket
    participant FE as Frontend
    participant SC as SapienCore

    Note over FE, SC: 1. Contributor Claims Slots
    FE->>SC: claimToContribute(projectId, quantity: 3, adapter)
    SC->>SC: Check returnStack first, then indexRange
    SC-->>FE: (claimId, indices: [5, 2, 6])
    Note right of SC: Index 2 recycled from stack,<br/>5 and 6 from fresh range

    Note over FE, S3: 2. Work Execution
    FE->>S3: GET /2.json, /5.json, /6.json
    S3-->>FE: Task Data
    Note left of FE: Contributor performs tasks

    Note over FE, SC: 3. Submission
    FE->>SC: batchContribute(claimId, [5,2,6], hashes[], cids[])
    Note right of SC: Each slot: Reserved → Pending
    Note right of SC: pendingContributions += 3

    Note over FE, SC: 4. Validation & Consensus
    Note right of SC: Validators commit-reveal scores
    SC->>SC: computeConsensus(projectId, index: 2)

    alt Accepted (score ≥ threshold)
        Note right of SC: Index 2 stays assigned
        Note right of SC: Contributor can claim reward
    else Rejected (score < threshold)
        SC->>SC: returnStack.push(2)
        SC->>SC: availableSlots++
        SC->>SC: submissionNonce[projectId][2]++
        Note right of SC: Index 2 available for re-claim
    end

    Note over FE, SC: 5. Re-Claim (Next Contributor)
    FE->>SC: claimToContribute(projectId, quantity: 1, adapter)
    SC->>SC: Pop index 2 from returnStack
    SC-->>FE: (claimId, indices: [2])
    Note right of SC: New contributor gets index 2
```

## Nonce System

Each index tracks a `submissionNonce` that increments when a contribution is rejected. This enables:

- **Re-contribution**: A new contributor can submit to the same index
- **Isolation**: Validations, consensus reports, and disputes are keyed by `(projectId, index, nonce)` to prevent state cross-contamination between rounds

```
submissionNonce[projectId][index] = 0  (first submission)
  → Rejected by consensus
submissionNonce[projectId][index] = 1  (second submission)
  → Accepted by consensus
```

## Summary Mapping

| System Component | Role of the Index |
|:---|:---|
| **S3 / IPFS** | The filename or CID (e.g., `3.json`). |
| **SapienCore** | The unique "slot" for a piece of work, tracked in `contributions[projectId][index]`. |
| **Frontend** | The key used to construct the URL: `bucket.s3.com/${index}.json`. |
| **Return Stack** | Recycling bin for rejected/expired indices, ensuring no wasted slots. |
| **Nonce** | Version counter per index, isolating each submission round. |

**Key Takeaway:** The contracts manage the flow of "units of work" (indices) with automatic recycling. The association between an index and specific data is maintained by the frontend and offchain infrastructure.
