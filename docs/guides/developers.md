# Guide for Developers

Developers can extend the Sapien PoQ ecosystem by building **Oracles (Adapters)** that connect external AI tools and workflows to the protocol.

## 🔗 Architecture of an Oracle

An Oracle typically consists of two parts:
1. **offchain Interface**: A bridge that monitors an external tool (e.g., CVAT for image labeling) and handles user authentication.
2. **onchain Adapter**: A set of scripts or a contract that calls the `SapienCore` or `ValidationOracle` functions on behalf of the users.

## 🛠️ Integration Points

### Contributor Oracle
A Contributor Oracle streamlines the submission of work.
- **Workflow**:
    1. Detect when a user finishes a task in the external tool.
    2. Upload the work data to a storage bucket (S3, IPFS).
    3. Call `SapienCore.contribute()` with the data reference and hash.
- **Key Function**: `contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash)`

### Validator Oracle
A Validator Oracle provides a UI for human reviewers or an API for autonomous validators.
- **Workflow**:
    1. Fetch pending contributions from `ValidationOracle`.
    2. Present the work and the Task Definition Spec (TDS) to the validator.
    3. Manage the **Commit-Reveal** lifecycle (storing the salt locally until the reveal phase).
- **Key Functions**: `claimToValidate()`, `commitValidation()`, `revealValidation()`.

## 📦 Building a Custom Consensus Algorithm

If the existing algorithms (Linear, Sqrt, Hybrid) don't meet your needs, you can implement your own.

1. **Implement `IConsensusAlgorithm`**: Create a contract that follows the interface.
2. **Calculate Consensus**: In the `calculateConsensus` function, implement your logic for weighting and outlier detection.
3. **Registration**: An admin must register your contract address in the `ValidationOracle`.

```solidity
interface IConsensusAlgorithm {
    function calculateConsensus(ValidationInput[] calldata validations)
        external view returns (ConsensusResult memory result);
    
    function getName() external pure returns (string memory);
}
```

## 📊 Consuming Quality Signals

Applications can consume Sapien quality signals in several ways:
- **onchain**: Query the `SapienCore.contributions` mapping to see the `status` and `averageScore`.
- **offchain**: Listen for `ContributionFinalized` events.
- **Attestations**: Read the attestations from the **Ethereum Attestation Service (EAS)** linked to each contribution.

## 🧪 Testing Your Integration

We recommend using **Foundry** for testing your adapters against the Sapien contracts.
1. Fork the Sapien deployment on Base Sepolia.
2. Deploy your adapter.
3. Simulate the full lifecycle: `createProject` -> `claim` -> `contribute` -> `validate` -> `finalize`.
