# Quantstamp Findings Analysis

Analysis of questions raised during the Quantstamp review, with code references and severity assessments.

---

## Q2 — Origination fee calculated post-protocol-fee

**Severity: Low / Design**

In `OriginationLib.fundProject()`, the origination fee for the adapter is calculated on `remaining` (after the protocol fee is deducted), not on the original `received` amount.

```95:107:src/libraries/OriginationLib.sol
            uint256 protocolFee = (received * $.protocolFeeBps) / C.BPS;
            if (protocolFee > 0) {
                IERC20(token).safeTransfer($.treasury, protocolFee);
            }
            remaining = received - protocolFee;
        }

        {
            if (adapter != address(0) && $.originationFeeBps > 0) {
                uint256 originationFee = (remaining * $.originationFeeBps) / C.BPS;
                $.pendingRewards[adapter][token] += originationFee;
                $.originationAdapter[projectId] = adapter;
```

With `protocolFeeBps = 1000` (10%) and `originationFeeBps = 400` (4%), a 10,000 token funding yields:
- Protocol fee: 1,000
- Origination fee: 9,000 * 4% = **360** (not 400)
- Net to escrow: 8,640

**Impact**: The adapter receives a smaller fee than naively expected. If adapters are promised "4% of the funding amount," this is misleading. If they're promised "4% of what reaches the project," it's correct.

**Recommendation**: Confirm the intended behavior. If the fee should be on the gross amount, move the origination fee calculation before the protocol fee deduction. Document whichever choice is made.

---

## Q3 — `fundProject()` can be called multiple times, overwriting adapter

**Severity: Low**

`fundProject()` allows repeated calls because the status check accepts both `Created` and `Funded`:

```74:76:src/libraries/OriginationLib.sol
        if (proj.status != ProjectStatus.Created && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.InvalidProjectConfig("project not in fundable state");
        }
```

Each call overwrites the stored adapter:

```106:106:src/libraries/OriginationLib.sol
                $.originationAdapter[projectId] = adapter;
```

The accrued fees for earlier adapters are safely stored in `$.pendingRewards` and claimable. However, `getOriginationAdapter()` returns only the latest adapter, so any off-chain system relying on that view loses visibility into prior adapters.

**Impact**: Low. Funds are safe. Only the `getOriginationAdapter()` lookup is affected.

**Recommendation**: If multi-funding is intentional, document it. Consider emitting the adapter in the `ProjectFunded` event (already done) and noting that `getOriginationAdapter()` only returns the most recent. Alternatively, restrict funding to a single call or accumulate adapters.

---

## Q4 — `ReputationUpdated` event emits `oldScore` post-decay

**Severity: Informational**

In `ReputationLib.update()`, decay is applied before setting `oldScore`:

```53:64:src/libraries/ReputationLib.sol
        uint256 currentScore = rep.score;

        if ($.decayRateBps > 0) {
            uint256 elapsed = block.timestamp - rep.lastUpdated;
            if (elapsed >= 1 days) {
                uint256 decayAmount = Math.mulDiv(currentScore * $.decayRateBps, elapsed / 1 days, C.BPS);
                currentScore =
                    currentScore > decayAmount + C.MIN_REPUTATION ? currentScore - decayAmount : C.MIN_REPUTATION;
            }
        }

        uint256 oldScore = currentScore;
```

The emitted `oldScore` is the score **after** decay but **before** the success/failure adjustment. The raw stored score before decay (`rep.score`) is never surfaced in the event.

**Impact**: Off-chain indexers see the effective decayed score rather than the raw stored score. This is arguably more useful since it represents what the score "actually was" at the time of the action.

**Recommendation**: This behavior is reasonable. Document that `oldScore` in the event includes lazy decay. If raw pre-decay values are needed for analytics, consider emitting a separate `DecayApplied` event.

---

## Q5 — Vault operations revert instead of partial-filling

