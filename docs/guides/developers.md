# Guide for Developers

Developers can extend the Sapien PoQ ecosystem by building **adapters** that connect external AI tools and workflows to the protocol. In v0.5, the protocol consists of two contracts — `SapienCore` and `SapienVault` — with all user-facing operations called on `SapienCore`.

## Architecture

An adapter typically consists of two parts:

1. **Off-chain interface**: A bridge that monitors an external tool (e.g., CVAT for image labeling, a custom annotation UI) and handles user authentication.
2. **On-chain integration**: Scripts or a contract that calls `SapienCore` functions on behalf of users, passing itself as the `adapter` parameter to receive fees.

## Adapter Integration Model

The protocol supports three adapter fee types, each collected at a different stage of the lifecycle:

| Adapter Type | Collected When | Parameter | Max Fee |
|-------------|----------------|-----------|---------|
| Origination | `fundProject` | `adapter` address | 5% (500 bps) |
| Contribution | `claimToContribute` | `adapter` address | 5% (500 bps) |
| Validation | `commitValidation` | `adapter` address | 5% (500 bps) |

Default adapter fee rates are 4% origination and 3% for contribution/validation (400/300/300 bps). These are set globally by the protocol admin and apply to all adapters equally.

### Origination Adapter

Receives a fee when an originator funds a project. The fee is deducted from the funded amount after the protocol fee.

```solidity
core.fundProject(projectId, amount, quantity, adapterAddress);
```

### Contribution Adapter

Receives a fee when a contributor's reward is eventually released. The adapter address is recorded at claim time:

```solidity
core.claimToContribute(projectId, quantity, adapterAddress);
```

### Validation Adapter

Receives a fee when a validator is settled. The adapter address is recorded at commit time:

```solidity
core.commitValidation(projectId, index, commitHash, stakeAmount, adapterAddress);
```

## Integration Points

### Contributor Adapter

A contributor adapter streamlines the submission of work:

1. Detect when a user finishes a task in the external tool.
2. Upload the work data to storage (S3, IPFS).
3. Call `SapienCore.contribute()` with the data reference.

**Key function**: `contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid)`

### Validator Adapter

A validator adapter provides a UI for human reviewers:

1. Query pending contributions via `getContribution(projectId, index)` — look for contributions with `Pending` status.
2. Present the work and the Task Definition Spec (from the project's `metadataCid`) to the validator.
3. Manage the commit-reveal lifecycle (storing the salt locally until the reveal phase).

**Key functions**:
- `lockValidatorCapacity(amount)` — one-time setup for validator capacity
- `claimToValidate(projectId, quantity)` — request random assignment of pending contributions
- `commitValidation(projectId, index, commitHash, stakeAmount, adapter)` — submit sealed score
- `revealValidation(projectId, index, score, salt)` — reveal score
- `settleValidator(projectId, index, nonce)` — settle position after consensus

### Commit Hash Construction

The commit hash packs the score as a `uint16` (2 bytes) followed by the `bytes32` salt (32 bytes), totaling 34 bytes:

```solidity
bytes32 commitHash = keccak256(abi.encodePacked(uint16(score), salt));
```

Score range is 0-10,000. Salt is a random `bytes32` value.

## Consuming Quality Signals

Applications can consume Sapien quality signals in several ways:

### On-chain Queries

```solidity
Contribution memory c = core.getContribution(projectId, index);
// c.status — Accepted, Rejected, Pending, Reserved, or Empty
// c.submissionHash — integrity hash of the contribution data
// c.rewardRate — reward amount for this contribution
// c.consensusNonce — current consensus round
```

### Events

Listen for key lifecycle events emitted by `SapienCore`:

| Event | Description |
|-------|-------------|
| `ContributionSubmitted` | A contribution has been submitted for review |
| `ConsensusReached` | Consensus computed — includes `weightedAverage` and `status` |
| `ValidatorSettled` | A validator has been settled — includes `outlier` flag |
| `ContributorRewardReleased` | Contributor reward moved to pending balance |
| `RewardClaimed` | User withdrew pending rewards |
| `DisputeOpened` | A dispute has been opened against a contribution |
| `DisputeResolved` | A dispute has been resolved |

### Reputation

Query a user's reputation for a specific role:

```solidity
Reputation memory rep = core.getReputation(user, roleKey);
// rep.score — current score (500-10,000, default 5000)
// rep.totalActions — lifetime action count
// rep.successfulActions — successful actions count
// rep.lastUpdated — last update timestamp
```

Role keys are:
- `keccak256("ORIGINATOR")` for originator reputation
- `keccak256("CONTRIBUTOR")` for contributor reputation
- `keccak256("VALIDATOR")` for validator reputation

### Adapter Fee Queries

```solidity
(uint256 origBps, uint256 contribBps, uint256 valBps) = core.getAdapterFees();

address origAdapter = core.getOriginationAdapter(projectId);
address contribAdapter = core.getContributionAdapter(claimId);
address valAdapter = core.getValidationAdapter(projectId, index, nonce, validator);
```

## Dispute System

The dispute system allows participants to challenge consensus outcomes:

- `openDispute(projectId, index, evidenceHash, evidenceCid)` — post a bond and challenge the result
- `resolveDispute(projectId, index, upheld)` — operator resolves the dispute
- `escalateDispute(projectId, index)` — anyone can escalate after 7 days if unresolved

Dispute state can be queried via `getDispute(projectId, index)`.

## Testing Your Integration

We recommend using **Foundry** for testing adapters against the Sapien contracts.

1. Fork the Sapien deployment on Base Sepolia.
2. Deploy your adapter contract (if applicable).
3. Simulate the full lifecycle:

```
createProject → fundProject → claimToContribute → contribute
→ claimToValidate → commitValidation → revealValidation
→ computeConsensus → settleValidator → releaseContributorReward → claimReward
```

Key test scenarios:
- Happy path with accepted contributions
- Rejected contributions (below consensus threshold)
- Expired claims and stake slashing
- Dispute flow (open, resolve, escalate)
- Batch operations for gas optimization
