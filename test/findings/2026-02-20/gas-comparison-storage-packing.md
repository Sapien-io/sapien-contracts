# EngineStorage Packing Gas Comparison

**Date:** 2026-02-21  
**Branch (packed):** `v0.5`  
**Branch (unpacked):** `experiment/unpacked-storage`  
**Method:** `forge test --gas-report`

## What Was Changed

The `EngineStorage` struct fields were expanded from packed types to full `uint256` slots:

| Field | Packed Type | Unpacked Type |
|-------|-------------|---------------|
| `protocolFeeBps` | `uint16` | `uint256` |
| `originationFeeBps` | `uint16` | `uint256` |
| `contributionFeeBps` | `uint16` | `uint256` |
| `validationFeeBps` | `uint16` | `uint256` |
| `decayRateBps` | `uint16` | `uint256` |
| `disputeBondBps` | `uint16` | `uint256` |
| `originatorReportBondBps` | `uint16` | `uint256` |
| `originatorStakeRequirement` | `uint128` | `uint256` |
| `minValidationStake` | `uint128` | `uint256` |
| `minClaimAmount` | `uint64` | `uint256` |
| `claimCooldown` | `uint64` | `uint256` |
| `lastClaimTime` mapping | `uint64` | `uint256` |

**Slots used for scalar fields:** Packed = ~5 slots → Unpacked = ~13 slots (+8 slots)

---

## Deployment

| Metric | Packed | Unpacked | Diff |
|--------|--------|----------|------|
| Deployment Cost | 3,459,910 | 3,453,312 | **-6,598** (-0.19%) |
| Deployment Size | 15,765 | 15,735 | **-30 bytes** |

> Unpacked is marginally cheaper to deploy (less bit-masking code).

---

## Core Operations (Avg Gas)

| Function | Packed | Unpacked | Diff | Packing Saves |
|----------|--------|----------|------|---------------|
| **initialize** | 163,709 | 294,810 | +131,101 | **80.1%** |
| **fundProject** | 243,358 | 244,978 | +1,620 | **0.67%** |
| **computeConsensus** | 291,615 | 293,189 | +1,574 | **0.54%** |
| **settleValidator** | 124,339 | 125,877 | +1,538 | **1.24%** |
| **claimReward** | 43,224 | 45,190 | +1,966 | **4.55%** |
| **cancelExpiredCommitment** | 102,383 | 104,328 | +1,945 | **1.90%** |
| **escalateDispute** | 55,305 | 56,299 | +994 | **1.80%** |
| **escalateOriginatorReport** | 51,713 | 52,707 | +994 | **1.92%** |
| **resolveDispute** | 90,147 | 91,340 | +1,193 | **1.32%** |
| **resolveOriginatorReport** | 77,681 | 78,697 | +1,016 | **1.31%** |
| **forceSettleValidator** | 92,297 | 93,624 | +1,327 | **1.44%** |
| createProject | 127,626 | 127,566 | -60 | ~0% |
| claimToContribute | 212,934 | 212,874 | -60 | ~0% |
| contribute | 135,537 | 135,534 | -3 | ~0% |
| commitValidation | 141,657 | 141,535 | -122 | ~0% |
| revealValidation | 68,413 | 68,419 | +6 | ~0% |
| openDispute | 111,027 | 111,018 | -9 | ~0% |
| reportOriginator | 104,677 | 104,713 | +36 | ~0% |
| releaseContributorReward | 72,117 | 71,850 | -267 | -0.37% |
| completeProject | 24,741 | 24,762 | +21 | ~0% |
| refundEscrow | 26,102 | 26,088 | -14 | ~0% |
| expireClaim | 220,142 | 217,676 | -2,466 | -1.12% |

---

## View Functions (Avg Gas)

