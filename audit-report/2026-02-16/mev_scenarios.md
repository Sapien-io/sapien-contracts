# Sapien PoQ v0.5 — MEV Attack Playbooks

## Overview

This document contains detailed attacker playbooks for economically exploiting the Sapien PoQ v0.5 protocol. Each scenario includes prerequisite conditions, step-by-step execution, profit extraction mechanisms, risk analysis, and mitigation considerations.

## Scenario 1: Project Funding Index Arbitrage (Sandwich Attack)

### Prerequisites
- Access to high-frequency trading infrastructure
- Mempool monitoring capabilities
- Sufficient capital for index claiming (minStakeToClaim × quantity)
- Target projects with high rewardRate values

### Attack Setup
```solidity
// Attacker contract for automated execution
contract IndexArbitrageBot {
    ISapienPoQ public immutable poq;
    address public immutable attacker;

    struct PendingFund {
        bytes32 projectId;
        uint256 amount;
        uint256 quantity;
        address adapter;
        uint256 gasPrice;
    }

    mapping(bytes32 => PendingFund) public pendingFunds;
}
```

### Step-by-Step Execution

#### Phase 1: Mempool Surveillance
```
1. Monitor Ethereum mempool for fundProject transactions
2. Parse transaction data to extract:
   - projectId
   - amount (reward pool size)
   - quantity (number of indices)
   - adapter address
3. Calculate potential profit: (rewardRate × quantity) × MEV extraction %
4. If profitable (> gas costs + opportunity costs), proceed to Phase 2
```

#### Phase 2: Front-Run Index Claiming
```
1. Submit claimToContribute transaction with higher gas price
   - quantity = target quantity (claim all available indices)
   - adapter = attacker's adapter for fee extraction
   - gasPrice = victim's gasPrice × 1.5

2. Transaction parameters:
   function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
   returns (uint256 claimId, uint256[] memory indices)

3. Verify claimed indices 0 to (quantity-1) (most valuable)
```

#### Phase 3: Funding Confirmation
```
1. Wait for victim's fundProject transaction to confirm
2. Verify project status == FUNDED
3. Confirm indices are locked to attacker's claim
```

#### Phase 4: Profit Extraction
```
1. Submit work for claimed indices (minimal quality to pass basic checks)
2. Wait for validation and consensus periods
3. Collect rewards through claimReward()
4. Extract adapter fees through attacker's adapter contract
```

### Profit Calculation
```
Base Profit = (rewardRate × claimedIndices) × (1 - validatorFeeBps/10000)
Adapter Fee = (Base Profit × contributionFeeBps/10000)
Total Profit = Base Profit + Adapter Fee
Net Profit = Total Profit - Gas Costs - Stake Losses
```

### Risk Analysis
- **High Risk**: Victim increases gas price, causing failed front-run
- **Medium Risk**: Network congestion delays execution
- **Low Risk**: Protocol changes (mitigated by monitoring)
- **Opportunity Cost**: Capital locked in stake during attack window

### Mitigation Impact
- **Pre-sandwich**: Attack succeeds if gas price competition fails
- **Post-sandwich**: Attack blocked by commit-reveal or randomization
- **Break-even gas price**: 15-25% of victim's gas price depending on network conditions

---

## Scenario 2: Consensus Sybil Manipulation

### Prerequisites
- Control of multiple EOAs (10-50 recommended)
- Minimum stake per account (globalMinValidationStake)
- Coordination mechanism (private channel/bot)
- Target projects with low validator participation

### Attack Architecture
```solidity
contract SybilCoordinator {
    struct SybilValidator {
        address account;
        uint256 stakeAmount;
        bytes32 commitHash;
        uint16 manipulatedScore;
    }

    mapping(bytes32 => SybilValidator[]) public sybilGroups;
    mapping(bytes32 => uint16) public targetScores;

    function coordinateAttack(
        bytes32 projectId,
        uint256 index,
        uint16 targetScore,
        address[] calldata validators
    ) external {
        targetScores[projectId] = targetScore;
        // Distribute target score to all sybil validators
    }
}
```

### Step-by-Step Execution

#### Phase 1: Account Preparation
```
For each sybil account (10-50 accounts):
1. Fund account with minimum stake + buffer
2. Set validator capacity: setValidatorCapacity(minStake)
3. Build reputation through legitimate participation (optional)
4. Register accounts in coordination group
```

