// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct StakeAccount {
    uint256 lockedAmount;
}

/// @notice A cohort of shares that entered an address at `startTime` and is
///         still inside the `minDepositAge` window. Packs into a single slot.
struct Tranche {
    uint128 shares;
    uint64 startTime;
}

struct SapienVaultStorage {
    mapping(address => StakeAccount) accounts;
    // Deprecated by the tranche model (SAP-1): retained read-only so the
    // lazy upgrade migration can seed each user's pre-upgrade age. No longer
    // written after the tranche refactor.
    mapping(address => uint256) lastDepositTimestamp;
    uint256 minDepositAge;
    // ── Tranche accounting (appended; ERC-7201 slot unchanged) ──────────
    // Shares that have cleared `minDepositAge` and are freely actionable.
    mapping(address => uint256) matureShares;
    // FIFO ring buffer of immature cohorts, indexed [head, tail).
    mapping(address => mapping(uint256 => Tranche)) immature;
    mapping(address => uint256) immatureHead;
    mapping(address => uint256) immatureTail;
    // Set once a user's balance has been migrated into the tranche model.
    mapping(address => bool) migrated;
    // Minimum asset amount for a new immature tranche when `minDepositAge > 0`.
    // Sub-threshold mints revert, blocking dust-deposit griefing. Zero disables.
    uint256 minTrancheSize;
}
