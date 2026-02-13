# EOA Wallets vs ERC-8004 Accounts

## Purpose

This document compares two identity and execution models for Sapien:

- staying with wallet-native EOA identity
- migrating to ERC-8004 identity with protocol `AgentAccount` execution

The comparison focuses on protocol requirements, security posture, ecosystem interoperability, and implementation cost.

## Definitions

### EOA Wallet Model

Participants are identified and authorized directly by `msg.sender` wallet addresses. Protocol state is keyed by addresses.

### ERC-8004 Account Model

Participants are identified by `(chainId, identityRegistry, agentId)` and represented in-protocol by a canonical `agentKey`.  
Execution is performed by deterministic `AgentAccount` contracts, with delegated authorization using EIP-712 and ERC-1271 support.

## Option A: Stay with EOA Wallets

### Pros

- **Low implementation complexity**
  - Minimal architectural changes from current contracts.
  - Simpler code paths and fewer new components.
- **Faster time to shipping**
  - Less interface churn in core/oracle/rewards/trust.
  - Existing test suite structure remains mostly valid.
- **Lower gas overhead per action**
  - No forwarder or account indirection layer by default.
  - Fewer signature verification branches in hot paths.
- **Operational simplicity**
  - Fewer deployed contracts and fewer upgrade surfaces.
  - Easier debugging for direct wallet-based transactions.
- **Lower immediate audit burden**
  - Avoids introducing new high-privilege auth modules (forwarder/resolver/account factory).

### Cons

- **Not strict ERC-8004 compatible**
  - Identity is wallet-centric, not registry-centric.
  - Weak native interoperability with ERC-8004 ecosystem tools.
- **Poor wallet rotation ergonomics**
  - Rotating wallets usually implies state migration or rebinding complexity.
  - Higher risk of partial migration errors (claims, rewards, lock states).
- **Agent portability limitations**
  - Identity continuity across wallet/controller changes is not first-class.
  - Harder to express long-lived agent identity independent of key custody.
- **Composability gap for institutional/contract signers**
  - EOA-only assumptions often leak into APIs and event semantics.
  - Contract signer support can become fragmented and ad hoc.
- **Weaker identity analytics**
  - Address-level attribution fragments participant history over time.

## Option B: Move to ERC-8004 Accounts

### Pros

- **Strict on-chain identity compatibility**
  - Aligns natively with ERC-8004 identity, reputation, and validation registries.
  - Standardized discovery and trust primitives for external protocols.
- **Strong identity continuity**
  - `agentKey` remains stable while controllers/wallets rotate.
  - Protocol state remains attached to identity, not a mutable key.
- **First-class wallet rotation**
  - No economic-state migration if execution account remains stable.
  - Safer continuity for in-flight lifecycle states.
- **Better support for autonomous and institutional agents**
  - Native ERC-1271 path for contract signatures.
  - Works cleanly for multi-sig, policy wallets, and managed operators.
- **Improved event and data indexing**
  - Identity-rich events allow deterministic agent-level analytics.
  - Easier cross-dapp attribution and reputation aggregation.
- **Future-proof integration surface**
  - Easier integration with emerging agent protocols and identity registries.

### Cons

- **Higher implementation complexity**
  - Requires new modules: resolver, forwarder, account factory, adapters.
  - Significant refactor of address-keyed maps and interfaces.
- **Longer delivery and audit timeline**
  - More contracts and trust boundaries to review.
  - Expanded invariant and integration testing scope.
- **Gas overhead**
  - Delegated execution and signature verification add runtime cost.
  - Additional storage reads for identity resolution and nonce checks.
- **Operational complexity**
  - Registry mode management (internal vs external) adds config risk.
  - More deployment sequencing and dependency management.
- **Failure-mode expansion**
  - Misconfigured resolver/registry/forwarder can break auth globally.
  - More severe blast radius from identity-layer bugs.

## Security Tradeoff Summary

### EOA Model Security Profile

- smaller attack surface
- fewer moving parts
- but weaker guarantees for identity continuity and controlled delegation

### ERC-8004 Account Security Profile

- stronger identity semantics and delegated auth model
- better for long-lived agent operations
- but requires rigorous controls around:
  - nonce/replay protection
  - signature domain separation
  - registry authority checks
  - account creation determinism
  - mode-switch and rotation invariants

## Product and Ecosystem Tradeoff Summary

### EOA Model

- best when optimizing for shortest path to first deployment
- acceptable for single-wallet operators with low identity portability needs

### ERC-8004 Account Model

- best when optimizing for composability, interoperability, and durable agent identity
- stronger fit for multi-operator, long-lived, cross-integration agent ecosystems

## Cost of Change

### Staying EOA

- low initial engineering cost
- potentially high future migration cost if strict identity interoperability becomes mandatory

### Moving to ERC-8004 Accounts

- high initial engineering and audit cost
- lower long-term migration risk and cleaner ecosystem integration

## Decision Guidance for Sapien

Given current stated requirements:

- strict on-chain ERC-8004 compatibility
- wallet rotation without state loss
- support for contract-agent participants across all roles

the **ERC-8004 account model is the better architectural fit**.

Staying EOA is still a valid strategy only if priorities change to:

- minimizing short-term complexity over standards alignment
- delaying identity portability and rotation guarantees
- accepting future migration overhead

## Practical Recommendation

If Sapien remains pre-mainnet and can tolerate a larger pre-launch build phase, choose ERC-8004 accounts now and avoid legacy debt.

If scope pressure forces a phased rollout, maintain the same end-state target:

- identity-keyed state
- deterministic agent execution accounts
- delegated auth with EIP-712 and ERC-1271
- rotation invariants enforced by tests before mainnet