#### Phase 2: Target Identification
```
1. Monitor for projects with:
   - Low expected validator participation (< 50% of numberOfValidations)
   - High reward potential
   - Controversial or borderline consensus thresholds
2. Calculate manipulation feasibility:
   sybilWeight = numSybil × sqrt(minStake) × avgReputation
   honestWeight = estimatedHonestValidators × avgStake^0.5 × avgReputation
   manipulationRatio = sybilWeight / (sybilWeight + honestWeight)
```

#### Phase 3: Coordinated Commitment
```
1. All sybil accounts commit simultaneously:
   function commitValidation(projectId, index, commitHash, stakeAmount)
   - commitHash = keccak256(abi.encodePacked(manipulatedScore, salt))
   - stakeAmount = minStake (to minimize losses)

2. Coordination ensures all use same manipulatedScore
3. Timing: Commit within first 25% of commit window for advantage
```

#### Phase 4: Selective Revelation
```
1. Monitor honest validator reveals
2. If consensus trending toward target: all sybil accounts reveal
3. If consensus opposing target: coordinated non-reveal (free option)
4. Ghost validators absorb slashing risk
```

#### Phase 5: Consensus Exploitation
```
If manipulation succeeds:
1. Extract validator rewards for all revealing accounts
2. Claim adapter fees if applicable
3. Recycle slashed stake from ghost validators

If manipulation fails:
1. Minimize losses through non-reveal of unprofitable positions
2. Reputation damage limited to participating accounts
```

### Profit Optimization
```
Expected Value = P(success) × rewardPerValidator × numSuccessful +
                 P(failure) × (-slashPerGhost × numGhosts)

Where:
- P(success) based on manipulation ratio and outlier detection
- rewardPerValidator = (totalValidatorRewards × weight) / totalWeight
- slashPerGhost = stakeAmount × slashPercentage (10-100% based on deviation)
```

### Advanced Techniques
- **Dynamic Sybil Sizing**: Adjust number of accounts based on target project
- **Stake Optimization**: Use minimum viable stake per account
- **Reputation Farming**: Pre-build reputation on low-value projects
- **Cross-Project Arbitrage**: Coordinate across multiple simultaneous consensuses

---

## Scenario 3: Free Option Ghost Validation

### Prerequisites
- Minimum stake for validation commitment
- Access to consensus monitoring infrastructure
- Low-risk tolerance (bounded downside)
- Target high-volatility consensus environments

### Attack Mechanism
```solidity
contract GhostValidator {
    struct PendingCommit {
        bytes32 projectId;
        uint256 index;
        bytes32 commitHash;
        uint128 stakeAmount;
        uint16 trueScore;
        uint16 manipulatedScore;
    }

    mapping(bytes32 => PendingCommit) public ghostPositions;

    function evaluateReveal(
        bytes32 projectId,
        uint256 index
    ) public view returns (bool shouldReveal, uint16 score) {
        // Monitor emerging consensus
        // Decide whether to reveal true or manipulated score
        // Or not reveal at all (free option)
    }
}
```

### Step-by-Step Execution

#### Phase 1: Strategic Commitment
```
1. Monitor validation commitments from honest validators
2. Identify projects with emerging consensus splits
3. Commit with minimum stake using ambiguous commit hash
4. Store both true and manipulated scores for potential reveals
```

#### Phase 2: Consensus Monitoring
```
1. Track reveal patterns during reveal window
2. Calculate emerging consensus weighted average
3. Assess position relative to consensus:
   - Bullish: emerging consensus favors positive reveal
   - Bearish: emerging consensus favors negative reveal
   - Neutral: consensus too close to call
```

#### Phase 3: Option Execution
```
If Bullish Position:
1. Reveal score that aligns with emerging consensus
2. Collect validator rewards
3. Extract reputation gains

If Bearish Position:
1. Reveal score that opposes emerging consensus
2. Accept outlier slashing (bounded loss)
3. Free option exercised

If Neutral Position:
1. Don't reveal (free option)
2. Wait for expiration or cancellation
3. Stake loss capped at commitment amount
```

#### Phase 4: Stake Recovery
```
For revealed positions:
- If accurate: stake released + rewards gained
- If outlier: stake partially/fully slashed

For non-revealed positions:
- Wait for cancelExpiredCommitment() after deadline
- Accept full stake slash (worst case)
- Reputation penalty applied
```

### Risk-Reward Analysis
```
Payoff Matrix:

Reveal Accurate:   +reward - 0 (stake returned)
Reveal Inaccurate: +reward - slash (partial stake loss)
Don't Reveal:      +0      - fullStake (guaranteed loss)

Free Option Value = Max(0, expectedReward - stakeCost)
```

