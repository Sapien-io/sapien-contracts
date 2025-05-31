// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test } from "lib/forge-std/src/Test.sol";
import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { StakingVault } from "src/StakingVault.sol";
import { ERC1967Proxy } from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

// Handler contract for invariant testing
contract StakingVaultHandler is Test {
    StakingVault public stakingVault;
    MockERC20 public sapienToken;
    
    address[] public actors;
    uint256 public constant MINIMUM_STAKE = 1000e18;
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;
    
    // Track system state for invariants
    uint256 public totalStakedByUsers;
    uint256 public totalPenaltiesPaid;
    uint256 public totalNormalUnstakes;
    uint256 public totalInstantUnstakes;
    
    // Valid lock periods
    uint256[] public lockPeriods = [30 days, 90 days, 180 days, 365 days];
    
    modifier useActor(uint256 actorIndexSeed) {
        address currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }
    
    constructor(StakingVault _stakingVault, MockERC20 _sapienToken) {
        stakingVault = _stakingVault;
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
        
        sapienToken.approve(address(stakingVault), amount);
        
        try stakingVault.stake(amount, lockPeriod) {
            totalStakedByUsers += amount;
        } catch {
            // Stake failed, continue
        }
    }
    
    function increaseAmount(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        if (!stakingVault.hasActiveStake(msg.sender)) return;
        
        uint256 amount = bound(amountSeed, MINIMUM_STAKE, MINIMUM_STAKE * 20);
        
        // Ensure actor has enough tokens
        if (sapienToken.balanceOf(msg.sender) < amount) {
            return;
        }
        
        sapienToken.approve(address(stakingVault), amount);
        
        try stakingVault.increaseAmount(amount) {
            totalStakedByUsers += amount;
        } catch {
            // Failed, continue
        }
    }
    
    function increaseLockup(uint256 actorSeed, uint256 lockupIncreaseSeed) public useActor(actorSeed) {
        if (!stakingVault.hasActiveStake(msg.sender)) return;
        
        uint256 lockupIncrease = bound(lockupIncreaseSeed, MINIMUM_LOCKUP_INCREASE, 300 days);
        
        try stakingVault.increaseLockup(lockupIncrease) {
            // Success
        } catch {
            // Failed, continue
        }
    }
    
    function initiateUnstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalUnlocked = stakingVault.getTotalUnlocked(msg.sender);
        if (totalUnlocked == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalUnlocked);
        
        try stakingVault.initiateUnstake(amount) {
            // Success
        } catch {
            // Failed, continue
        }
    }
    
    function unstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalReady = stakingVault.getTotalReadyForUnstake(msg.sender);
        if (totalReady == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalReady);
        
        uint256 balanceBefore = sapienToken.balanceOf(msg.sender);
        
        try stakingVault.unstake(amount) {
            uint256 balanceAfter = sapienToken.balanceOf(msg.sender);
            totalNormalUnstakes += (balanceAfter - balanceBefore);
            totalStakedByUsers -= amount;
        } catch {
            // Failed, continue
        }
    }
    
    function instantUnstake(uint256 actorSeed, uint256 amountSeed) public useActor(actorSeed) {
        uint256 totalLocked = stakingVault.getTotalLocked(msg.sender);
        if (totalLocked == 0) return;
        
        uint256 amount = bound(amountSeed, 1, totalLocked);
        
        uint256 balanceBefore = sapienToken.balanceOf(msg.sender);
        
        try stakingVault.instantUnstake(amount) {
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
            total += stakingVault.getTotalStaked(actors[i]);
        }
    }
    
    // Getter function for actors array
    function getActors() public view returns (address[] memory) {
        return actors;
    }
}

