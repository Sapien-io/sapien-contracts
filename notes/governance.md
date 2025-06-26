# Sapien Protocol Governance & Access Control

This document provides a comprehensive overview of the governance structure, role assignments, and access control across the Sapien protocol smart contracts.

---

## Table of Contents
1. [Multisig Architecture](#multisig-architecture) 
2. [Smart Contract Roles](#smart-contract-roles)
3. [Actor-to-Role Mapping](#actor-to-role-mapping)
4. [Role Privileges by Contract](#role-privileges-by-contract)
5. [Token Allocations](#token-allocations)
6. [Deployment Addresses](#deployment-addresses)

---

## Multisig Architecture

| **Entity**            | **Type**        | **Threshold**    | **Primary Responsibilities**                |
|-----------------------|-----------------|------------------|---------------------------------------------|
| Foundation Safe #1    | Safe Multisig   | 3 of 5           | Core foundation treasury & protocol admin   |
| Foundation Safe #2    | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Foundation Safe #3    | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Corp Treasury         | Safe Multisig   | 4 of 7           | Investor allocations & team compensation    |
| Blended MS            | Safe Multisig   | 3 of 3           | 2 Foundation + 1 Corp signer                |
| Security Council      | Safe Multisig   | 2 of 3           | Corp Engineering Team                       |

---

## Smart Contract Roles

### Global Roles (Cross-Contract)
| **Role**              | **Purpose**                                      | **Used In**                    |
|-----------------------|--------------------------------------------------|--------------------------------|
| `DEFAULT_ADMIN_ROLE`  | Ultimate admin control, can grant/revoke roles   | All contracts                  |
| `PAUSER_ROLE`         | Emergency pause/unpause functionality            | SapienRewards, SapienVault     |

### Contract-Specific Roles
| **Role**              | **Purpose**                                      | **Contract**                   |
|-----------------------|--------------------------------------------------|--------------------------------|
| `REWARD_ADMIN_ROLE`   | Manage reward deposits/withdrawals               | SapienRewards                  |
| `REWARD_MANAGER_ROLE` | Sign reward claims for users                     | SapienRewards                  |
| `SAPIEN_QA_ROLE`      | Process QA penalties on user stakes              | SapienVault                    |
| `QA_MANAGER_ROLE`     | Execute QA decisions with signatures             | SapienQA                       |
| `QA_SIGNER_ROLE`      | Create signatures for QA decisions               | SapienQA                       |

---

## Actor-to-Role Mapping

### Primary Actor Assignments

| **Actor**             | **Contract**    | **Role(s)**                  | **Description**                     |
|-----------------------|-----------------|------------------------------|-------------------------------------|
| Foundation Safe #1    | All             | `DEFAULT_ADMIN_ROLE`         | Protocol governance & upgrades      |
| Security Council      | All             | `PAUSER_ROLE`                | Emergency response capability       |
| Rewards Admin         | SapienRewards   | `REWARD_ADMIN_ROLE`          | Treasury management for rewards     |
| Rewards Manager       | SapienRewards   | `REWARD_MANAGER_ROLE`        | Off-chain reward calculation signer |
| QA Manager            | SapienQA        | `QA_MANAGER_ROLE`            | Execute quality assessments         |
| QA Signer             | SapienQA        | `QA_SIGNER_ROLE`             | Authorize QA decisions              |
| SapienQA Contract     | SapienVault     | `SAPIEN_QA_ROLE`             | Apply penalties to user stakes      |

### Timelock Roles
| **Actor**             | **Entity**           | **Purpose**                                  |
|-----------------------|----------------------|----------------------------------------------|
| Timelock Proposer     | Security Council     | Propose contract upgrades to ProxyAdmins     |
| Timelock Executor     | Foundation Safe #1   | Execute approved changes after delay         |
| Timelock Admin        | Blended MS           | Manage timelock configuration                |

---

## Role Privileges by Contract

### SapienToken
| **Role**              | **Privileges**                                   |
|-----------------------|--------------------------------------------------|
| `NONE`                | The Token contract is immutable                  |

### SapienVault
| **Role**              | **Privileges**                                   |
|-----------------------|--------------------------------------------------|
| `DEFAULT_ADMIN_ROLE`  | • Set treasury address<br>• Set maximum stake amount<br>• Emergency withdraw (when paused)<br>• Grant/revoke roles |
| `PAUSER_ROLE`         | • Pause all staking/unstaking operations<br>• Unpause contract |
| `SAPIEN_QA_ROLE`      | • Process QA penalties on user stakes<br>• Reduce user stake amounts |

### SapienRewards
| **Role**              | **Privileges**                                   |
|-----------------------|--------------------------------------------------|
| `DEFAULT_ADMIN_ROLE`  | • Set reward token<br>• Grant/revoke roles      |
| `PAUSER_ROLE`         | • Pause reward claims<br>• Unpause contract     |
| `REWARD_ADMIN_ROLE`   | • Deposit reward tokens<br>• Withdraw reward tokens<br>• Recover unaccounted tokens<br>• Reconcile balance |
| `REWARD_MANAGER_ROLE` | • Sign reward claims (off-chain)<br>• Cannot claim rewards themselves |

### SapienQA
| **Role**              | **Privileges**                                   |
|-----------------------|--------------------------------------------------|
| `DEFAULT_ADMIN_ROLE`  | • Set treasury address<br>• Set vault contract<br>• Grant/revoke roles |
| `QA_MANAGER_ROLE`     | • Process quality assessments with valid signatures<br>• Apply warnings and penalties |
| `QA_SIGNER_ROLE`      | • Create EIP-712 signatures for QA decisions (off-chain) |

---

## Token Allocations

| **Category**          | **Allocation %** | **Controlled By**    | **Vesting/Notes**               |
|-----------------------|------------------|----------------------|---------------------------------|
| Foundation Treasury   | 13%              | Foundation Safe #1   | Strategic reserves              |
| Airdrops              | 13%              | Foundation Safe #1   | Community distribution          |
| Trainer Compensation  | 15%              | Foundation Safe #1   | AI trainer rewards              |
| Liquidity Incentives  | 12% (5% + 7%)    | Foundation Safe #1   | DEX/AMM incentives              |
| Investors             | 30.45%           | Corp Treasury        | Subject to vesting schedules    |
| Team & Advisors       | 16.55%           | Corp Treasury        | Subject to vesting schedules    |

---

## Deployment Addresses

### MAINNET multisigs (Base - Chain ID: 8453)
| **Contract**          | **Address**                                      |
|-----------------------|--------------------------------------------------|
| Foundation Safe #1    | `TBD`                                            |
| Foundation Safe #2    | `TBD`                                            |
| Foundation Safe #3    | `TBD`                                            |
| Corp Treasury         | `TBD`                                            |
| Blended MS            | `TBD`                                            |
| Security Council      | `TBD`                                            |

### MAINNET protocol (Base - Chain ID: 8453)
| **Contract**          | **Address**                                      |
|-----------------------|--------------------------------------------------|
| SapienToken           | `TBD`                                            |
| SapienVault           | `TBD`                                            |
| SapienRewards         | `TBD`                                            |
| SapienQA              | `TBD`                                            |
| Timelock              | `TBD`                                            |

### TESTNET multisigs (Base Sepolia - Chain ID: 84532)
| **Contract**          | **Address**                                      |
|-----------------------|--------------------------------------------------|
| Core Team Admin       | [`0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC`](https://sepolia.basescan.org/address/0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC)     |

### TESTNET protocol (Base Sepolia - Chain ID: 84532)
| **Contract**          | **Address**                                      |
|-----------------------|--------------------------------------------------|
| SapienToken           | [`0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6`](https://sepolia.basescan.org/address/0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6)     |
| SapienVault           | [`0xBCC5e0913B3df10b08C88dea87F396Dc95cAd385`](https://sepolia.basescan.org/address/0xBCC5e0913B3df10b08C88dea87F396Dc95cAd385)     |
| SapienRewards         | [`0xFF443d92F80A12Fb7343bb16d44df60204c6eB08`](https://sepolia.basescan.org/address/0xFF443d92F80A12Fb7343bb16d44df60204c6eB08)     |
| SapienQA              | [`0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF`](https://sepolia.basescan.org/address/0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF)     |
| Timelock              | [`0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC`](https://sepolia.basescan.org/address/0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC)     |

---

## 🔄 Governance Processes

### Protocol Upgrades
1. **Proposal**: Managed by Corp, with influence from stakeholders and community
2. **Review**: Technical and security review by core team
3. **Timelock**: Changes queued with appropriate delay
4. **Execution**: After timelock delay, changes executed by authorized executors

### Emergency Response
1. **Detection**: Issue identified by monitoring or community
2. **Pause**: Security Council can immediately pause affected contracts
3. **Assessment**: Technical team evaluates severity and solutions
4. **Resolution**: Fix implemented through normal or emergency procedures
5. **Unpause**: Contracts resumed after verification

### Role Management
- **Adding Roles**: Only `DEFAULT_ADMIN_ROLE` can grant new roles
- **Removing Roles**: Only `DEFAULT_ADMIN_ROLE` can revoke roles
- **Role Renunciation**: Role holders can renounce their own roles
- **Admin Transfer**: Requires multi-step process with timelock

### Separation of Concerns
- **Signing vs Execution**: QA and Rewards separate signature creation from execution
- **Admin vs Operations**: Day-to-day operations separated from admin functions
- **Pause vs Admin**: Emergency pause separated from administrative control

---

## 📞 Contact & Resources

- **Governance Forum**: TBD
- **Documentation**: https://docs.sapien.io
- **Contracts Audit**: TBD
- **Bug Bounty**: TBD

---

*Last Updated: June 26 2025*