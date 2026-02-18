# Sapien PoQ v0.5 — Protocol Intent & Summary

## System Overview

Sapien PoQ v0.5 is a decentralized quality oracle protocol designed for AI workflow verification. The protocol enables stake-weighted, consensus-based assessment of AI-generated data and agent behaviors through a structured workflow involving originators, contributors, and validators.

## Core Protocol Claims

### Primary Purpose
The protocol claims to provide decentralized quality assurance for AI workflows by:
- Enabling originators to post tasks with funded reward pools
- Allowing contributors to claim and submit work for specific data points
- Having validators independently score submissions via commit-reveal mechanism
- Settling rewards and penalties based on weighted consensus agreement
- Supporting participation from humans, AI agents, or hybrid teams

### Economic Security Model
The protocol claims economic security through:
- Stake-locked participation (contributors and validators must lock tokens)
- Slashing mechanisms for poor performance or malicious behavior
- Reputation system with asymmetric gains/losses
- Dispute resolution with bonded challenges
- Originator accountability through locked stake

### Technical Architecture Claims
The protocol claims to:
- Use ERC-4337 Smart Accounts for account abstraction (Coinbase Smart Wallet)
- Consolidate functionality from 5 contracts to 2 contracts + 1 library
- Implement ERC-7201 namespaced storage for upgrade safety
- Use phased finalization (compute consensus → settle validators → claim rewards)
- Employ commit-reveal validation to prevent herding
- Provide adapter fees for frontend/tooling developers
- Support pluggable consensus algorithms

## Intended Behavior

### Participant Roles
1. **Originators**: Fund projects, define requirements, face accountability for misconduct
2. **Contributors**: Claim data points, submit work, receive rewards if accepted
3. **Validators**: Score submissions, earn rewards, face slashing for poor performance
4. **Adapters**: Build frontends/tools, earn fees for facilitating protocol interactions
5. **Operators**: Resolve disputes and maintain protocol health

### Key Protocol Flows
1. **Project Lifecycle**: Create → Fund → Active → Completed
2. **Work Submission**: Claim indices → Submit work → Validation → Consensus → Settlement
3. **Validation Process**: Commit (blind) → Reveal (with stake) → Consensus computation
4. **Reward Distribution**: Phased settlement preventing single-transaction reverts
5. **Dispute Resolution**: Bonded challenges with operator resolution and auto-escalation

### Security Properties
The protocol intends to be:
- **Trust-minimized**: Only stake operations require external calls
- **Censorship-resistant**: Permissionless participation and dispute escalation
- **Economically secure**: All participants have skin in the game
- **Upgradeable**: ERC-1967 proxies with ERC-7201 storage
- **Account-abstracted**: ERC-4337 native with session key delegation

## Critical Assumptions

### External Dependencies
- ERC-4337 infrastructure (EntryPoint, Bundler, Paymaster) operates correctly
- Coinbase Smart Wallet provides secure account abstraction
- ConsensusLib algorithms produce fair weighted averages and outlier detection

### Participant Behavior
- Validators act honestly (commit-reveal prevents strategic voting)
- Originators provide legitimate tasks (accountability mechanisms deter abuse)
- Adapters provide value (fee structure incentivizes quality tooling)
- Operators resolve disputes fairly (within time bounds)

### Economic Model
- SAPIEN token has sufficient value to deter attacks
- Fee structure covers operational costs
- Stake requirements prevent Sybil attacks
- Reputation system converges toward quality signaling

## Success Criteria

The protocol achieves its goals if:
- High-quality AI workflows receive consensus approval and rewards
- Low-quality submissions are rejected with appropriate penalties
- Malicious actors face economic consequences
- The protocol scales to support meaningful AI verification tasks
- Account abstraction enables seamless UX for all participant types
- Dispute mechanisms resolve conflicts fairly and efficiently