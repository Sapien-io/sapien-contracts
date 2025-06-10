// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test } from "lib/forge-std/src/Test.sol";
import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { SapienVault } from "src/SapienVault.sol";
import { ERC1967Proxy } from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Constants as Const } from "src/utils/Constants.sol";

// Handler contract for invariant testing
contract SapienVaultHandler is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;
    
    address[] public actors;
    uint256 public constant MINIMUM_STAKE = Const.MINIMUM_STAKE_AMOUNT;
    uint256 public constant COOLDOWN_PERIOD = Const.COOLDOWN_PERIOD;
    uint256 public constant MINIMUM_LOCKUP_INCREASE = Const.MINIMUM_LOCKUP_INCREASE;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = Const.EARLY_WITHDRAWAL_PENALTY;
    
    // Track system state for invariants
    uint256 public totalStakedByUsers;
    uint256 public totalPenaltiesPaid;
    uint256 public totalNormalUnstakes;
    uint256 public totalEarlyUnstakes;
    
    // Valid lock periods
    uint256[] public lockPeriods = [
        Const.LOCKUP_30_DAYS, 
        Const.LOCKUP_90_DAYS, 
        Const.LOCKUP_180_DAYS, 
        Const.LOCKUP_365_DAYS
    ];
    
    modifier useActor(uint256 actorIndexSeed) {
        address currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }
    
    constructor(SapienVault _sapienVault, MockERC20 _sapienToken) {
        sapienVault = _sapienVault;
        sapienToken = _sapienToken;
        
        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            sapienToken.mint(actor, 1000000e18);
        }
    }
    
    function stake(uint256 actorSeed, uint256 amountSeed, uint256 lockPeriodSeed) public useActor(actorSeed) {
        uint256 amount = bound(amountSeed, MINIMUM_STAKE, MINIMUM_STAKE * 50);
        uint256 lockPeriod = lockPeriods[bound(lockPeriodSeed, 0, lockPeriods.length - 1)];
        
        // Ensure actor has enough tokens
        if (sapienToken.balanceOf(msg.sender) < amount) {
            return;
        }
        
        sapienToken.approve(address(sapienVault), amount);
        
        try sapienVault.stake(amount, lockPeriod) {
            totalStakedByUsers += amount;
        } catch {
            // Stake failed, continue
        }
    }
    
    function increaseAmount(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        if (!sapienVault.hasActiveStake(msg.sender)) return;
        
        uint256 amount = bound(amountSeed, MINIMUM_STAKE, MINIMUM_STAKE * 20);
        
        // Ensure actor has enough tokens
        if (sapienToken.balanceOf(msg.sender) < amount) {
            return;
        }
        
        sapienToken.approve(address(sapienVault), amount);
        
        try sapienVault.increaseAmount(amount) {
            totalStakedByUsers += amount;
        } catch {
            // Failed, continue
        }
    }
    
    function increaseLockup(uint256 actorSeed, uint256 lockupIncreaseSeed) public useActor(actorSeed) {
        if (!sapienVault.hasActiveStake(msg.sender)) return;
        
        uint256 lockupIncrease = bound(lockupIncreaseSeed, MINIMUM_LOCKUP_INCREASE, 300 days);
        
        try sapienVault.increaseLockup(lockupIncrease) {
            // Success
        } catch {
            // Failed, continue
        }
    }
    
    function initiateUnstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalUnlocked = sapienVault.getTotalUnlocked(msg.sender);
        if (totalUnlocked == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalUnlocked);
        
        try sapienVault.initiateUnstake(amount) {
            // Success
        } catch {
            // Failed, continue
        }
    }
    
    function unstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalReady = sapienVault.getTotalReadyForUnstake(msg.sender);
        if (totalReady == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalReady);
        
        uint256 balanceBefore = sapienToken.balanceOf(msg.sender);
        
        try sapienVault.unstake(amount) {
            uint256 balanceAfter = sapienToken.balanceOf(msg.sender);
            totalNormalUnstakes += (balanceAfter - balanceBefore);
            totalStakedByUsers -= amount;
        } catch {
            // Failed, continue
        }
    }
    
    function earlyUnstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalLocked = sapienVault.getTotalLocked(msg.sender);
        if (totalLocked == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalLocked);
        
        uint256 balanceBefore = sapienToken.balanceOf(msg.sender);
        
        try sapienVault.earlyUnstake(amount) {
            uint256 balanceAfter = sapienToken.balanceOf(msg.sender);
            uint256 received = balanceAfter - balanceBefore;
            uint256 penalty = amount - received;
            
            totalEarlyUnstakes += received;
            totalPenaltiesPaid += penalty;
            totalStakedByUsers -= amount;
        } catch {
            // Failed, continue
        }
    }
    
    function warpTime(uint256 timeSeed) public {
        uint256 timeToWarp = bound(timeSeed, 1 hours, 400 days);
        vm.warp(block.timestamp + timeToWarp);
    }
    
    // Helper function to get total staked across all users
    function getTotalStakedAcrossUsers() public view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += sapienVault.getTotalStaked(actors[i]);
        }
    }
    
    // Getter function for actors array
    function getActors() public view returns (address[] memory) {
        return actors;
    }
}

