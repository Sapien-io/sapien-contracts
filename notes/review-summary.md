# SC Protocol Review and Update Plan

**For**: CTO and Team  
**From**: Chad  
**Date**: May 2025  

## Summary

This is a design and security review of Sapien's smart contracts for pre-launch requirements. Automated and manual review identified a range of suggestions for architectural and functional implementation. Based on the notes within, this doc outlines the recommended udpates to enhance security, performance, and maintainability.

### 1. Migrate from Hardhat to Foundry Testing Framework
- **Performance**: 10-100x faster test execution
- **Impact**: Improved development velocity and test coverage

### 2. Fix Implementation Findings
**Current Issues**: A variety of security related fixes contained within the subsequent contract folders and summaryized here [Security Review](contracts-review-may/security-review-report.md).

### 3. Separate Token and Vesting Architecture
- **Current Problem**: Token contract handles both ERC20 logic and vesting (violates single responsibility)
- **Risk**: Unnecessary security risk from Vesting Logic contained within Token contract and degraded trust by token upgradeability
- **Solution**: 
  - Create immutable, non-upgradeable `SapienToken` (pure ERC20)
  - Create separate upgradeable `VestingVault` contract

### 4. Simplify Staking System Architecture
- **Current Issue**: 
  - Over-complex signature requirements for all staking operations
  - Offchain attack surface inherited onchain uneccessarily 
- **Solution**: Remove unnecessary signature requirements, simplify processes

### 5. Enhance Rewards System Security
- **Needed Changes**:
  - Mitigate issues found during review
  - Unit, integration, scenario and invariant testing with fuzzing

### 6. Enhance RBAC and Upgradability
- **Current Risk**: Uses non-standard access control implementation and upgradeability patterns
- **Needed Changes**:
  - Use OZ AccessControl standard contracts where the roles reference the internal purpose for access control, not the origin of it's authoity. Review all instances of `gnosisSafe`, `sapienAddress` and `authorizedSigner` and determine where and how if time allows for these roles to be unambiguated.
  
### 7. Create documentation for the Protocol
- **Needed Changes**:
  - Gitbook Documentation
  - Notion Documentation
  - `sapien-contracts` documentation
  - SRED Documentation


## Implementation / Asana Overview

Diagram of [proposed architectural changes](contracts-review-may/token/contract-relationships.svg)

### Architectural Updates ( May 26th - May 28th )
- [x] Chore: Migrate to Foundry testing framework
- [x] Feat: Implement separated vesting architecture
  - [x] Create immutable `SapienToken` contract
- [x] Feat: Remove offchain Staking signatures 

### Functional Issues and Fixes ( May 28th - May 30th )
- [x] Fix: Review items found in [May Contracts Review](contracts-review-may) 
  - [x] [Staking](contracts-review-may/staking)
  - [x] [Rewards](contracts-review-may/rewards)
  - [x] [Token ](contracts-review-may/token)
- [ ] Chore: Ensure flow of funds compliance with Business requirements
- [x] Feat: Implement input validations where neccessary
- [x] Feat: Update the Access Control / Roles
- [ ] Chore: Ensure inline Natspec documentation is updated
- [x] Test: 100% unit test coverage with forge
- [ ] Test: integration tests with Tenderly vNET(and/or) Base Sepolia
- [ ] Test: scenario tests for product UX flows
- [x] Test: invariant tests for fund flows with fuzzing
- [x] Test: CI/CD and repo docs for release process


### Offchain Implementation ( June 2nd - June 6th )
- [ ] Create Operational Document
- [ ] Setup Data Indexing for sapien-server / sapien-indexing
- [ ] Design and Create monitoring and alerting systems
- [ ] Review / Assist / Implement Server and Application Integrations for data
- [ ] Review / Assist / Implement Wallet, Network and Accounts implementation in sapien-server and sapien-web
- [ ] Documentation for Gitbook, Notion, Repo and SRED