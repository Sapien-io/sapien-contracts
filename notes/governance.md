# Sapien Protocol Governance & Access Control

This document provides an overview of the governance structure, role assignments, and access control across the Sapien protocol smart contracts.

---

## Table of Contents
- [Sapien Protocol Governance \& Access Control](#sapien-protocol-governance--access-control)
  - [Table of Contents](#table-of-contents)
  - [Multisig Architecture](#multisig-architecture)
  - [Smart Contract Roles](#smart-contract-roles)
    - [Global Roles (Cross-Contract)](#global-roles-cross-contract)
    - [Contract-Specific Roles](#contract-specific-roles)
  - [Actor-to-Role Mapping](#actor-to-role-mapping)
    - [Primary Actor Assignments](#primary-actor-assignments)
  - [Token Allocations](#token-allocations)

---

## Multisig Architecture

| **Multisig**          | **Type**        | **Threshold**    | **Primary Responsibilities**                |
|-----------------------|-----------------|------------------|---------------------------------------------|
| Foundation One        | Safe Multisig   | 3 of 5           | Core foundation treasury & protocol admin   |
| Foundation Two        | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Foundation Three      | Safe Multisig   | 2 of 3           | Satellite foundation operations             |
| Corp Treasury         | Safe Multisig   | 4 of 7           | Investor allocations & team compensation    |
| Blended MS            | Safe Multisig   | 3 of 3           | 2 Foundation + 1 Corp signer                |
| Security Council      | Safe Multisig   | 2 of 5           | Corp Engineering Team                       |

| **Multisig            | address                                                                         |
|-----------------------|---------------------------------------------------------------------------------|
| Foundation One        |[0x0e8b34E70AA583D937e5bF407738f2C8fF4D371C](https://app.safe.global/home?safe=base:0x0e8b34E70AA583D937e5bF407738f2C8fF4D371C) |
| 

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
| Default Admin         | All             | `DEFAULT_ADMIN_ROLE`         | Blended MS                          |
| Pauser                | All             | `PAUSER_ROLE`                | Security MS                         |
| Rewards Admin         | SapienRewards   | `REWARD_ADMIN_ROLE`          | Corp MS                             |
| Rewards Manager       | SapienRewards   | `REWARD_MANAGER_ROLE`        | Rewards Manager Key                 |
| QA Manager            | SapienQA        | `QA_MANAGER_ROLE`            | QA Manager Key                      |
| QA Signer             | SapienQA        | `QA_SIGNER_ROLE`             | Security MS                         |
| Sapien QA             | SapienVault     | `SAPIEN_QA_ROLE`             | SapienQA Contract                   |
| Timelock Admin        | Timelock        | `TIMELOCK_ADMIN`             | Blended MS                          |
| Timelock Proposer     | Timelock        | `TIMELOCK_PROPOSER`          | Security MS                         |
| Timelock Executor     | Timelock        | `TIMELOCK_EXECUTOR`          | Corp MS                             |
| Timelock Cancellor    | Timelock        | `TIMELOCK_CANCELLOR`         | Security MS                         |

---

## Token Allocations

| **Category**          | **Allocation %** | **Controlled By**          | **Vesting/Notes**                    |
|-----------------------|------------------|----------------------------|--------------------------------------|
| Foundation Treasury   | 13%              | Foundation One             | Strategic reserves                   |
| Airdrops              | 13%              | Corp MS                    | Community distribution               |
| Trainer Compensation  | 15%              | Corp MS                    | AI trainer rewards                   |
| Liquidity Incentives  | 12% (5% + 7%)    | Corp MS                    | CEXs, Market Makers, DEX/AMM         |
| Investors             | 30.45%           | Corp MS                    | Subject to vesting schedules         |
| Team & Advisors       | 16.55%           | Corp MS                    | Subject to vesting schedules         |