**Severity: Low**

All vault lock/unlock/slash operations require exact amounts and revert if insufficient:

```114:117:src/SapienVault.sol
    function lockContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);
```

The DoS concern: `availableBalance()` is `convertToAssets(balanceOf(user)) - totalLocked`. Since `convertToAssets` involves integer division (`shares * totalAssets / totalSupply`), it's subject to rounding. A donation or deposit by another user could change `totalAssets`, shifting `convertToAssets` by 1 wei, potentially causing a revert if the caller is at the exact boundary.

**Impact**: In practice, users would stake slightly more than the minimum to avoid edge cases. The ERC-4626 virtual shares offset (`_decimalsOffset = 3`) already reduces rounding impact to negligible levels. A genuine off-by-one attack would require the attacker to donate tokens or sandwich-deposit at precisely the right moment, which is economically irrational for a 1-wei impact.

**Recommendation**: The strict revert behavior is safer than partial fills (which could leave the protocol in inconsistent states). No change needed, but this is worth noting in user-facing documentation: "Ensure your vault balance exceeds the required stake by a small margin."

---

## Q6 — `minStakeToClaim` is used as an exact amount, not a minimum

**Severity: Informational**

Despite the name suggesting a minimum, `claimToContribute()` locks exactly `minStakeToClaim * quantity` — the contributor cannot choose to stake more:

```57:61:src/libraries/ContributionLib.sol
        {
            uint256 stakeRequired = proj.minStakeToClaim * quantity;
            if (stakeRequired > 0) {
                $.vault.lockContributor(msg.sender, stakeRequired);
            }
        }
```

**Impact**: Naming inconsistency. No functional issue since the same exact amount is unlocked/slashed later.

**Recommendation**: Rename to `stakePerClaim` or `contributorStake` for clarity. Alternatively, if allowing variable stakes is desired, add a `stakeAmount` parameter to `claimToContribute()` and enforce `>= minStakeToClaim`.

---

## Q7 — Originator can validate their own project

**Severity: Medium**

`claimToValidate()` prevents validating your **own contribution** (line 72) but does **not** prevent the project originator from validating other contributors' work on their project:

```69:77:src/libraries/ValidationLib.sol
        for (uint256 i; i < pendingLen; ++i) {
            uint256 idx = pending[i];
            Contribution storage contrib = $.contributions[projectId][idx];
            if (contrib.contributor == msg.sender) continue;
            uint256 nonce = $.submissionNonce[projectId][idx];
            if ($.validatorCommits[projectId][idx][nonce][msg.sender].claimed) continue;
            if ($.validationCounters[projectId][idx][nonce].claimCount >= proj.numberOfValidations) continue;
            eligible[eligibleCount++] = idx;
        }
```

The originator has financial incentive (they funded the rewards) and could bias validation scores to accept low-quality work or reject good work to reclaim funds.

**Impact**: Medium. An originator who is also a validator could manipulate consensus outcomes on their own project. However, the commit-reveal scheme and multi-validator consensus provide some mitigation — the originator would be just one of N validators.

**Recommendation**: Add a check in `claimToValidate()`:

```solidity
if (proj.originator == msg.sender) revert OriginatorCannotValidate();
```

---

## Q8 — Front-running risks

### Q8a — Project ID griefing

**Severity: Low**

`projectId` is caller-supplied. If an originator uses a predictable ID, an attacker could front-run `createProject()` with that same ID. The attacker's project would claim the ID, blocking the legitimate originator.

**Impact**: Low. The originator can simply use a different ID. Using `keccak256(abi.encodePacked(msg.sender, nonce))` or including randomness makes this impractical to exploit.

**Recommendation**: Document that originators should use non-predictable project IDs. Alternatively, derive the ID on-chain (e.g., from `msg.sender` + a counter).

### Q8b — Validators can use identical commit/reveal data

**Severity: Informational**

