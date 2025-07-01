# Sapien Protocol Governance & Access Control

This document provides an overview of the governance structure, role assignments, and access control across the Sapien protocol smart contracts.

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

| **Multisig**          | **Type**        | **Threshold**    | **Primary Responsibilities**                |
|-----------------------|-----------------|------------------|---------------------------------------------|
| Foundation Safe #1    | Safe Multisig   | 3 of 5           | Core foundation treasury & protocol admin   |
| Foundation Safe #2    | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Foundation Safe #3    | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Corp Treasury         | Safe Multisig   | 4 of 7           | Investor allocations & team compensation    |
| Blended MS            | Safe Multisig   | 3 of 3           | 2 Foundation + 1 Corp signer                |
| Security Council      | Safe Multisig   | 2 of 5           | Corp Engineering Team                       |

---

## Smart Contract Roles

### Global Roles (Cross-Contract)
| **Role**              | **Purpose**                                      | **Used In**                       |
|-----------------------|--------------------------------------------------|-----------------------------------|
| `DEFAULT_ADMIN_ROLE`  | Ultimate admin control, can grant/revoke roles   | All contracts                     |
| `PAUSER_ROLE`         | Emergency pause/unpause functionality            | SapienRewards, SapienVault        |

### Contract-Specific Roles
| **Role**              | **Purpose**                                      | **Contract**                      |
|-----------------------|--------------------------------------------------|-----------------------------------|
| `REWARD_ADMIN_ROLE`   | Manage rewards, deposits/withdrawals             | SapienRewards                     |
| `REWARD_MANAGER_ROLE` | Sign reward claims for users                     | SapienRewards                     |
| `SAPIEN_QA_ROLE`      | Process QA penalties on user stakes              | SapienVault                       |
| `QA_MANAGER_ROLE`     | Execute QA decisions with signatures             | SapienQA                          |
| `QA_SIGNER_ROLE`      | Create signatures for QA decisions               | SapienQA                          |
| `TIMELOCK_ADMIN`      | Manage Timelock role assignments                 | TimelockController                |
| `TIMELOCK_PROPOSER`   | Propose Contract Upgrade Tx                      | TimelockController                |
| `TIMELOCK_EXECUTOR`   | Executor Contract Upgrade Tx                     | TimelockController                |
| `TIMELOCK_CANCELLOR`  | Cancel Contract Upgrade Tx                       | TimelockController                |

---

## Actor-to-Role Mapping

### Primary Actor Assignments

| **Actor**             | **Contract**    | **Role(s)**                  | **Control Assingment**              |
|-----------------------|-----------------|------------------------------|-------------------------------------|
| Default Admin         | All             | `DEFAULT_ADMIN_ROLE`         | Foundation Safe #1                  |
| Pauser                | All             | `PAUSER_ROLE`                | Security Council                    |
| Rewards Admin         | SapienRewards   | `REWARD_ADMIN_ROLE`          | Corp Treasury                       |
| Rewards Manager       | SapienRewards   | `REWARD_MANAGER_ROLE`        | Rewards Manager Key                 |
| QA Manager            | SapienQA        | `QA_MANAGER_ROLE`            | QA Manager Key                      |
| QA Signer             | SapienQA        | `QA_SIGNER_ROLE`             | Security Council                    |
| Sapien QA             | SapienVault     | `SAPIEN_QA_ROLE`             | SapienQA Contract                   |
| Timelock Admin        | Timelock        | `TIMELOCK_ADMIN`             | Foundation Safe #1                  |
| Timelock Proposer     | Timelock        | `TIMELOCK_PROPOSER`          | Security Council                    |
| Timelock Executor     | Timelock        | `TIMELOCK_EXECUTOR`          | Corp Treasury                       |
| Timelock Cancellor    | Timelock        | `TIMELOCK_CANCELLOR`         | Security Council                    |

---

## Token Allocations

| **Category**          | **Allocation %** | **Controlled By**          | **Vesting/Notes**                    |
|-----------------------|------------------|----------------------------|--------------------------------------|
| Foundation Treasury   | 13%              | Foundation #1              | Strategic reserves                   |
| Airdrops              | 13%              | Corp Treasury              | Community distribution               |
| Trainer Compensation  | 15%              | Corp Treasury              | AI trainer rewards                   |
| Liquidity Incentives  | 12% (5% + 7%)    | Corp Treasury              | CEXs, Market Makers, DEX/AMM         |
| Investors             | 30.45%           | Foundation #1              | Subject to vesting schedules         |
| Team & Advisors       | 16.55%           | Foundation #1              | Subject to vesting schedules         |


---


## Deployment Addresses

### MAINNET multisigs (Base - Chain ID: 8453)
| **Contract**          | **Address**                                                                          |
|-----------------------|--------------------------------------------------------------------------------------|
| Foundation Safe #1    | `TBD`                                                                                |
| Foundation Safe #2    | `TBD`                                                                                |
| Foundation Safe #3    | `TBD`                                                                                |
| Corp Treasury         | `TBD`                                                                                |
| Blended MS            | `TBD`                                                                                |
| Security Council      | `TBD`                                                                                |

### MAINNET protocol (Base - Chain ID: 8453)
| **Contract**          | **Address**                                                                          |
|-----------------------|--------------------------------------------------------------------------------------|
| SapienToken           | `TBD`                                                                                |
| SapienVault           | `TBD`                                                                                |
| SapienRewards         | `TBD`                                                                                |
| SapienQA              | `TBD`                                                                                |
| Timelock              | `TBD`                                                                                |


### TESTNET multisigs (Base Sepolia - Chain ID: 84532)
| **Contract**          | **Address**                                                                          |
|-----------------------|--------------------------------------------------------------------------------------|
| Core Team Admin       | [`0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC`](https://sepolia.basescan.org/address/0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC)     |


### TESTNET protocol (Base Sepolia - Chain ID: 84532)
| **Contract**          | **Address**                                                                          |
|-----------------------|--------------------------------------------------------------------------------------|
| SapienToken           | [`0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6`](https://sepolia.basescan.org/address/0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6)     |
| SapienVault           | [`0xBCC5e0913B3df10b08C88dea87F396Dc95cAd385`](https://sepolia.basescan.org/address/0xBCC5e0913B3df10b08C88dea87F396Dc95cAd385)     |
| SapienRewards         | [`0xFF443d92F80A12Fb7343bb16d44df60204c6eB08`](https://sepolia.basescan.org/address/0xFF443d92F80A12Fb7343bb16d44df60204c6eB08)     |
| SapienQA              | [`0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF`](https://sepolia.basescan.org/address/0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF)     |
| Timelock              | [`0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC`](https://sepolia.basescan.org/address/0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC)     |


---

## Governance Processes

### Protocol Upgrades
1. **Proposal**: Managed by Corp on behalf of Foundation with influence from stakeholders and community
2. **Review**: Technical and security reviews by third parties and core team
3. **Timelock**: Changes queued with a proposal with 48 hour delay
4. **Execution**: After timelock delay, changes executed by authorized executors
5. **Cancelled**: Proposals may be cancelled if required during 48 hour timelock

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

## Contact & Resources

- **Governance Forum**: TBD
- **Documentation**: https://docs.sapien.io
- **Contracts Repo**: https://github.com/sapien-io/sapien-contracts
- **Contracts Audit**: TBD
- **Bug Bounty**: TBD

---

*Last Updated: July 1 2025*