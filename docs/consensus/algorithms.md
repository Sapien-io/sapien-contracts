# Consensus Algorithms

Sapien PoQ uses a pluggable consensus architecture. Originators can choose the algorithm that best fits their project's security and cost requirements.

## ⚖️ Available Algorithms

### Sqrt Stake Consensus (`SqrtStakeConsensus.sol`)

Uses a quadratic voting approach to balance power.

- **Weighting**: `sqrt(stake)`
- **Security Grade**: **A-**
- **Best For**: Projects seeking maximum validator diversity and fairness.
- **Pros**: Reduces the influence of large token holders, making it 22% more democratic than linear weighting. Prevents "whale" dominance with sublinear scaling.

## 📊 Comparison Summary

| Metric | Sqrt Stake |
|--------|------------|
| **Whale Resistance** | High |
| **Sybil Resistance** | High |
| **Efficiency (Gas)** | High |
| **Incentive Alignment** | High |

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
