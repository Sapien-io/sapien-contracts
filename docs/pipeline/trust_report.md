# Sapien PoQ Protocol Trust Report

## Who Can Rug, Pause, or Drain?

### 1. Rug (The Admin)
*   **Default Admin Role (`DEFAULT_ADMIN_ROLE`):** This role has ultimate power. 
    *   **Emergency Withdraw:** In the `Rewards` contract, the admin can call `emergencyWithdraw` when the contract is paused. While it checks against `totalAllocated`, a compromised admin could theoretically manipulate allocations or simply pause and withdraw all "unallocated" (but actually project-funded) rewards.
    *   **Upgrades:** The protocol uses the Transparent Proxy pattern. The `ProxyAdmin` (usually the same as `DEFAULT_ADMIN_ROLE`) can upgrade contract logic, effectively allowing them to change any rule or drain any fund.
    *   **Fees:** Admin can set protocol fees up to 3% (`MAX_PROTOCOL_FEE_BPS`).

### 2. Pause (Emergency Stops)
*   **Vault Pausing:** The `PAUSER_ROLE` (initially the admin) can pause `SapienVault`. This prevents deposits, withdrawals, transfers, and slashing.
*   **Rewards Pausing:** The `DEFAULT_ADMIN_ROLE` can pause the `Rewards` contract, stopping reward claims and allocations.

### 3. Drain (The Slashers)
*   **Slasher Role (`SLASHER_ROLE`):** Held by `SapienCore` and `ValidationOracle`. These contracts can burn user shares in the `SapienVault`. 
    *   **Centralization Risk:** If either of these contracts is compromised or contains logic bugs, it could be used to zero out any user's stake. 
    *   **Collusion:** Malicious validators or originators could theoretically trigger slashes through the protocol logic if they can control the consensus outcome.

## Trust Assumptions Summary

| Actor | Trust Level | Risk Impact |
| :--- | :--- | :--- |
| **Protocol Admin** | **EXTREME** | Full control over upgrades, fees, and emergency withdrawals. |
| **Originators** | **MEDIUM** | Can create malicious projects or set extreme reveal deadlines (mitigated by `MIN_REVEAL_DEADLINE`). |
| **Validators** | **MEDIUM-HIGH** | If enough validators collude, they can control the `weightedAverage` score, potentially approving poor work or slashing honest contributors. |
| **SapienCore / Oracle** | **HIGH** | These contracts hold `SLASHER_ROLE` and `LOCKER_ROLE`. Their logic must be perfect to avoid accidental draining of user stakes. |

## Centralization Risk Score: 8/10 (High)

The protocol is highly centralized around the `DEFAULT_ADMIN_ROLE`. While the "Proof of Quality" mechanism decentralizes the *work* and *validation*, the *governance* and *emergency controls* remain concentrated.

### Key Risks:
1.  **Admin OMNIPOTENCE:** The admin can upgrade any contract, change any parameter, and perform emergency withdrawals.
2.  **Oracle Dependency:** The `ValidationOracle` is the source of truth for consensus. Any bug in the pluggable consensus algorithms or the commit-reveal logic can lead to permanent loss of funds or reputation.
3.  **Governance Transparency:** There is no evidence of a multi-sig or DAO structure in the current contract code, though the `initialize` function allows any address to be set as admin.

## Mitigation Suggestions
1.  **Transition to Multi-sig:** Ensure `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` are held by a robust multi-sig (e.g., Gnosis Safe).
2.  **Timelocks:** Implement a timelock for upgrades and major parameter changes (like protocol fees).
3.  **Algorithmic Guardrails:** Further harden consensus algorithms to be whale-resistant (e.g., `HybridConsensus` with its 30% cap).