### Optimization Strategies
- **Position Sizing**: Limit commitment stake to acceptable loss amount
- **Multiple Positions**: Diversify across uncorrelated consensuses
- **Timing**: Reveal late in window to maximize information advantage
- **Correlation**: Avoid positions with high correlation to minimize portfolio risk

---

## Scenario 4: Dispute Bond Arbitrage Griefing

### Prerequisites
- Small amount of stake for dispute bonds
- Access to accepted contribution monitoring
- Low-value target for griefing (competitors/contributors)
- Automated dispute opening infrastructure

### Attack Setup
```solidity
contract DisputeGriefer {
    struct GriefTarget {
        bytes32 projectId;
        uint256 index;
        address contributor;
        uint256 bondAmount;
        uint256 potentialDelay;
    }

    function calculateGriefProfit(
        GriefTarget memory target
    ) public pure returns (uint256) {
        // Calculate opportunity cost to contributor
        // Factor in time value of delayed rewards
        // Account for dispute resolution probability
    }
}
```

### Step-by-Step Execution

#### Phase 1: Target Selection
```
1. Monitor for newly accepted contributions
2. Identify high-value contributors with time-sensitive rewards
3. Calculate dispute bond: (rewardRate × disputeBondBps) / BPS
4. Assess grief value: rewardDelay × opportunityCost
```

#### Phase 2: Coordinated Dispute Opening
```
1. Open dispute immediately after consensus acceptance:
   function openDispute(projectId, index, evidenceHash)
   - evidenceHash: minimal/frivolous evidence
   - bondAmount: calculated minimum

2. Extend challenge period automatically
3. Lock contributor rewards during dispute window
```

#### Phase 3: Dispute Management
```
1. Monitor dispute resolution timeline
2. If operator resolves quickly: accept bond return
3. If operator delays: dispute escalates automatically
4. Maintain dispute until auto-resolution or operator action
```

#### Phase 4: Profit Extraction
```
1. Bond returned when dispute resolved in attacker's favor
2. Contributor reward release delayed by DISPUTE_RESOLUTION_DEADLINE
3. Opportunity cost extracted through timing advantage
4. Repeat across multiple targets for scale
```

### Advanced Griefing Techniques
- **Serial Griefing**: Chain disputes on same contribution
- **Multi-Target**: Open disputes on all indices in a project
- **Bond Optimization**: Use minimum viable bonds
- **Evidence Automation**: Generate procedural "evidence" for disputes

### Economic Impact Assessment
```
Grief Profit = (Contributor Opportunity Cost × Delay Duration) - Attacker Bond Cost
Where:
- Opportunity Cost = rewardAmount × (interestRate × delayDays / 365)
- Delay Duration = DISPUTE_RESOLUTION_DEADLINE (7 days default)
- Bond Cost = disputeBondBps% of rewardRate (temporary lock)
```

---

## Scenario 5: Reputation Farming via Flash Projects

### Prerequisites
- Project creation rights
- Minimum funding amount for project creation
- Control of multiple validator accounts
- Reputation extraction automation

### Attack Architecture
```solidity
contract ReputationFarm {
    struct FarmProject {
        bytes32 projectId;
        uint256 fundingAmount;
        uint256 numIndices;
        address[] validators;
        bool completed;
    }

    function createFarmProject(
        uint256 fundingAmount,
        uint256 numIndices
    ) external returns (bytes32) {
        // Create minimal project
        // Fund with minimum amount
        // Claim all indices
        // Set up self-validation
    }

    function executeFarmCycle(bytes32 projectId) external {
        // Contribute work
        // Self-validate with positive scores
        // Extract reputation
        // Complete/abandon project
    }
}
```

### Step-by-Step Execution

#### Phase 1: Project Creation
```
1. Create project with minimal configuration:
   - consensusThreshold: minimum viable (1 bp)
   - validatorRewardBps: 0 (minimize costs)
   - numberOfValidations: low number (3-5)

2. Fund project with minimum amount
3. Lock originator stake (if required)
```

#### Phase 2: Self-Contribution
```
1. Claim all available indices
2. Submit minimal viable contributions
3. Set up self-validation infrastructure
```

#### Phase 3: Coordinated Validation
```
1. Use controlled validator accounts to commit
2. All validators reveal identical high scores
3. Achieve consensus with 100% approval rate
4. Extract contributor reputation boost
```

#### Phase 4: Reputation Extraction
```
1. Reputation updated: SUCCESS_INCREASE (10) + qualityBonus
2. Quality bonus = (weightedAverage × 20) / BPS
3. With perfect scores: +10 + 20 = +30 reputation
4. Originator reputation also boosted (+10)
```

