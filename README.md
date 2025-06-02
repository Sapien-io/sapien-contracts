# SAPIEN Protocol Smart Contracts

**A decentralized data foundry powering the future of AI training through human expertise and tokenized incentives.**

The SAPIEN protocol bridges the gap between human wisdom and machine learning by creating a self-regulating economy where experts are rewarded for high-quality AI training data contributions. Built on Base with the $SAPIEN ERC-20 token, the protocol has already connected over **550,000 trainers** across **100+ countries** who have completed more than **50 million tasks** for enterprise AI customers.

---

## 🏗️ System Architecture

### Core Smart Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **SapienToken** | ERC-20 utility token | Standard token with emission controls |
| **SapienVault** | Staking & lockup management | Progressive staking, lockup multipliers, emergency features |
| **SapienQA** | Quality assurance enforcement | validation, progressive penalties, audit trails |
| **SapienRewards** | Task reward distribution | EIP-712 signatures, duplicate protection, batch processing |
| **Multiplier** | Reward calculation engine | Performance-based multipliers, time-weighted bonuses |

---

## 📚 Contract Documentation

Detailed technical documentation for each smart contract:

- **[SapienVault](notes/SapienVault.md)** - Staking, lockup management, and vault operations
- **[SapienQA](notes/SapienQA.md)** - Quality assurance system and penalty enforcement  
- **[SapienRewards](notes/SapienRewards.md)** - Off-chain signed reward claims and distribution
- **[Multiplier](notes/Multiplier.md)** - Reward calculation and multiplier mechanics
- **[SAPIEN Whitepaper](notes/whitepaper.md)** - Complete tokenomics and protocol design

---

## 🔬 Comprehensive Testing Suite

The SAPIEN protocol features one of the most comprehensive smart contract testing suites in DeFi, with **extensive end-to-end testing** that validates complete user journeys and real-world scenarios.

### 🎭 End-to-End Test Coverage

#### SapienQA Testing Suite (`SapienQA.t.sol`)
**19 comprehensive tests** covering the complete quality assurance workflow:

- **✅ Progressive Enforcement**: Warning → Minor Penalty → Major Penalty
- **✅ Community Governance**: Realistic QA enforcement scenarios
- **✅ Cross-Contract Integration**: QA ↔ Vault ↔ Token interactions
- **✅ Security Validation**: EIP-712 signatures, replay attack prevention
- **✅ Edge Case Handling**: Insufficient stakes, vault pauses, error recovery

**Main End-to-End Test**: `test_QA_EndToEndScenario`
- Simulates complete user journey from staking to penalty enforcement
- Validates 4 QA decisions (2 warnings + 2 penalties)
- Tests progressive enforcement with stake reduction (10,000 → 8,500 tokens)
- Ensures perfect audit trail and data integrity

#### SapienVault Testing Suite (`SapienVault_EndToEnd.t.sol`)
**Multi-phase testing** with 8 distinct user personas over 400+ days:

#### SapienRewards Testing Suite (`SapienRewards_EndToEnd.t.sol`)
**6 comprehensive test phases** covering the complete rewards claiming system:

- **✅ User Journey**: 365+ day simulation with realistic usage patterns
- **✅ Multi-User Coordination**: 50+ concurrent users with distinct behaviors
- **✅ Emergency Procedures**: System pause, recovery, balance reconciliation
- **✅ Financial Accuracy**: Perfect balance tracking across 202+ orders
- **✅ High-Load Performance**: Rapid-fire claims and stress testing

### 🔧 Development Tools

Built with **Foundry** for maximum development efficiency:

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run comprehensive test suite
forge test -v

# Run specific end-to-end tests
forge test --match-test "test_QA_EndToEndScenario" -vv
forge test --match-test "test_EndToEnd_CompleteStakingJourney" -v
forge test --match-test "test_EndToEnd_CompleteUserJourney" -v

make unit
make var

make cover
make show

# Generate gas snapshots
forge snapshot

```

