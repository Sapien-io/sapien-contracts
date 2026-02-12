# Audit Review Focus: Sapien V2 Security Fixes

The recent changes in `src/` implement several security fixes (Opus 4.6 series). These areas require close attention during the audit to ensure the fixes are robust and do not introduce new vulnerabilities.

## 1. Storage Layout & Upgradeability (High Priority)
- **SapienCore.sol**: Verify the storage slot alignment. The insertion of `userActiveClaimedQuantity` appears to shift subsequent variables, which is a major upgrade risk.
- **ValidationOracle.sol**: Verify the `ValidationCommit` struct change. Adding `revealDeadlineSnapshot` to the middle of the struct changes its layout. While safe for new entries in storage, it should be checked for any off-chain or on-chain decoding implications.
- **Gap Management**: Re-calculate the expected gap size for all upgradeable contracts (`SapienCore`, `ValidationOracle`, `Rewards`, etc.) to ensure a consistent total slot count (typically 50).

## 2. Slot Starvation & Counter Tracking (Medium Priority)
- **User Claim Limits**: Review `userActiveClaimedQuantity` tracking in `SapienCore.sol`.
    - Is it correctly decremented in `reclaimExpiredIndices`, `releaseExpiredClaim`, and `_contribute`?
    - Are there any paths (e.g., error reverts in batch operations) where the counter could get out of sync?
    - Can a user "self-grief" by letting claims expire and not having them reclaimed, or can others reclaim them for the user?

## 3. Anti-Dilution Logic (Medium Priority)
- **Funding Math**: Review `_fundProject` in `SapienCore.sol`.
    - Verify that the dilution check `rewardAmountAfterFee * project.state.totalQuantityAvailable < project.state.totalRewardsAvailable * quantity` is safe from overflow and correctly implements the "non-decreasing reward rate" rule.
    - Check interaction with `MIN_REWARD_PER_SLOT`.

## 4. Oracle Reveal Deadline Snapshot (Medium Priority)
- **Deadline Integrity**: Review `_commitValidationWithStake` and `_revealValidation` in `ValidationOracle.sol`.
    - Does the snapshot correctly prevent an originator from shortening the deadline *after* a validator has committed?
    - Is the fallback to `settings.revealDeadline` (when snapshot is 0) correctly handled for legacy commits that don't have a snapshot?

## 5. Access Control & One-Time Settings (Low Priority)
- **Rewards.sol**: Verify `setCore` one-time-set logic to prevent compromised admins from hijacking the reward pool.
- **ValidationOracle.sol**: Verify `onlyCoreOrAdmin` modifier on administrative and state-changing functions.
- **Vault Pausing**: Verify `deposit` and `mint` overrides in `SapienVault.sol` correctly prevent new capital entry during emergency pause.

## 6. Precision & Fee-on-Transfer (Low Priority)
- **SapienCore.sol**: Verify the fix for fee-on-transfer tokens in `_fundProject` (using balance checks to update `totalRewardsAvailable`).
- **Custom Errors**: The transition from string reverts to custom errors (`ProtocolFeeTooHigh`, `ConsensusThresholdOutOfRange`, etc.) should be checked for consistency across the codebase.
