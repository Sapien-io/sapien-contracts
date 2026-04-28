// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct StakeAccount {
    uint256 lockedAmount;
}

struct SapienVaultStorage {
    mapping(address => StakeAccount) accounts;
    mapping(address => uint256) lastDepositTimestamp;
    uint256 minDepositAge;
}