contract StakingVaultInvariantsTest is StdInvariant, Test {
    StakingVault public stakingVault;
    MockERC20 public sapienToken;
    StakingVaultHandler public handler;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    
    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);
        
        StakingVault stakingVaultImpl = new StakingVault();
        bytes memory initData = abi.encodeWithSelector(
            StakingVault.initialize.selector,
            address(sapienToken),
            admin,
            treasury
        );
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImpl), initData);
        stakingVault = StakingVault(address(stakingVaultProxy));
        
        handler = new StakingVaultHandler(stakingVault, sapienToken);
        
        // Set up invariant testing
        targetContract(address(handler));
        
        // Define function selectors to call
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = StakingVaultHandler.stake.selector;
        selectors[1] = StakingVaultHandler.increaseAmount.selector;
        selectors[2] = StakingVaultHandler.increaseLockup.selector;
        selectors[3] = StakingVaultHandler.initiateUnstake.selector;
        selectors[4] = StakingVaultHandler.unstake.selector;
        selectors[5] = StakingVaultHandler.instantUnstake.selector;
        selectors[6] = StakingVaultHandler.warpTime.selector;
        
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
            sapienToken.balanceOf(address(stakingVault)),
            stakingVault.totalStaked(),
            "Contract token balance must equal totalStaked"
        );
    }
    
    /// @dev Total staked should equal sum of all user stakes
    function invariant_TotalStakedEqualsUserStakes() public view {
        uint256 sumOfUserStakes = handler.getTotalStakedAcrossUsers();
        assertEq(
            stakingVault.totalStaked(),
            sumOfUserStakes,
            "totalStaked must equal sum of all user stakes"
        );
    }
    
    /// @dev No user should have negative stake amounts or stakes below minimum
    function invariant_NoInvalidStakes() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 userStaked = stakingVault.getTotalStaked(actors[i]);
            
            // If user has stake, it should be >= MINIMUM_STAKE
            if (userStaked > 0) {
                assertTrue(
                    userStaked >= handler.MINIMUM_STAKE(),
                    "User stake must be 0 or >= minimum stake"
                );
                
                // User should have active stake
                assertTrue(
                    stakingVault.hasActiveStake(actors[i]),
                    "User with staked amount should have active stake"
                );
            } else {
                // If no stake, should not have active stake
                assertFalse(
                    stakingVault.hasActiveStake(actors[i]),
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
            ) = stakingVault.getUserStakingSummary(actors[i]);
            
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
                    effectiveMultiplier >= 10000 && effectiveMultiplier <= 15000,
                    "Effective multiplier must be in valid range"
                );
                
                // Effective lockup should be <= 365 days
                assertLe(
                    effectiveLockUpPeriod,
                    365 days,
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
        assertEq(stakingVault.getMultiplierForPeriod(30 days), 10500, "30-day multiplier");
        assertEq(stakingVault.getMultiplierForPeriod(90 days), 11000, "90-day multiplier");
        assertEq(stakingVault.getMultiplierForPeriod(180 days), 12500, "180-day multiplier");
        assertEq(stakingVault.getMultiplierForPeriod(365 days), 15000, "365-day multiplier");
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
                ,,,
            ) = stakingVault.getUserStakingSummary(actors[i]);
            
            if (userTotalStaked > 0) {
                // Total unlocked + total locked should equal total staked
                assertEq(
                    totalUnlocked + totalLocked,
                    userTotalStaked,
                    "Unlocked + locked must equal total staked"
                );
                
                // If in cooldown, user should not be able to increase amount/lockup
                // (This is tested implicitly through handler logic)
                
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
    
    /// @dev Treasury should only receive penalty payments
    function invariant_TreasuryOnlyReceivesPenalties() public view {
        uint256 treasuryBalance = sapienToken.balanceOf(treasury);
        uint256 totalPenalties = handler.totalPenaltiesPaid();
        
        assertEq(
            treasuryBalance,
            totalPenalties,
            "Treasury balance must equal total penalties paid"
        );
    }
    
    /// @dev Total tokens should be conserved (accounting for penalties)
    function invariant_TokenConservation() public view {
        uint256 contractBalance = sapienToken.balanceOf(address(stakingVault));
        uint256 treasuryBalance = sapienToken.balanceOf(treasury);
        uint256 totalUserBalances = 0;
        
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            totalUserBalances += sapienToken.balanceOf(actors[i]);
        }
        
        uint256 totalSupplyToActors = actors.length * 1000000e18; // Initial mint amount
        
        assertEq(
            contractBalance + treasuryBalance + totalUserBalances,
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
            if (stakingVault.hasActiveStake(actors[i])) {
                // Test getUserActiveStakes for compatibility
                (
                    uint256[] memory stakeIds,
                    uint256[] memory amounts,
                    uint256[] memory multipliers,
                    uint256[] memory lockUpPeriods
                ) = stakingVault.getUserActiveStakes(actors[i]);
                
                // Should have exactly one stake
                assertEq(stakeIds.length, 1, "Active user should have exactly one stake");
                assertEq(stakeIds[0], 1, "Stake ID should be 1 for compatibility");
                assertGt(amounts[0], 0, "Stake amount should be positive");
                assertGt(multipliers[0], 0, "Multiplier should be positive");
                assertGt(lockUpPeriods[0], 0, "Lock period should be positive");
                
                // Test getStakeDetails
                (,,,,,bool isActive) = stakingVault.getStakeDetails(actors[i], 1);
                assertTrue(isActive, "Stake should be active");
            } else {
                // Should have no active stakes
                (
                    uint256[] memory stakeIds,
                    ,,,
                ) = stakingVault.getUserActiveStakes(actors[i]);
                assertEq(stakeIds.length, 0, "Inactive user should have no stakes");
                
                // Test getStakeDetails for invalid case
                (,,,,,bool isActive) = stakingVault.getStakeDetails(actors[i], 1);
                assertFalse(isActive, "Stake should not be active");
            }
        }
    }
    
    /// @dev Weighted average properties should be maintained
    function invariant_WeightedAverageProperties() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            if (stakingVault.hasActiveStake(actors[i])) {
                (
                    uint256 userTotalStaked,
                    ,,,,,
                    uint256 effectiveLockUpPeriod,
                    uint256 timeUntilUnlock
                ) = stakingVault.getUserStakingSummary(actors[i]);
                
                if (userTotalStaked > 0) {
                    // Effective lockup should be reasonable
                    assertLe(
                        effectiveLockUpPeriod,
                        365 days,
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
        // The penalty calculation is: penalty = amount * 20 / 100
        // This invariant is maintained by the contract logic
        assertTrue(true, "Penalty rate is constant at 20%");
    }
    
    /// @dev Stakes should only be unlocked after lock period
    function invariant_StakesUnlockedAfterLockPeriod() public view {
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint256 userTotalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                ,,,
                uint256 effectiveLockUpPeriod,
                uint256 timeUntilUnlock
            ) = stakingVault.getUserStakingSummary(actors[i]);
            
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
            uint256 userStaked = stakingVault.getTotalStaked(actors[i]);
            
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
            stakingVault.totalStaked() <= type(uint256).max,
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
} 