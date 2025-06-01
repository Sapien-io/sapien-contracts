# Staking End-to-End Test Suite Documentation

## Overview
The Staking End-to-End Test Suite (`SapienVault_EndToEnd.t.sol`) provides comprehensive testing of the SapienVault staking system through realistic user journeys and scenarios. This test suite validates the complete staking lifecycle from initial stake through various modifications to final unstaking, including emergency scenarios and system integrations.

## Test Architecture

### Core Components
- **SapienVault**: Main staking contract with full functionality
- **SapienQA**: Quality assurance system integration 
- **Multiplier**: Reward multiplier calculation system
- **MockERC20**: SAPIEN token implementation for testing

### User Personas
The test suite employs 8 distinct user personas, each representing different staking behaviors:

1. **Conservative Staker**: Low-risk approach, prefers shorter lockups and smaller amounts
2. **Aggressive Staker**: High-risk tolerance, large stakes with long lockups
3. **Strategic Staker**: Dynamic approach, frequently adjusts strategy based on conditions
4. **Emergency User**: Requires unexpected liquidity, tests early unstaking scenarios
5. **Compound Staker**: Progressive builder, gradually increases stake over time
6. **QA Victim**: Subject to quality assurance penalties
7. **Max Staker**: Boundary tester, explores system limits
8. **Social Staker**: Community-oriented behaviors, multiple partial operations

## Main End-to-End Test Phases

### Phase 1: Initial Adoption & Basic Staking (Day 0-30)
**Purpose**: Test basic staking functionality with various user profiles
- Conservative staker: Small stake, 30-day lockup
- Aggressive staker: Large stake, 365-day lockup  
- Strategic staker: Medium stake, 90-day lockup
- Time progression: 30 days

**Key Validations**:
- Stake creation with different amounts and lockups
- Total staked tracking
- User state verification
- Multiplier calculations

### Phase 2: Stake Optimization & Growth (Day 30-90)
**Purpose**: Test stake modification features as users optimize their positions
- Amount increases by conservative staker
- Lockup extensions by strategic staker
- New user onboarding (compound staker, social staker)
- Boundary testing with max staker (1M tokens)
- Time progression: 60 days (total: 90 days)

**Key Validations**:
- `increaseAmount()` functionality
- `increaseLockup()` functionality  
- Weighted average calculations
- System scalability

### Phase 3: Strategic Adjustments (Day 90-180)
**Purpose**: Test complex staking strategies and iterative optimizations
- Compound staker's progressive growth strategy (3 iterations)
- Strategic staker's major rebalancing
- Conservative staker's first lockup extension
- Time progression: 90 days (total: 180 days)

**Key Validations**:
- Multiple consecutive stake modifications
- Lockup period calculations
- Strategy evolution over time
- State consistency through changes

### Phase 4: Maturity & Complexity (Day 180-270)
**Purpose**: Test unstaking flows and cooldown mechanisms
- Conservative staker partial unstaking (initiate → cooldown → unstake)
- Social staker multiple unstake initiations
- Emergency user preparation
- Time progression: 90 days (total: 270 days)

**Key Validations**:
- `initiateUnstake()` functionality
- Cooldown period enforcement
- Partial unstaking mechanics
- Multiple unstake request handling

### Phase 5: Emergency & Edge Cases (Day 270-365)
**Purpose**: Test emergency scenarios and system robustness
- Emergency user early unstaking with penalties
- Edge case testing (oversized unstake attempts)
- Social staker cooldown completion
- System pause/unpause functionality
- Time progression: 95 days (total: 365 days)

**Key Validations**:
- `earlyUnstake()` with penalty calculations
- Error handling for invalid operations
- Administrative controls (pause/unpause)
- Treasury penalty collection

### Phase 6: QA Integration & Penalties
**Purpose**: Test quality assurance system integration
- QA victim staking before penalties
- Standard QA penalty processing
- Large penalty handling (exceeding stake)
- Treasury transfer verification

**Key Validations**:
- `processQAPenalty()` functionality
- Penalty amount calculations
- Stake reduction mechanics
- Treasury balance updates

### Phase 7: Long-term Operations (Day 365+)
**Purpose**: Test long-term system behavior and new user onboarding
- Aggressive staker's year-long lockup completion
- Max staker large-scale operations
- Late user onboarding to mature system
- Final optimizations
- Time progression: 30+ days (total: ~400 days)

**Key Validations**:
- Long-term lockup completion
- System performance with large stakes
- New user integration in mature system
- Final state consistency

## Specialized Scenario Tests

### Progressive Builder Pattern
**Test**: `test_StakingPattern_ProgressiveBuilder()`
**Scenario**: User gradually builds stake over 4 weeks with increasing amounts and lockup extensions

**Week-by-Week Progression**:
1. Initial minimum stake (30-day lockup)
2. Double the stake amount  
3. Extend lockup (+60 days)
4. Major stake increase (+3x minimum)
5. Final lockup extension (+90 days)

**Validations**:
- Progressive stake building (5x final amount)
- Lockup period accumulation
- Multiplier optimization

### Early Exit Optimizer Pattern  
**Test**: `test_StakingPattern_EarlyExitOptimizer()`
**Scenario**: User stakes for long-term but needs emergency liquidity after 6 months

**Flow**:
1. Large stake with 365-day lockup
2. Emergency after 180 days
3. Strategic early unstaking (1/3 of stake)
4. Penalty calculation and payment

**Validations**:
- Early unstaking penalty (20%)
- Correct payout calculation
- Remaining stake preservation

### Liquidity Manager Pattern
**Test**: `test_StakingPattern_LiquidityManager()`  
**Scenario**: User manages stake for planned liquidity needs

**Strategy**:
1. Initial stake with short lockup
2. Amount increase for better rewards
3. Wait for lockup expiration
4. Partial unstaking for liquidity needs

**Validations**:
- Planned liquidity extraction
- Stake preservation
- No penalty normal unstaking

## Final Comprehensive Verification

### Token Conservation
- Vault balance equals total staked
- Treasury balance reflects collected penalties
- User balances account for all operations

### System Invariants
- Total staked tracking accuracy
- Active stake verification
- Multiplier reasonableness
- State consistency

### Success Metrics
The test suite validates successful handling of:
- ✅ Initial staking with various strategies
- ✅ Stake modifications (amount & lockup increases)  
- ✅ Multiple unstaking patterns
- ✅ Emergency early unstaking with penalties
- ✅ QA integration and penalty processing
- ✅ Long-term operations and late joiners
- ✅ System pause/unpause functionality
- ✅ Edge cases and boundary conditions
- ✅ Token conservation and accounting

## Gas Usage Analysis
- Main journey test: ~1.39M gas
- Progressive builder: ~271K gas  
- Early exit optimizer: ~263K gas
- Liquidity manager: ~258K gas

## Running the Tests

```bash
# Run all staking end-to-end tests
forge test --match-contract "SapienVaultEndToEndTest" -v

# Run specific test
forge test --match-test "test_EndToEnd_CompleteStakingJourney" -v

# Run pattern tests only
forge test --match-test "test_StakingPattern" -v
```

## Integration Points

### External Dependencies
- **SapienQA Contract**: Penalty processing integration
- **Multiplier Contract**: Reward calculation system
- **Treasury**: Penalty collection destination

### Test Data Validation
- All operations tracked for comprehensive verification
- Token conservation verified at multiple checkpoints
- State consistency validated throughout journey

This comprehensive test suite ensures the SapienVault staking system functions correctly under realistic conditions and edge cases, providing confidence in the system's robustness and reliability. 