Commit hashes are stored per-validator (`$.validatorCommits[...][validator]`), so two validators submitting the same `(score, salt)` pair don't collide. However, colluding validators could agree on identical scores/salts off-chain.

**Impact**: Minimal. Identical scores would simply agree on consensus. The commit-reveal scheme prevents copying after commit (since reveals require the original salt). Collusion between validators is an economic concern mitigated by staking/slashing.

**Recommendation**: No code change needed. This is an inherent limitation of commit-reveal and is mitigated by the staking/reputation system.

### Q8c — Dispute front-running

**Severity: Low**

Only one dispute is allowed per `(projectId, index, nonce)`. A front-runner who observes a pending `openDispute` transaction could submit their own dispute first with the same evidence hash, becoming the challenger (and bond holder / potential reward recipient) instead.

```52:57:src/libraries/DisputeLib.sol
        Dispute storage dispute = $.disputes[projectId][index][nonce];

        // SEC-H-03: only one dispute per (projectId, index, nonce) — block reopening
        if (dispute.status == DisputeStatus.Open) revert ISapienCore.DisputeAlreadyOpen();
        if (dispute.status == DisputeStatus.Rejected || dispute.status == DisputeStatus.Upheld) {
            revert ISapienCore.DisputeAlreadyClosed();
        }
```

**Impact**: The front-runner steals the dispute slot but must also lock the bond and bear the risk of rejection (bond slashing). The legitimate evidence still gets submitted (just by a different challenger). The outcome (upheld/rejected) is unchanged.

**Recommendation**: Accept as a known trade-off. If this is a concern, consider requiring the `evidenceHash` to include `msg.sender` so the front-runner's hash would differ, or allow multiple disputes per contribution.

### Q8d — Originator report front-running

**Severity: Low**

Same pattern as Q8c. Only one open report per project. A front-runner could file a report with the same evidence hash, becoming the reporter.

**Impact**: Identical to Q8c — the front-runner assumes the bond risk. The report outcome is unchanged.

**Recommendation**: Same mitigations as Q8c.

---

## Q9 — Reputation updated before dispute phase; rollback is asymmetric

**Severity: Medium**

On consensus acceptance, the contributor receives a reputation bonus:

```336:337:src/libraries/ValidationLib.sol
            uint256 qualityBonus = (result.weightedAverage * 20) / C.BPS;
            ReputationLib.update(contrib.contributor, proj.requiredSkill, true, qualityBonus);
```

If the contribution is later disputed and the dispute is upheld, the "rollback" is a flat penalty:

```101:101:src/libraries/DisputeLib.sol
            ReputationLib.update(contrib.contributor, proj.requiredSkill, false, 0);
```

This applies `REJECTION_DECREASE = 50`, regardless of how large the bonus was. For a high consensus score (e.g., 9000), the bonus would be `9000 * 20 / 10000 = 18`, plus `SUCCESS_INCREASE = 10` = total gain of 28. The penalty of 50 actually overcorrects.

However, if time has passed, decay has altered the score, and other actions have occurred, the net effect is unpredictable. The "undo" does not account for the specific bonus previously granted.

**Impact**: Medium. A contributor who gets a large bonus from consensus and then has the result disputed gets a fixed-size penalty that doesn't correlate with the original bonus. In most cases the 50-point penalty is actually harsher than the ~28-point gain, so this works against the contributor.

**Recommendation**: Store the bonus amount granted during `computeConsensus` and apply it as the penalty on upheld dispute (instead of the flat `REJECTION_DECREASE`). Alternatively, accept the asymmetry as intentional — the flat penalty is a simpler model and the overcorrection deters low-quality submissions.

---

## Q10 — Originator self-report at a discount

**Severity: Medium**

