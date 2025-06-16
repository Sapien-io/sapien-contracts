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
| **Multiplier** | Reward calculation engine | Performance-based multipliers, time-weighted reward bonuses |

---

## Technical Documentation

Comprehensive technical specifications for each smart contract:

- **[SapienVault](notes/SapienVault.md)** - Staking mechanisms, lockup management, and vault operations
- **[SapienQA](notes/SapienQA.md)** - Quality assurance system and penalty enforcement protocols  
- **[SapienRewards](notes/SapienRewards.md)** - Off-chain signed reward claims and distribution mechanisms
- **[Multiplier](notes/Multiplier.md)** - Reward calculation algorithms and multiplier mechanics
- **[SAPIEN Whitepaper](notes/whitepaper.md)** - Complete tokenomics and protocol design specification
- **[Multiplier Paper](notes/multiplier.pdf)** - Paper on the multiplier math

---

## Comprehensive Testing Framework

The SAPIEN protocol implements an extensive smart contract testing framework with comprehensive end-to-end validation that covers complete user journeys and production scenarios.

### End-to-End Test Coverage

#### SapienQA Testing Suite (`SapienQA.t.sol`)
**19 comprehensive test cases** covering the complete quality assurance workflow:

- **Progressive Enforcement Testing**: Warning → Minor Penalty → Major Penalty progression
- **Community Governance Validation**: Realistic QA enforcement scenario testing
- **Cross-Contract Integration**: QA ↔ Vault ↔ Token interaction validation
- **Security Protocol Verification**: EIP-712 signature validation, replay attack prevention
- **Edge Case Coverage**: Insufficient stakes, vault pause states, error recovery procedures

**Primary Integration Test**: `test_QA_EndToEndScenario`
- Simulates complete user journey from initial staking to penalty enforcement
- Validates 4 sequential QA decisions (2 warnings + 2 penalties)
- Tests progressive enforcement with stake reduction (10,000 → 8,500 tokens)
- Ensures complete audit trail integrity and data consistency

#### SapienVault Testing Suite (`SapienVault_EndToEnd.t.sol`)
**Multi-phase temporal testing** with 8 distinct user personas over 400+ day simulation periods

#### SapienRewards Testing Suite (`SapienRewards_EndToEnd.t.sol`)
**6 comprehensive test phases** covering the complete reward distribution system:

- **Extended User Journey Simulation**: 365+ day simulation with realistic usage patterns
- **Multi-User Coordination Testing**: 50+ concurrent users with distinct behavioral profiles
- **Emergency Procedure Validation**: System pause protocols, recovery mechanisms, balance reconciliation
- **Financial Accuracy Verification**: Precise balance tracking across 202+ reward orders
- **High-Load Performance Testing**: Rapid-fire claim processing and system stress validation

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
make var

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
- **Multiplier**: Library implementation for gas optimization

## Gas Optimization

- **Library Usage**: Multiplier calculations implemented as library to reduce deployment costs
- **Batch Operations**: Rewards and QA operations support batch processing
- **Efficient Storage**: Optimized storage layouts and packing for reduced gas consumption
- **Minimal External Calls**: Reduced cross-contract calls through careful architecture design