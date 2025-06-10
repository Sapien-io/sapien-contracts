// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title JuneAudit_SAP_3
 * @dev Test cases for SAP-3: QA Penalty Can Be Avoided by Unstaking Before Penalty
 *
 * The vulnerability allows users to avoid QA penalties by using earlyUnstake()
 * to immediately withdraw their funds paying only 20% penalty, thus circumventing
 * larger QA penalties that could be applied during the normal 2-day cooldown period.
 */
contract JuneAudit_SAP_3 is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    uint256 public constant STAKE_AMOUNT = 1000 * 1e18;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY_RATE = 20; // 20%

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1;

    function setUp() public {
        user1 = makeAddr("user1");

        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory vaultInitData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            makeAddr("pauseManager"),
            treasury,
            makeAddr("dummyQA") // Dummy QA address for testing
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), vaultInitData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Provide tokens to user
        sapienToken.mint(user1, STAKE_AMOUNT);

        // User stakes tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
        sapienVault.stake(STAKE_AMOUNT, Const.LOCKUP_30_DAYS);
        vm.stopPrank();

        // Fast forward to after lock period
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);
    }

    /**
     * @notice Test that demonstrates the fix where users can NO LONGER instantly unstake
     * during the lock period - now cooldown is enforced for early unstake
     */
    function test_Vault_SAP_3_EarlyUnstakeCooldownEnforced() public {
        console.log("=== SAP-3: Early Unstake Cooldown Fix Test ===");

        // Reset to lock period to allow earlyUnstake initiation
        vm.warp(block.timestamp - Const.LOCKUP_30_DAYS - 1);

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 userStakeBefore = sapienVault.getTotalStaked(user1);

        console.log("Initial user balance:", userBalanceBefore);
        console.log("Initial user stake:", userStakeBefore);

        // Scenario: User tries to use earlyUnstake instantly (the old vulnerability)
        // But now they need to initiate cooldown first

        uint256 earlyUnstakeAmount = STAKE_AMOUNT;

        // User tries to call earlyUnstake directly - should fail
        vm.prank(user1);
        vm.expectRevert(ISapienVault.EarlyUnstakeCooldownRequired.selector);
        sapienVault.earlyUnstake(earlyUnstakeAmount);

        console.log("Step 1: Direct earlyUnstake blocked - cooldown required");

        // User initiates early unstake cooldown
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(earlyUnstakeAmount);

        console.log("Step 2: Early unstake cooldown initiated");

        // User tries to earlyUnstake immediately after initiation - should fail
        vm.prank(user1);
        vm.expectRevert(ISapienVault.EarlyUnstakeCooldownRequired.selector);
        sapienVault.earlyUnstake(earlyUnstakeAmount);

        console.log("Step 3: Early unstake still blocked during cooldown period");

        // During the cooldown period, the user is vulnerable to QA penalties
        // This demonstrates that the 2-day window exists for penalty application

        console.log("Step 4: User must wait 2 days before early unstake");
        console.log("During this time, QA penalties can be applied");

        // Verify user still has full stake (no instant withdrawal)
        uint256 userStakeAfter = sapienVault.getTotalStaked(user1);
        assertEq(userStakeAfter, userStakeBefore, "User stake should remain unchanged");

        console.log("=== FIX DEMONSTRATED ===");
        console.log("User CANNOT instantly unstake to avoid penalties");
        console.log("2-day cooldown window enforced for early unstake");
        console.log("QA penalties can be applied during cooldown period");
    }

    /**
     * @notice Test showing normal unstaking flow with cooldown
     */
    function test_Vault_SAP_3_NormalUnstakingHasCooldown() public {
        console.log("=== Normal unstaking has proper cooldown ===");

        uint256 unstakeAmount = STAKE_AMOUNT / 2; // 500 tokens

        // User initiates normal unstake
        vm.prank(user1);
        sapienVault.initiateUnstake(unstakeAmount);

        console.log("Normal unstake initiated for:", unstakeAmount);
        console.log("User must wait 2 days for cooldown completion");

        // Verify user cannot immediately unstake
        vm.prank(user1);
        vm.expectRevert(ISapienVault.NotReadyForUnstake.selector);
        sapienVault.unstake(unstakeAmount);

        console.log("Immediate unstake blocked - cooldown enforced");

        // Fast forward past cooldown
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);

        // Now unstake should work
        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        vm.prank(user1);
        sapienVault.unstake(unstakeAmount);
        uint256 userBalanceAfter = sapienToken.balanceOf(user1);

        assertEq(userBalanceAfter - userBalanceBefore, unstakeAmount, "User should receive full unstake amount");
        console.log("Unstake successful after cooldown completion");
    }

    /**
     * @notice Test that early unstake works correctly after cooldown period completion
     */
    function test_Vault_SAP_3_EarlyUnstakeWorksAfterCooldown() public {
        console.log("=== Early unstake after cooldown completion ===");

        // Reset to lock period to allow earlyUnstake initiation
        vm.warp(block.timestamp - Const.LOCKUP_30_DAYS - 1);

        uint256 earlyUnstakeAmount = STAKE_AMOUNT / 2; // 500 tokens
        uint256 expectedEarlyPenalty = (earlyUnstakeAmount * EARLY_WITHDRAWAL_PENALTY_RATE) / 100; // 100 tokens
        uint256 expectedPayout = earlyUnstakeAmount - expectedEarlyPenalty; // 400 tokens

        // User initiates early unstake cooldown
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(earlyUnstakeAmount);

        console.log("Early unstake cooldown initiated for:", earlyUnstakeAmount);

        // Fast forward past cooldown period
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 userStakeBefore = sapienVault.getTotalStaked(user1);

        // Now early unstake should work
        vm.prank(user1);
        sapienVault.earlyUnstake(earlyUnstakeAmount);

        uint256 userBalanceAfter = sapienToken.balanceOf(user1);
        uint256 userStakeAfter = sapienVault.getTotalStaked(user1);

        console.log("User balance before early unstake:", userBalanceBefore);
        console.log("User balance after early unstake:", userBalanceAfter);
        console.log("Expected payout:", expectedPayout);

        // Verify early unstake worked correctly
        assertEq(userBalanceAfter - userBalanceBefore, expectedPayout, "User should receive correct payout");
        assertEq(
            userStakeAfter, userStakeBefore - earlyUnstakeAmount, "Stake should be reduced by early unstake amount"
        );

        console.log("Early unstake completed successfully after cooldown");
        console.log("Penalty applied:", expectedEarlyPenalty);
        console.log("User received:", expectedPayout);
    }
}
