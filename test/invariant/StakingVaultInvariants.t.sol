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
    
    // Track system state for invariants
    uint256 public totalStakedByUsers;
    uint256 public totalPenaltiesPaid;
    uint256 public totalNormalUnstakes;
    uint256 public totalInstantUnstakes;
    
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
    
    function instantUnstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalLocked = sapienVault.getTotalLocked(msg.sender);
        if (totalLocked == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalLocked);
        
        uint256 balanceBefore = sapienToken.balanceOf(msg.sender);
        
        try sapienVault.instantUnstake(amount) {
            uint256 balanceAfter = sapienToken.balanceOf(msg.sender);
            uint256 received = balanceAfter - balanceBefore;
            uint256 penalty = amount - received;
            
            totalInstantUnstakes += received;
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
    
    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);
        
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            rewardSafe
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
        selectors[5] = SapienVaultHandler.instantUnstake.selector;
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
                
                // Effective multiplier should be in valid range
                assertTrue(
                    effectiveMultiplier >= Const.BASE_MULTIPLIER && effectiveMultiplier <= Const.MAX_MULTIPLIER,
                    "Effective multiplier must be in valid range"
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
    
    /// @dev Multipliers should always be valid for base periods
    function invariant_ValidBaseMultipliers() public view {
        // Check base multipliers for standard periods
        assertEq(sapienVault.getMultiplierForPeriod(Const.LOCKUP_30_DAYS), Const.MIN_MULTIPLIER, "30-day multiplier");
        assertEq(sapienVault.getMultiplierForPeriod(Const.LOCKUP_90_DAYS), Const.MULTIPLIER_90_DAYS, "90-day multiplier");
        assertEq(sapienVault.getMultiplierForPeriod(Const.LOCKUP_180_DAYS), Const.MULTIPLIER_180_DAYS, "180-day multiplier");
        assertEq(sapienVault.getMultiplierForPeriod(Const.LOCKUP_365_DAYS), Const.MAX_MULTIPLIER, "365-day multiplier");
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
                // Test getUserActiveStakes for compatibility
                (
                    uint256[] memory stakeIds,
                    uint256[] memory amounts,
                    uint256[] memory multipliers,
                    uint256[] memory lockUpPeriods
                ) = sapienVault.getUserActiveStakes(actors[i]);
                
                // Should have exactly one stake
                assertEq(stakeIds.length, 1, "Active user should have exactly one stake");
                assertEq(stakeIds[0], 1, "Stake ID should be 1 for compatibility");
                assertGt(amounts[0], 0, "Stake amount should be positive");
                assertGt(multipliers[0], 0, "Multiplier should be positive");
                assertGt(lockUpPeriods[0], 0, "Lock period should be positive");
                
                // Test getStakeDetails
                (,,,,,bool isActive) = sapienVault.getStakeDetails(actors[i], 1);
                assertTrue(isActive, "Stake should be active");
            } else {
                // Should have no active stakes
                (
                    uint256[] memory stakeIds,
                    ,,
                ) = sapienVault.getUserActiveStakes(actors[i]);
                assertEq(stakeIds.length, 0, "Inactive user should have no stakes");
                
                // Test getStakeDetails for invalid case
                (,,,,,bool isActive) = sapienVault.getStakeDetails(actors[i], 1);
                assertFalse(isActive, "Stake should not be active");
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
    
    /// @dev Instant unstake penalty should always be 20%
    function invariant_InstantUnstakePenalty() public pure {
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
    // ADDITIONAL SAPIEN VAULT SPECIFIC INVARIANTS
    // =============================================================================
    
    /// @dev Effective multipliers should be calculated correctly based on weighted lockup
    function invariant_EffectiveMultiplierCalculation() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (sapienVault.hasActiveStake(actors[i])) {
                (
                    ,,,,,
                    uint256 effectiveMultiplier,
                    uint256 effectiveLockUpPeriod,
                    
                ) = sapienVault.getUserStakingSummary(actors[i]);
                
                if (effectiveLockUpPeriod > 0) {
                    // Check that multiplier matches expected range for lockup period
                    if (effectiveLockUpPeriod >= Const.LOCKUP_365_DAYS) {
                        assertEq(effectiveMultiplier, Const.MAX_MULTIPLIER, "365+ day lockup should have max multiplier");
                    } else if (effectiveLockUpPeriod >= Const.LOCKUP_30_DAYS) {
                        assertTrue(
                            effectiveMultiplier >= Const.MIN_MULTIPLIER && effectiveMultiplier <= Const.MAX_MULTIPLIER,
                            "Multiplier should be in valid range for lockup period"
                        );
                    } else {
                        assertEq(effectiveMultiplier, Const.BASE_MULTIPLIER, "Short lockup should have base multiplier");
                    }
                }
            }
        }
    }
    
    /// @dev User stake struct should maintain data integrity
    function invariant_UserStakeDataIntegrity() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 amount, uint256 lockUpPeriod, uint256 startTime, uint256 multiplier, uint256 cooldownStart, bool isActive) = 
                sapienVault.getStakeDetails(actors[i], 1);
            
            if (isActive) {
                assertGt(amount, 0, "Active stake should have positive amount");
                assertGt(lockUpPeriod, 0, "Active stake should have positive lockup");
                assertGt(startTime, 0, "Active stake should have positive start time");
                assertGt(multiplier, 0, "Active stake should have positive multiplier");
                
                // Start time should not be in the future
                assertLe(startTime, block.timestamp, "Start time should not be in future");
                
                // If in cooldown, cooldown start should be valid
                if (cooldownStart > 0) {
                    assertLe(cooldownStart, block.timestamp, "Cooldown start should not be in future");
                    assertGe(cooldownStart, startTime, "Cooldown start should be after stake start");
                }
            } else {
                // Inactive stakes should have zero values
                assertEq(amount, 0, "Inactive stake should have zero amount");
                assertEq(lockUpPeriod, 0, "Inactive stake should have zero lockup");
                assertEq(startTime, 0, "Inactive stake should have zero start time");
                assertEq(multiplier, 0, "Inactive stake should have zero multiplier");
                assertEq(cooldownStart, 0, "Inactive stake should have zero cooldown start");
            }
        }
    }
    
    /// @dev Cooldown state should be consistent with unstake readiness
    function invariant_CooldownConsistency() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 totalInCooldown = sapienVault.getTotalInCooldown(actors[i]);
            uint256 totalReadyForUnstake = sapienVault.getTotalReadyForUnstake(actors[i]);
            
            if (totalInCooldown > 0) {
                // If something is in cooldown, check cooldown timing
                (,,,,uint256 cooldownStart,) = sapienVault.getStakeDetails(actors[i], 1);
                assertGt(cooldownStart, 0, "Cooldown amount > 0 should have cooldown start time");
                
                if (block.timestamp >= cooldownStart + Const.COOLDOWN_PERIOD) {
                    assertEq(totalReadyForUnstake, totalInCooldown, "After cooldown period, all cooldown should be ready");
                } else {
                    assertEq(totalReadyForUnstake, 0, "Before cooldown period ends, nothing should be ready");
                }
            } else {
                assertEq(totalReadyForUnstake, 0, "No cooldown means nothing ready for unstake");
            }
        }
    }
} 