# SAPIEN Protocol Smart Contracts

**A decentralized data foundry powering the future of AI training through human expertise and tokenized incentives.**

The SAPIEN protocol bridges the gap between human wisdom and machine learning where experts are rewarded for high-quality AI training data contributions. Built on Base with the $SAPIEN ERC-20 token, the protocol has connected over **100,000 trainers** across **25+ countries** for AI data customers.

---

## System Architecture

### Core Smart Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **SapienToken** | ERC-20 utility token | Standard token implementation |
| **SapienVault** | Staking & lockup management | Progressive staking rewards, temporal lockup multipliers, emergency controls |
| **SapienQA** | Quality assurance enforcement | Automated validation, progressive penalty system, comprehensive audit trails |
| **SapienRewards** | Task reward distribution | EIP-712 cryptographic signatures, duplicate protection |

### Base Mainnet Deployment

| Contract | Address | BaseScan |
|----------|---------|----------|
| **SAPIEN** | `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3` | [View on BaseScan](https://basescan.org/address/0xC729777d0470F30612B1564Fd96E8Dd26f5814E3) |
| **USDC** | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | [View on BaseScan](https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) |
| **TimelockController** | `0x20304CbD5D4674b430CdC360f9F7B19790D98257` | [View on BaseScan](https://basescan.org/address/0x20304CbD5D4674b430CdC360f9F7B19790D98257) |
| **SapienQA** | `0x962F190C6DDf58547fe2Ac4696187694a715A2eA` | [View on BaseScan](https://basescan.org/address/0x962F190C6DDf58547fe2Ac4696187694a715A2eA) |
| **SapienVault** | `0x74b21FAdf654543B142De0bDC7a6A4a0c631e397` | [View on BaseScan](https://basescan.org/address/0x74b21FAdf654543B142De0bDC7a6A4a0c631e397) |
| **SapienRewards** | `0xB70C2BA5Aa45b052C2aC59D310bA8E93Ee65B3C9` | [View on BaseScan](https://basescan.org/address/0xB70C2BA5Aa45b052C2aC59D310bA8E93Ee65B3C9) |
| **USDCRewards** | `0x9E866C93Fc53baA53B7D00927094de0C18320AA2` | [View on BaseScan](https://basescan.org/address/0x9E866C93Fc53baA53B7D00927094de0C18320AA2) |
| **BatchRewards** | `0x6766D9285C8E6453De9eD17fec90618c0A1d02e2` | [View on BaseScan](https://basescan.org/address/0x6766D9285C8E6453De9eD17fec90618c0A1d02e2) |

### Base Sepolia Deployment

| Contract | Address | BaseScan |
|----------|---------|----------|
| **SAPIEN** | `0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6` | [View on BaseScan](https://sepolia.basescan.org/address/0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6) |
| **USDC** | `0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05` | [View on BaseScan](https://sepolia.basescan.org/address/0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05) |
| **TimelockController** | `0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC` | [View on BaseScan](https://sepolia.basescan.org/address/0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC) |
| **SapienQA** | `0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF` | [View on BaseScan](https://sepolia.basescan.org/address/0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF) |
| **SapienVault** | `0x3a92bF12A5ece7959C47D1aF32E10d71d868bF90` | [View on BaseScan](https://sepolia.basescan.org/address/0x3a92bF12A5ece7959C47D1aF32E10d71d868bF90) |
| **SapienRewards** | `0xFF443d92F80A12Fb7343bb16d44df60204c6eB08` | [View on BaseScan](https://sepolia.basescan.org/address/0xFF443d92F80A12Fb7343bb16d44df60204c6eB08) |
| **USDCRewards** | `0x798Fc8E87AfD496b8a16b436120cc6A456d3AC48` | [View on BaseScan](https://sepolia.basescan.org/address/0x798Fc8E87AfD496b8a16b436120cc6A456d3AC48) |
| **BatchRewards** | `0xae064cF985da8Cd842753D65B307E27A3853838e` | [View on BaseScan](https://sepolia.basescan.org/address/0xae064cF985da8Cd842753D65B307E27A3853838e) |
---

## Technical Documentation

Comprehensive technical specifications for each smart contract:

- **[SapienVault](notes/SapienVault.md)** - Staking mechanisms, lockup management, and vault operations
- **[SapienQA](notes/SapienQA.md)** - Quality assurance system and penalty enforcement protocols  
- **[SapienRewards](notes/SapienRewards.md)** - Off-chain signed reward claims and distribution mechanisms
- **[SAPIEN Whitepaper](https://docs.sapien.io/sapien-litepaper/proof-of-quality)** - Complete tokenomics and protocol design specification
- **[Multiplier Paper](notes/multiplier.pdf)** - Paper on the multiplier math
- **[Rewards Signatures](notes/rewards-signature-system.md)** - Rewards signature docs
- **[Batch Rewards](notes/BatchRewards.md)** -  Batches rewards for USDC and SAPIEN
---

### Development Infrastructure

Built with **Foundry** for comprehensive smart contract development:

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run comprehensive test suite
forge test -v

# Run specific end-to-end test scenarios
forge test --match-test "test_QA_EndToEndScenario" -vv
forge test --match-test "test_EndToEnd_CompleteStakingJourney" -v
forge test --match-test "test_EndToEnd_CompleteUserJourney" -v

# Execute unit test suite
make unit

# Run variable testing scenarios
make invar

# Generate code coverage reports
make cover

# Display coverage analysis
make show

# Generate gas consumption snapshots
forge snapshot
```

## Security Considerations

- **EIP-712 Signature Verification**: All off-chain signed operations use cryptographic signature validation
- **Reentrancy Protection**: Comprehensive reentrancy guards across all external contract interactions
- **Access Control**: Role-based permissions with multi-signature requirements for critical operations
- **Pause Mechanisms**: Emergency pause functionality for all user-facing operations
- **Progressive Penalties**: Graduated penalty system to prevent abuse while maintaining user protection

## Deployment Architecture

The protocol utilizes OpenZeppelin's upgradeable proxy pattern for critical contracts:

- **SapienVault**: Upgradeable proxy implementation
- **SapienRewards**: Upgradeable proxy implementation  
- **SapienQA**: Upgradeable proxy implementation
- **SapienToken**: Standard ERC-20 implementation

## Gas Optimization

- **Library Usage**: Multiplier calculations implemented as library to reduce deployment costs
- **Batch Operations**: Rewards and QA operations support batch processing
- **Efficient Storage**: Optimized storage layouts and packing for reduced gas consumption
- **Minimal External Calls**: Reduced cross-contract calls through careful architecture design