#### Phase 5: Project Cleanup
```
1. Complete project to unlock stakes
2. Refund escrow to originator
3. Recycle accounts for next farming cycle
4. Reputation preserved for future use
```

### Scaling Considerations
- **Parallel Farming**: Run multiple projects simultaneously
- **Account Rotation**: Use fresh accounts for each cycle
- **Stake Optimization**: Minimize locked stake duration
- **Fee Minimization**: Use zero-fee adapters or direct contribution

### Profit Model
```
Reputation Gained = baseIncrease + qualityBonus
Utility Value = Reputation × (Participation Weight in Future Projects)
Cost = Funding Amount + Gas Costs + Stake Opportunity Cost

Net Value = Reputation Utility - Direct Costs
```

---

## Scenario 6: Fee Rounding Dust Accumulation

### Prerequisites
- Large volume of transactions through the protocol
- Fee-on-transfer token interactions
- Multiple fee tiers active simultaneously
- Long-term position holding

### Attack Mechanism
```solidity
contract RoundingDustCollector {
    struct FeeStream {
        address token;
        uint256 accumulatedDust;
        uint256 collectionThreshold;
    }

    mapping(address => FeeStream) public feeStreams;

    function monitorFeeRounding(
        address token,
        uint256 expectedFee,
        uint256 actualFee
    ) external {
        uint256 dust = expectedFee - actualFee;
        feeStreams[token].accumulatedDust += dust;

        if (feeStreams[token].accumulatedDust >= collectionThreshold) {
            collectDust(token);
        }
    }
}
```

### Step-by-Step Execution

#### Phase 1: Fee Structure Analysis
```
1. Map all fee deduction points:
   - Protocol fee (1%)
   - Origination adapter fee (2%)
   - Contribution adapter fee (2%)
   - Validation adapter fee (2%)

2. Calculate cumulative rounding bias:
   Base Amount × ∏(1 - feeBps/10000) vs sequential deductions
```

#### Phase 2: Volume Exploitation
```
1. Execute high-volume operations to accumulate dust:
   - Create/fund many projects
   - Facilitate numerous contributions
   - Process many validations/settlements

2. Each operation contributes small rounding dust
3. Dust accumulates in pendingRewards mappings
```

#### Phase 3: Dust Harvesting
```
1. Monitor accumulated rounding differences
2. Claim rewards when dust reaches economic thresholds
3. Extract protocol's rounding gains as user rewards
4. Reinvest proceeds for compound dust accumulation
```

### Mathematical Exploitation
```
For each fee tier, rounding loss = amount - floor(amount × feeBps / BPS)

Cumulative Loss = Σ roundingLoss over all tiers
Protocol Gain = Total Fees Deducted - Σ Actual Fee Payments

Attacker Extraction = Protocol Gain × Participation Rate
```

### Advanced Techniques
- **Token Selection**: Focus on high-volume, fee-on-transfer tokens
- **Timing Optimization**: Claim during low gas periods
- **Volume Automation**: Use bots for continuous protocol interaction
- **Multi-Token Arbitrage**: Extract dust across different reward tokens

---

## Mitigation Effectiveness Assessment

### Current Protocol Defenses
- **Stake Requirements**: Increase attack costs but don't prevent Sybil attacks
- **Commit-Reveal**: Prevents score herding but enables free options
- **Slashing**: Deters but doesn't prevent sophisticated attacks
- **Time Windows**: Create timing games and sandwich opportunities

### Recommended Protocol Hardening
1. **Consensus Algorithm Improvements**:
   - Implement quadratic staking weights
   - Add correlation detection for Sybil identification
   - Use time-averaged stake calculations

2. **Economic Parameter Adjustments**:
   - Increase minimum stake requirements dynamically
   - Implement reputation stake-locking
   - Add dispute bond escalation

3. **Timing and Randomization**:
   - Add commit-reveal for index claiming
   - Implement VRF-based randomization
   - Use time-weighted stake calculations

4. **Monitoring and Circuit Breakers**:
   - Add anomaly detection for consensus manipulation
   - Implement participation rate monitoring
   - Add emergency pause mechanisms for detected attacks

### Economic Security Budget
```
Recommended Stake Requirements:
- Contributor Stake: 1% of project value
- Validator Stake: 0.1% of project value per validation
- Originator Stake: 5% of project value (locked until completion)
- Dispute Bonds: 10% of reward amount

Break-Even Attack Cost = Protocol Security Budget × Attack Success Probability
```

This completes the MEV attack playbook analysis for Sapien PoQ v0.5. Each scenario represents economically viable attack vectors that require protocol-level mitigation rather than user behavior changes.