**Attack scenario**: A misbehaving originator creates a sock-puppet address with minimal stake, calls `reportOriginator()` with a dummy `evidenceHash`, and the Operator rejects it (slashing the sock puppet's bond). The question is whether this permanently blocks future reports.

**Analysis**: After rejection, the report status is `OriginatorReportStatus.Rejected`. The guard in `reportOriginator` only blocks `Open` reports:

```165:165:src/libraries/DisputeLib.sol
        if (report.status == OriginatorReportStatus.Open) revert ISapienCore.OriginatorReportAlreadyOpen();
```

Since `Rejected != Open`, a new report **can** be filed after rejection. The attack does not permanently block reporting.

**Remaining concern**: While the sock-puppet's report is `Open` (before the Operator resolves it), new contributions are blocked:

```52:54:src/libraries/ContributionLib.sol
        if ($.originatorReports[projectId].status == OriginatorReportStatus.Open) {
            revert ISapienCore.DisputeInProgress();
        }
```

This creates a **temporary griefing vector**: the originator's accomplice files a dummy report, stalling contributions until the Operator resolves it (up to 7 days before auto-escalation). The cost to the attacker is only the report bond (`totalRewards * originatorReportBondBps / BPS`).

**Impact**: Medium. Repeated dummy reports can delay contributions. Each costs the attacker a bond, but the bond may be small relative to the disruption caused.

**Recommendation**: Consider:
1. Adding a cooldown after rejected reports before new ones can be filed
2. Increasing the bond for subsequent reports on the same project
3. Adding a check that prevents re-reporting by the same address after rejection
4. Adding an `Upheld`/`Rejected` check alongside the `Open` check to prevent re-reporting entirely (if one report per project is the intended design)

---

## Q11 — Contributor reputation bonus not fully reversed on upheld dispute

**Severity: Medium**

This is closely related to Q9. When `computeConsensus()` accepts a contribution, the contributor gets:

```solidity
SUCCESS_INCREASE (10) + qualityBonus (up to 20)
```

When `upholdDispute()` is called on an accepted contribution, the contributor gets:

```solidity
REJECTION_DECREASE (50)
```

The penalty does not consider the original bonus. Additionally, `ReputationLib.update()` applies time-based decay before each adjustment, so the reputation state at dispute time is not the same as at consensus time.

**Example timeline**:
1. Consensus: score 5000 + 28 bonus → score = 5028
2. 3 days pass, decay applied
3. Another action modifies score
4. Dispute upheld: score - 50, but the starting point is already different

The result is that the net reputation change from "accepted then disputed" is not equivalent to "never accepted."

**Impact**: Medium. The reputation system does not maintain exact reversibility, which could be exploited by repeatedly getting contributions accepted (gaining reputation) and having accomplices dispute them (known fixed penalty).

**Recommendation**: Either:
- Store the granted bonus per contribution and reverse it specifically on upheld dispute
- Accept the asymmetry and document it as intended design (the flat 50-point penalty acts as a deterrent and is typically larger than the bonus)

---

## Summary

| Finding | Severity | Action Required |
|---------|----------|-----------------|
| Q2 — Origination fee basis | Low | Confirm intent, document |
| Q3 — Multi-fund adapter overwrite | Low | Document or restrict |
| Q4 — `oldScore` includes decay | Informational | Document |
| Q5 — Vault strict reverts | Low | No change needed |
| Q6 — `minStakeToClaim` naming | Informational | Consider rename |
| Q7 — Originator can validate own project | Medium | Add originator check |
| Q8a — Project ID griefing | Low | Document best practices |
| Q8b — Identical validator commits | Informational | No change needed |
| Q8c — Dispute front-running | Low | Accept or add `msg.sender` to hash |
| Q8d — Report front-running | Low | Accept or add `msg.sender` to hash |
| Q9 — Asymmetric reputation rollback | Medium | Store bonus or document |
| Q10 — Report griefing via sock puppet | Medium | Add cooldown or escalating bond |
| Q11 — Bonus not reversed on dispute | Medium | Store bonus or document |
