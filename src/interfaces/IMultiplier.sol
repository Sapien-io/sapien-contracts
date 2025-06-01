// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/// @title IMultiplier - Interface for Sapien AI Staking Multiplier Calculator
/// @notice Interface for handling all multiplier calculations for the Sapien staking system
interface IMultiplier {
    
    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------
    
    event MultiplierCalculationUpdated(uint256 indexed version);
    
    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------
    
    error InvalidStakeAmount();
    error InvalidLockupPeriod();
    
    // -------------------------------------------------------------
    // Core Multiplier Functions
    // -------------------------------------------------------------

    /**
     * @notice Get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function getMultiplierForPeriod(uint256 lockUpPeriod) external pure returns (uint256 multiplier);

    /**
     * @notice Calculate linear weighted multiplier that includes both time and amount factors plus global coefficient
     * @param amount The total staked amount
     * @param effectiveLockup The effective lockup period
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return The calculated final multiplier including global effects
     */
    function calculateLinearWeightedMultiplier(
        uint256 amount, 
        uint256 effectiveLockup,
        uint256 totalStaked,
        uint256 totalSupply
    ) external pure returns (uint256);

    /**
     * @notice Calculate individual multiplier based on time and amount factors
     * @param amount The staked amount
     * @param effectiveLockup The effective lockup period
     * @return The individual multiplier before global effects
     */
    function calculateIndividualMultiplier(uint256 amount, uint256 effectiveLockup) external pure returns (uint256);

    /**
     * @notice Calculate amount factor using logarithmic scaling
     * @param amount The staked amount
     * @return The amount factor (0 to 10000, representing 0.0 to 1.0)
     */
    function calculateAmountFactor(uint256 amount) external pure returns (uint256);

    /**
     * @notice Approximate log10 function for integer values
     * @param value The input value
     * @return The approximate log10 * 1000 for precision
     */
    function approximateLog10(uint256 value) external pure returns (uint256);

    /**
     * @notice Calculate global staking coefficient based on network participation
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return The global coefficient (5000-15000, representing 0.5x to 1.5x)
     */
    function calculateGlobalCoefficient(uint256 totalStaked, uint256 totalSupply) external pure returns (uint256);

    /**
     * @notice Calculate sigmoid-based coefficient for optimal staking participation
     * @param stakingRatio The ratio of staked tokens to total supply (in basis points)
     * @return The coefficient (5000-15000, representing 0.5x to 1.5x)
     */
    function calculateSigmoidCoefficient(uint256 stakingRatio) external pure returns (uint256);

    /**
     * @notice Get detailed multiplier breakdown for a given amount and duration
     * @param amount The stake amount
     * @param duration The lockup duration
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return individualMultiplier The multiplier before global effects
     * @return globalCoefficient The current global coefficient
     * @return finalMultiplier The final multiplier after global effects
     * @return stakingRatio Current network staking ratio (basis points)
     */
    function getMultiplierBreakdown(
        uint256 amount, 
        uint256 duration,
        uint256 totalStaked,
        uint256 totalSupply
    ) external pure returns (
        uint256 individualMultiplier, 
        uint256 globalCoefficient, 
        uint256 finalMultiplier, 
        uint256 stakingRatio
    );

    /**
     * @notice Validates that a lockup period is supported
     * @param lockUpPeriod The lockup period to validate
     * @return isValid Whether the lockup period is valid
     */
    function isValidLockupPeriod(uint256 lockUpPeriod) external pure returns (bool isValid);

    /**
     * @notice Calculate multiplier combining base lockup multiplier with amount factor
     * @param amount The staked amount
     * @param effectiveLockup The effective lockup period
     * @return The calculated multiplier
     */
    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) external pure returns (uint256);
} 