| Function | Packed | Unpacked | Diff | Packing Saves |
|----------|--------|----------|------|---------------|
| **getAdapterFees** | 3,208 | 7,329 | +4,121 | **128.5%** |
| **getDisputeConfig** | 5,714 | 7,703 | +1,989 | **34.8%** |
| treasury | 2,838 | 2,860 | +22 | 0.78% |
| getPendingRewards | 3,274 | 3,296 | +22 | 0.67% |
| getReputation | 4,383 | 4,405 | +22 | 0.50% |
| getProjectEscrow | 3,230 | 3,252 | +22 | 0.68% |
| getOriginatorLockedStake | 3,166 | 3,188 | +22 | 0.70% |

> `getAdapterFees` reads 3 fee bps values. Packed: 1 SLOAD (same slot). Unpacked: 3 SLOADs. ~4,100 gas difference.

---

## Admin Setters (Max Gas)

| Function | Packed | Unpacked | Diff | Notes |
|----------|--------|----------|------|-------|
| setProtocolFee | 9,141 | 9,086 | **-55** | Unpacked cheaper |
| setOriginationFee | 9,229 | 9,174 | **-55** | Unpacked cheaper |
| setContributionFee | 9,075 | 9,020 | **-55** | Unpacked cheaper |
| setValidationFee | 9,031 | 8,976 | **-55** | Unpacked cheaper |
| setDecayRate | 8,520 | 8,443 | **-77** | Unpacked cheaper |
| setDisputeBondBps | 9,361 | 9,306 | **-55** | Unpacked cheaper |
| setOriginatorReportBondBps | 8,762 | 8,685 | **-77** | Unpacked cheaper |
| setMinValidationStake | 25,721 | 25,584 | **-137** | Unpacked cheaper |
| setOriginatorStakeRequirement | 26,235 | 26,117 | **-118** | Unpacked cheaper |

> All admin setters are slightly cheaper WITHOUT packing (~55-137 gas each) because writing a full `uint256` slot avoids the read-modify-write (SLOAD + mask + SSTORE) needed for packed fields.

---

## Summary

### Where Packing Helps Most
1. **`initialize`** — 131,101 gas saved (80%), but only called once per deployment
2. **`getAdapterFees`** — 4,121 gas saved (128%) per call (reads 3 co-located fee fields in 1 SLOAD)
3. **`getDisputeConfig`** — 1,989 gas saved (35%) per call (reads 3 co-located config fields)
4. **`claimReward`** — 1,966 gas saved (4.5%) per call (reads `minClaimAmount` + `claimCooldown`)
5. **`cancelExpiredCommitment`** — 1,945 gas saved (1.9%) per call
6. **`fundProject`** — 1,620 gas saved (0.67%) per call (reads `protocolFeeBps` + `originationFeeBps`)
7. **`computeConsensus`** — 1,574 gas saved (0.54%) per call (reads `decayRateBps`)
8. **`settleValidator`** — 1,538 gas saved (1.24%) per call

### Where Packing Hurts (or is Neutral)
- **Admin setters** — Packing costs 55-137 extra gas per write (read-modify-write overhead)
- **`expireClaim`** — Packing costs 2,466 extra gas per call (1.12%)
- **Most write-heavy operations** — Near zero impact (within noise)
- **Deployment** — Packing costs ~6,598 extra gas (more bit-manipulation code)

### Net Assessment

Storage packing in `EngineStorage` provides **meaningful savings for read-heavy operations** that access multiple co-located fields (especially `getAdapterFees` at 128% savings). For the hot-path state-changing operations (`fundProject`, `computeConsensus`, `settleValidator`, `claimReward`), savings are modest at **0.5%–4.5%** per call.

The admin setter overhead is negligible since those are rarely called. The `initialize` savings are large but one-time.

**Verdict: Keep the packing.** The ~2,000 gas savings per `fundProject`/`settleValidator`/`claimReward` call adds up at scale, and the view function savings (128% for `getAdapterFees`) are significant. The admin setter cost is the only downside and is operationally irrelevant.
