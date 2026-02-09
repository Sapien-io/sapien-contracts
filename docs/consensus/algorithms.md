# Consensus Algorithms

Sapien PoQ uses a pluggable consensus architecture. Originators can choose the algorithm that best fits their project's security and cost requirements.

## ⚖️ Available Algorithms

### 1. Hybrid Consensus (`HybridConsensus.sol`)
The most sophisticated and recommended algorithm for Sapien.
- **Weighting**: `min(sqrt(stake) × reputation, 30% cap)`
- **Security Grade**: **A-**
- **Best For**: High-value projects where long-term quality and Sybil resistance are critical.
- **Pros**: Perfectly aligns incentives by considering both financial stake and historical quality (PoQ). Prevents "whale" dominance with a hard cap and sublinear (sqrt) scaling.

### 2. Sqrt Stake Consensus (`SqrtStakeConsensus.sol`)
Uses a quadratic voting approach to balance power.
- **Weighting**: `sqrt(stake)`
- **Security Grade**: **A-**
- **Best For**: Projects seeking maximum validator diversity and fairness.
- **Pros**: Reduces the influence of large token holders, making it 22% more democratic than linear weighting.

### 3. Capped Linear Consensus (`CappedLinearConsensus.sol`)
A middle ground between traditional staking and advanced consensus.
- **Weighting**: `min(stake, 30% of total committee stake)`
- **Security Grade**: **B+**
- **Best For**: General use cases requiring a simple but secure upgrade from linear weighting.
- **Pros**: Prevents any single validator from controlling the outcome (whale protection).

### 4. Linear Stake Consensus (`LinearStakeConsensus.sol`)
The simplest form of consensus.
- **Weighting**: `stake`
- **Security Grade**: **C+**
- **Best For**: Low-risk projects or backward compatibility.
- **Cons**: Vulnerable to "whale" attacks where a single large holder can override the committee.

## 📊 Comparison Summary

| Metric | Linear | Capped | Sqrt | Hybrid |
|--------|--------|--------|------|--------|
| **Whale Resistance** | Low | High | Medium | High |
| **Sybil Resistance** | High | Medium | Medium | High |
| **Efficiency (Gas)** | Very High | High | Medium | Medium |
| **Incentive Alignment** | Low | Medium | High | Very High |

## 🛠️ How it Works

1. **Input**: Each algorithm receives an array of `ValidationInput` (Validator, Score, Stake, Reputation).
2. **Weighting**: The algorithm calculates the weight of each validator based on its specific logic.
3. **Consensus**: A weighted average score is calculated.
4. **Outlier Detection**: The system uses `ConsensusLib` to identify validators whose scores deviate significantly.
   - **Absolute Threshold**: Any score deviating by more than 1500 (15%) from the mean is considered an outlier.
   - **Relative Threshold**: Any score deviating by more than 2 standard deviations (2σ) is considered an outlier.
5. **Slashing Calculation**: `ConsensusLib` calculates a slash percentage based on the number of standard deviations from the mean:
   - **5σ+**: 100% slash (Extreme Outlier)
   - **4σ-5σ**: 75% slash
   - **3σ-4σ**: 50% slash
   - **2σ-3σ**: 25% slash
   - **1.5σ-2σ**: 10% slash
6. **Output**: Returns the final `weightedAverage` and a list of `validatorsToSlash` with their corresponding `slashAmounts`.