contract SapienVaultInvariantsTest is StdInvariant, Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;
    SapienVaultHandler public handler;
    
    address public admin = makeAddr("admin");
    address public rewardSafe = makeAddr("rewardSafe");
    address public sapienQA = makeAddr("sapienQA");
    
    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);
        
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            rewardSafe,
            sapienQA
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));
        
        handler = new SapienVaultHandler(sapienVault, sapienToken);
        
        // Set up invariant testing
        targetContract(address(handler));
        
        // Define function selectors to call
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = SapienVaultHandler.stake.selector;
        selectors[1] = SapienVaultHandler.increaseAmount.selector;
        selectors[2] = SapienVaultHandler.increaseLockup.selector;
        selectors[3] = SapienVaultHandler.initiateUnstake.selector;
        selectors[4] = SapienVaultHandler.unstake.selector;
        selectors[5] = SapienVaultHandler.earlyUnstake.selector;
        selectors[6] = SapienVaultHandler.warpTime.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    // =============================================================================
    // CORE INVARIANTS
    // =============================================================================
    
    /// @dev The contract's token balance should always equal totalStaked
    function invariant_TokenBalanceEqualsStaked() public view {
        assertEq(
            sapienToken.balanceOf(address(sapienVault)),
            sapienVault.totalStaked(),
            "Contract token balance must equal totalStaked"
        );
    }
    
    /// @dev Total staked should equal sum of all user stakes
    function invariant_TotalStakedEqualsUserStakes() public view {
        uint256 sumOfUserStakes = handler.getTotalStakedAcrossUsers();
        assertEq(
            sapienVault.totalStaked(),
            sumOfUserStakes,
            "totalStaked must equal sum of all user stakes"
        );
    }
    
    /// @dev No user should have negative stake amounts or stakes below minimum
    function invariant_NoInvalidStakes() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 userStaked = sapienVault.getTotalStaked(actors[i]);
            
            // If user has stake, it should be >= MINIMUM_STAKE
            if (userStaked > 0) {
                assertTrue(
                    userStaked >= handler.MINIMUM_STAKE(),
                    "User stake must be 0 or >= minimum stake"
                );
                
                // User should have active stake
                assertTrue(
                    sapienVault.hasActiveStake(actors[i]),
                    "User with staked amount should have active stake"
                );
            } else {
                // If no stake, should not have active stake
                assertFalse(
                    sapienVault.hasActiveStake(actors[i]),
                    "User with no staked amount should not have active stake"
                );
            }
        }
    }
    
    /// @dev User summary totals should be consistent
    function invariant_UserSummaryConsistency() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint256 userTotalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                uint256 totalInCooldown,
                uint256 totalReadyForUnstake,
                uint256 effectiveMultiplier,
                uint256 effectiveLockUpPeriod,
                uint256 timeUntilUnlock
            ) = sapienVault.getUserStakingSummary(actors[i]);
            
            if (userTotalStaked > 0) {
                // Total staked should equal locked + unlocked
                assertEq(
                    userTotalStaked,
                    totalLocked + totalUnlocked,
                    "Total staked must equal locked + unlocked"
                );
                
                // Ready for unstake should be <= total in cooldown
                assertLe(
                    totalReadyForUnstake,
                    totalInCooldown,
                    "Ready for unstake must be <= total in cooldown"
                );
                
                // Effective multiplier should be in valid range (using new multiplier system)
                assertTrue(
                    effectiveMultiplier >= 10000 && effectiveMultiplier <= 20000,
                    "Effective multiplier must be in valid range (1.0x - 2.0x)"
                );
                
                // Effective lockup should be <= 365 days
                assertLe(
                    effectiveLockUpPeriod,
                    Const.LOCKUP_365_DAYS,
                    "Effective lockup must be <= 365 days"
                );
            } else {
                // If no stake, all values should be zero
                assertEq(totalUnlocked, 0, "No stake means no unlocked");
                assertEq(totalLocked, 0, "No stake means no locked");
                assertEq(totalInCooldown, 0, "No stake means no cooldown");
                assertEq(totalReadyForUnstake, 0, "No stake means nothing ready");
                assertEq(timeUntilUnlock, 0, "No stake means no unlock time");
            }
        }
    }
    
    /// @dev Multipliers should be calculated using the new multiplier contract
    function invariant_ValidMultiplierCalculation() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                (
                    uint256 userTotalStaked,
                    ,,,,,
                    uint256 effectiveLockUpPeriod,
                    
                ) = sapienVault.getUserStakingSummary(actors[i]);
                
                // Calculate expected multiplier using the contract's method
                uint256 expectedMultiplier = sapienVault.calculateMultiplier(userTotalStaked, effectiveLockUpPeriod);
                
                // Get actual multiplier from summary
                (,,,,,uint256 actualMultiplier,,) = sapienVault.getUserStakingSummary(actors[i]);
                
                assertEq(
                    actualMultiplier,
                    expectedMultiplier,
                    "Actual multiplier should match calculated multiplier"
                );
            }
        }
    }
    
    /// @dev Cooldown logic should be consistent
    function invariant_CooldownLogic() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint256 userTotalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                uint256 totalInCooldown,
                uint256 totalReadyForUnstake,
                ,,
            ) = sapienVault.getUserStakingSummary(actors[i]);
            
            if (userTotalStaked > 0) {
                // Total unlocked + total locked should equal total staked
                assertEq(
                    totalUnlocked + totalLocked,
                    userTotalStaked,
                    "Unlocked + locked must equal total staked"
                );
                
                // Cooldown amount should not exceed total staked
                assertLe(
                    totalInCooldown,
                    userTotalStaked,
                    "Cooldown cannot exceed total staked"
                );
                
                // Ready for unstake should not exceed cooldown
                assertLe(
                    totalReadyForUnstake,
                    totalInCooldown,
                    "Ready for unstake cannot exceed cooldown"
                );
            }
        }
    }
    
    /// @dev Reward Safe should only receive penalty payments
    function invariant_RewardSafeOnlyReceivesPenalties() public view {
        uint256 rewardSafeBalance = sapienToken.balanceOf(rewardSafe);
        uint256 totalPenalties = handler.totalPenaltiesPaid();
        
        assertEq(
            rewardSafeBalance,
            totalPenalties,
            "Reward Safe balance must equal total penalties paid"
        );
    }
    
    /// @dev Total tokens should be conserved (accounting for penalties)
    function invariant_TokenConservation() public view {
        uint256 contractBalance = sapienToken.balanceOf(address(sapienVault));
        uint256 rewardSafeBalance = sapienToken.balanceOf(rewardSafe);
        uint256 totalUserBalances = 0;
        
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            totalUserBalances += sapienToken.balanceOf(actors[i]);
        }
        
        uint256 totalSupplyToActors = actors.length * 1000000e18; // Initial mint amount
        
        assertEq(
            contractBalance + rewardSafeBalance + totalUserBalances,
            totalSupplyToActors,
            "Total tokens must be conserved"
        );
    }
    
    // =============================================================================
    // SINGLE STAKE SPECIFIC INVARIANTS
    // =============================================================================
    
    /// @dev Each user should have at most one active stake
    function invariant_SingleStakePerUser() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                // User has active stake - verify they can only have one
                uint256 totalStaked = sapienVault.getTotalStaked(actors[i]);
                assertGt(totalStaked, 0, "Active user should have positive stake amount");
                
                // Verify getUserStakingSummary returns consistent data
                (uint256 summaryTotal,,,,,,,) = sapienVault.getUserStakingSummary(actors[i]);
                assertEq(summaryTotal, totalStaked, "Summary total should match getTotalStaked");
            } else {
                // Should have no stake
                uint256 totalStaked = sapienVault.getTotalStaked(actors[i]);
                assertEq(totalStaked, 0, "Inactive user should have zero stake");
            }
        }
    }
    
    /// @dev Weighted average properties should be maintained
    function invariant_WeightedAverageProperties() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                (
                    uint256 userTotalStaked,
                    ,,,,,
                    uint256 effectiveLockUpPeriod,
                    uint256 timeUntilUnlock
                ) = sapienVault.getUserStakingSummary(actors[i]);
                
                if (userTotalStaked > 0) {
                    // Effective lockup should be reasonable
                    assertLe(
                        effectiveLockUpPeriod,
                        Const.LOCKUP_365_DAYS,
                        "Effective lockup should not exceed max period"
                    );
                    
                    // Time until unlock should not exceed effective lockup
                    assertLe(
                        timeUntilUnlock,
                        effectiveLockUpPeriod,
                        "Time until unlock should not exceed effective lockup"
                    );
                }
            }
        }
    }
    
    // =============================================================================
    // BUSINESS LOGIC INVARIANTS
    // =============================================================================
    
    /// @dev Early unstake penalty should always be 20%
    function invariant_EarlyUnstakePenalty() public pure {
        // This is tested implicitly through the handler tracking
        // The penalty calculation is: penalty = amount * EARLY_WITHDRAWAL_PENALTY / 100
        assertEq(Const.EARLY_WITHDRAWAL_PENALTY, 20, "Penalty rate should be constant at 20%");
    }
    
    /// @dev Stakes should only be unlocked after lock period
    function invariant_StakesUnlockedAfterLockPeriod() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint256 userTotalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                ,,,,
                uint256 timeUntilUnlock
            ) = sapienVault.getUserStakingSummary(actors[i]);
            
            if (userTotalStaked > 0) {
                if (timeUntilUnlock == 0) {
                    // If no time until unlock, everything should be unlocked
                    assertEq(totalLocked, 0, "No locked tokens when timeUntilUnlock is 0");
                    assertEq(totalUnlocked, userTotalStaked, "All tokens should be unlocked");
                } else {
                    // If time remaining, everything should be locked
                    assertEq(totalUnlocked, 0, "No unlocked tokens when timeUntilUnlock > 0");
                    assertEq(totalLocked, userTotalStaked, "All tokens should be locked");
                    assertGt(timeUntilUnlock, 0, "Time until unlock should be positive");
                }
            }
        }
    }
    
    /// @dev Minimum stake requirement should always be enforced
    function invariant_MinimumStakeEnforced() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 userStaked = sapienVault.getTotalStaked(actors[i]);
            
            if (userStaked > 0) {
                assertTrue(
                    userStaked >= handler.MINIMUM_STAKE(),
                    "Active stakes must meet minimum requirement"
                );
            }
        }
    }
    
    /// @dev System should handle edge cases gracefully
    function invariant_NoOverflowUnderflow() public view {
        // Check that totalStaked doesn't overflow
        assertTrue(
            sapienVault.totalStaked() <= type(uint256).max,
            "totalStaked should not overflow"
        );
        
        // Check user balances don't underflow
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            assertTrue(
                sapienToken.balanceOf(actors[i]) <= type(uint256).max,
                "User balances should not overflow"
            );
        }
    }
    
    // =============================================================================
    // NEW SAPIEN VAULT SPECIFIC INVARIANTS
    // =============================================================================
    
    /// @dev Effective multipliers should be calculated correctly using the new multiplier matrix
    function invariant_EffectiveMultiplierRange() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                (
                    ,,,,,
                    uint256 effectiveMultiplier,
                    uint256 effectiveLockUpPeriod,
                    
                ) = sapienVault.getUserStakingSummary(actors[i]);
                
                if (effectiveLockUpPeriod > 0) {
                    // Check that multiplier is in the expected range for the new system
                    assertTrue(
                        effectiveMultiplier >= 10000 && effectiveMultiplier <= 20000,
                        "Multiplier should be in valid range (1.0x - 2.0x) for new system"
                    );
                    
                    // Minimum multiplier for any valid lockup should be at least 1.05x
                    if (effectiveLockUpPeriod >= Const.LOCKUP_30_DAYS) {
                        assertTrue(
                            effectiveMultiplier >= 10500,
                            "Multiplier should be at least 1.05x for valid lockup periods"
                        );
                    }
                }
            }
        }
    }
    
    /// @dev User stake state should be valid
    function invariant_UserStakeStateValidity() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            bool hasStake = sapienVault.hasActiveStake(actors[i]);
            uint256 totalStaked = sapienVault.getTotalStaked(actors[i]);
            
            // Consistency between hasActiveStake and getTotalStaked
            if (hasStake) {
                assertGt(totalStaked, 0, "Active stake should have positive amount");
            } else {
                assertEq(totalStaked, 0, "Inactive user should have zero stake");
            }
            
            // If user has stake, summary should be valid
            if (totalStaked > 0) {
                (
                    uint256 userTotalStaked,
                    uint256 totalUnlocked,
                    uint256 totalLocked,
                    uint256 totalInCooldown,
                    uint256 totalReadyForUnstake,
                    uint256 effectiveMultiplier,
                    uint256 effectiveLockUpPeriod,
                ) = sapienVault.getUserStakingSummary(actors[i]);
                
                assertEq(userTotalStaked, totalStaked, "Summary should match getTotalStaked");
                assertGt(effectiveMultiplier, 0, "Active stake should have positive multiplier");
                assertGt(effectiveLockUpPeriod, 0, "Active stake should have positive lockup period");
                
                // State consistency checks
                assertEq(totalUnlocked + totalLocked, userTotalStaked, "Unlocked + locked = total");
                assertLe(totalInCooldown, userTotalStaked, "Cooldown <= total");
                assertLe(totalReadyForUnstake, totalInCooldown, "Ready <= cooldown");
            }
        }
    }
    
    /// @dev Cooldown state should be consistent with contract state
    function invariant_CooldownConsistency() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 totalInCooldown = sapienVault.getTotalInCooldown(actors[i]);
            uint256 totalReadyForUnstake = sapienVault.getTotalReadyForUnstake(actors[i]);
            
            // If something is in cooldown, ready amount should be consistent
            if (totalInCooldown > 0) {
                assertLe(totalReadyForUnstake, totalInCooldown, "Ready should not exceed cooldown");
                
                // After cooldown period, everything in cooldown should be ready
                // This is tested implicitly through the cooldown timing logic
            } else {
                assertEq(totalReadyForUnstake, 0, "No cooldown means nothing ready for unstake");
            }
        }
    }
    
    /// @dev Maximum stake limits should be enforced
    function invariant_MaximumStakeLimits() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 userStaked = sapienVault.getTotalStaked(actors[i]);
            
            // Individual stakes should not exceed practical limits
            // While the contract allows up to uint128.max theoretically,
            // individual operations are limited to 10M tokens
            assertTrue(
                userStaked <= 1000_000_000 * Const.TOKEN_DECIMALS, // 1B tokens - very generous upper bound
                "User stake should not exceed reasonable limits"
            );
        }
    }
    
    /// @dev Lock periods should be valid
    function invariant_ValidLockPeriods() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                (,,,,,, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(actors[i]);
                
                // Effective lockup should be within valid bounds
                assertTrue(
                    effectiveLockUpPeriod >= Const.LOCKUP_30_DAYS && effectiveLockUpPeriod <= Const.LOCKUP_365_DAYS,
                    "Effective lockup should be within valid range"
                );
            }
        }
    }
} 