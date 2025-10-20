# SAPIEN Protocol Smart Contracts

**A decentralized data foundry powering the future of AI training through human expertise and tokenized incentives.**

The SAPIEN protocol bridges the gap between human wisdom and machine learning where experts are rewarded for high-quality AI training data contributions. Built on Base with the $SAPIEN ERC-20 token, the protocol has connected over **550,000 trainers** across **100+ countries** who have completed more than **50 million tasks** for enterprise AI customers.

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
| **TimelockController** | `0x20304CbD5D4674b430CdC360f9F7B19790D98257` | [View on BaseScan](https://basescan.org/address/0x20304CbD5D4674b430CdC360f9F7B19790D98257) |
| **SapienQA** | `0x962F190C6DDf58547fe2Ac4696187694a715A2eA` | [View on BaseScan](https://basescan.org/address/0x962F190C6DDf58547fe2Ac4696187694a715A2eA) |
| **SapienVault** | `0x74b21FAdf654543B142De0bDC7a6A4a0c631e397` | [View on BaseScan](https://basescan.org/address/0x74b21FAdf654543B142De0bDC7a6A4a0c631e397) |
| **SapienRewards** | `0xB70C2BA5Aa45b052C2aC59D310bA8E93Ee65B3C9` | [View on BaseScan](https://basescan.org/address/0xB70C2BA5Aa45b052C2aC59D310bA8E93Ee65B3C9) |
| **USDCRewards** | `0x9E866C93Fc53baA53B7D00927094de0C18320AA2` | [View on BaseScan](https://basescan.org/address/0x9E866C93Fc53baA53B7D00927094de0C18320AA2) |
| **BatchRewards** | `0x6766D9285C8E6453De9eD17fec90618c0A1d02e2` | [View on BaseScan](https://basescan.org/address/0x6766D9285C8E6453De9eD17fec90618c0A1d02e2)

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