// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SapienQA} from "src/SapienQA.sol";
import {SapienVault} from "src/SapienVault.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienQA} from "src/interfaces/ISapienQA.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title TenderlyQAIntegrationTest
 * @notice Integration tests for SapienQA penalty system against Tenderly deployed contracts
 * @dev Tests all QA operations, penalty enforcement, and vault integration on Base mainnet fork
 * 
 * SETUP REQUIREMENTS:
 * - Set TENDERLY_VIRTUAL_TESTNET_RPC_URL environment variable
 * - Set TENDERLY_TEST_PRIVATE_KEY environment variable to the private key corresponding 
 *   to QA_MANAGER address 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9
 * - Run with: FOUNDRY_PROFILE=tenderly forge test --match-contract TenderlyQAIntegrationTest
 */
contract TenderlyQAIntegrationTest is Test {
    // Tenderly deployed contract addresses
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant SAPIEN_VAULT_PROXY = 0x35977d540799db1e8910c00F476a879E2c0e1a24;
    address public constant SAPIEN_QA = 0x5ed9315ab0274B0C546b71ed5a7ABE9982FF1E8D;
    address public constant TREASURY = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant QA_MANAGER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    
    SapienQA public sapienQA;
    SapienVault public sapienVault;
    SapienToken public sapienToken;
    
    // Test user personas
    address public regularUser = makeAddr("regularUser");
    address public repeatOffender = makeAddr("repeatOffender");
    address public minorViolator = makeAddr("minorViolator");
    address public majorViolator = makeAddr("majorViolator");
    address public severeViolator = makeAddr("severeViolator");
    address public qaVictim = makeAddr("qaVictim");
    address public cleanUser = makeAddr("cleanUser");
    address public progressiveViolator = makeAddr("progressiveViolator");
    
    // Test constants
    uint256 public constant USER_INITIAL_BALANCE = 1_000_000 * 1e18;
    uint256 public constant STAKE_AMOUNT = 100_000 * 1e18;
    uint256 public constant LARGE_STAKE = 500_000 * 1e18;
    uint256 public constant SMALL_PENALTY = 1_000 * 1e18;
    uint256 public constant MEDIUM_PENALTY = 5_000 * 1e18;
    uint256 public constant LARGE_PENALTY = 25_000 * 1e18;
    
    // EIP-712 constants
    bytes32 public constant QA_DECISION_TYPEHASH = 
        keccak256("QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,string reason)");
    
    // Test manager private key for signatures
    uint256 public QA_MANAGER_PRIVATE_KEY;
    
    // Decision counter for unique decision IDs
    uint256 public decisionCounter = 1;
    
    function setUp() public {
        // Initialize private key from environment with fallback
        try vm.envUint("TENDERLY_TEST_PRIVATE_KEY") returns (uint256 privateKey) {
            QA_MANAGER_PRIVATE_KEY = privateKey;
        } catch {
            // Fallback to default test key if environment variable is not set
            // NOTE: This will fail with UnauthorizedSigner unless TENDERLY_TEST_PRIVATE_KEY is set 
            // to the private key corresponding to QA_MANAGER address 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9
            QA_MANAGER_PRIVATE_KEY = 0x000000000000000000000000000000000000000000000000000000000000dead;
        }
        
        // Setup fork to use Tenderly Base mainnet virtual testnet
        string memory rpcUrl = vm.envString("TENDERLY_VIRTUAL_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        
        // Initialize contract interfaces
        sapienQA = SapienQA(SAPIEN_QA);
        sapienVault = SapienVault(SAPIEN_VAULT_PROXY);
        sapienToken = SapienToken(SAPIEN_TOKEN);
        
        // Setup test users with initial balances and stakes
        setupTestUsers();
    }
    
    function setupTestUsers() internal {
        address[] memory users = new address[](8);
        users[0] = regularUser;
        users[1] = repeatOffender;
        users[2] = minorViolator;
        users[3] = majorViolator;
        users[4] = severeViolator;
        users[5] = qaVictim;
        users[6] = cleanUser;
        users[7] = progressiveViolator;
        
        // Fund users and have them stake
        vm.startPrank(TREASURY);
        for (uint256 i = 0; i < users.length; i++) {
            sapienToken.transfer(users[i], USER_INITIAL_BALANCE);
        }
        vm.stopPrank();
        
        // Users stake tokens (needed for QA penalties)
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
            sapienVault.stake(STAKE_AMOUNT, Const.LOCKUP_90_DAYS);
            vm.stopPrank();
        }
    }
    
    /**
     * @notice Test basic warning processing without penalties
     */
    function test_QA_BasicWarningProcessing() public {
        bytes32 decisionId = generateDecisionId();
        string memory reason = "First time violation - warning issued";
        
        // Create QA decision signature for warning
        bytes memory signature = createQASignature(
            decisionId,
            regularUser,
            uint8(ISapienQA.QAActionType.WARNING),
            0, // No penalty for warnings
            reason
        );
        
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountBefore = sapienVault.getTotalStaked(regularUser);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.WARNING,
            0,
            decisionId,
            reason,
            signature
        );
        
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter = sapienVault.getTotalStaked(regularUser);
        
        // Verify no financial penalty
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore);
        assertEq(stakeAmountAfter, stakeAmountBefore);
        
        // Verify decision was processed
        assertTrue(sapienQA.isDecisionProcessed(decisionId));
        
        // Verify QA record was created
        assertEq(sapienQA.getUserQARecordCount(regularUser), 1);
        
        console.log("[PASS] Basic warning processing validated");
    }
    
    /**
     * @notice Test minor penalty enforcement
     */
    function test_QA_MinorPenaltyEnforcement() public {
        bytes32 decisionId = generateDecisionId();
        uint256 penaltyAmount = SMALL_PENALTY;
        string memory reason = "Minor guideline violation";
        
        bytes memory signature = createQASignature(
            decisionId,
            minorViolator,
            uint8(ISapienQA.QAActionType.MINOR_PENALTY),
            penaltyAmount,
            reason
        );
        
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountBefore = sapienVault.getTotalStaked(minorViolator);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            minorViolator,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            decisionId,
            reason,
            signature
        );
        
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter = sapienVault.getTotalStaked(minorViolator);
        
        // Verify penalty was transferred to treasury
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, penaltyAmount);
        
        // Verify user's stake was reduced
        assertEq(stakeAmountBefore - stakeAmountAfter, penaltyAmount);
        
        console.log("[PASS] Minor penalty enforcement validated");
    }
    
    /**
     * @notice Test major penalty enforcement
     */
    function test_QA_MajorPenaltyEnforcement() public {
        bytes32 decisionId = generateDecisionId();
        uint256 penaltyAmount = MEDIUM_PENALTY;
        string memory reason = "Significant misconduct";
        
        bytes memory signature = createQASignature(
            decisionId,
            majorViolator,
            uint8(ISapienQA.QAActionType.MAJOR_PENALTY),
            penaltyAmount,
            reason
        );
        
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountBefore = sapienVault.getTotalStaked(majorViolator);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            majorViolator,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            penaltyAmount,
            decisionId,
            reason,
            signature
        );
        
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter = sapienVault.getTotalStaked(majorViolator);
        
        // Verify penalty enforcement
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, penaltyAmount);
        assertEq(stakeAmountBefore - stakeAmountAfter, penaltyAmount);
        
        console.log("[PASS] Major penalty enforcement validated");
    }
    
    /**
     * @notice Test severe penalty enforcement
     */
    function test_QA_SeverePenaltyEnforcement() public {
        bytes32 decisionId = generateDecisionId();
        uint256 penaltyAmount = LARGE_PENALTY;
        string memory reason = "Serious violation requiring severe penalty";
        
        bytes memory signature = createQASignature(
            decisionId,
            severeViolator,
            uint8(ISapienQA.QAActionType.SEVERE_PENALTY),
            penaltyAmount,
            reason
        );
        
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountBefore = sapienVault.getTotalStaked(severeViolator);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            severeViolator,
            ISapienQA.QAActionType.SEVERE_PENALTY,
            penaltyAmount,
            decisionId,
            reason,
            signature
        );
        
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter = sapienVault.getTotalStaked(severeViolator);
        
        // Verify penalty enforcement
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, penaltyAmount);
        assertEq(stakeAmountBefore - stakeAmountAfter, penaltyAmount);
        
        console.log("[PASS] Severe penalty enforcement validated");
    }
    
    /**
     * @notice Test progressive enforcement escalation
     */
    function test_QA_ProgressiveEnforcementEscalation() public {
        // Phase 1: First warning
        processQADecision(
            progressiveViolator,
            ISapienQA.QAActionType.WARNING,
            0,
            "First violation warning"
        );
        
        // Phase 2: Second warning
        processQADecision(
            progressiveViolator,
            ISapienQA.QAActionType.WARNING,
            0,
            "Second violation warning"
        );
        
        // Phase 3: Minor penalty
        uint256 minorPenalty = 2000 * 1e18;
        uint256 treasuryBefore = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountBefore = sapienVault.getTotalStaked(progressiveViolator);
        
        processQADecision(
            progressiveViolator,
            ISapienQA.QAActionType.MINOR_PENALTY,
            minorPenalty,
            "Continued violations - minor penalty"
        );
        
        uint256 treasuryAfter1 = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter1 = sapienVault.getTotalStaked(progressiveViolator);
        
        // Verify minor penalty
        assertEq(treasuryAfter1 - treasuryBefore, minorPenalty);
        assertEq(stakeAmountBefore - stakeAmountAfter1, minorPenalty);
        
        // Phase 4: Major penalty
        uint256 majorPenalty = 8000 * 1e18;
        processQADecision(
            progressiveViolator,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            majorPenalty,
            "Escalated violations - major penalty"
        );
        
        uint256 treasuryAfter2 = sapienToken.balanceOf(TREASURY);
        uint256 stakeAmountAfter2 = sapienVault.getTotalStaked(progressiveViolator);
        
        // Verify major penalty
        assertEq(treasuryAfter2 - treasuryAfter1, majorPenalty);
        assertEq(stakeAmountAfter1 - stakeAmountAfter2, majorPenalty);
        
        // Verify total QA records
        assertEq(sapienQA.getUserQARecordCount(progressiveViolator), 4);
        
        console.log("[PASS] Progressive enforcement escalation validated");
    }
    
    /**
     * @notice Test partial penalty when user has insufficient stake
     */
    function test_QA_PartialPenaltyInsufficientStake() public {
        // First reduce user's stake with a large penalty
        processQADecision(
            qaVictim,
            ISapienQA.QAActionType.SEVERE_PENALTY,
            STAKE_AMOUNT / 2, // Remove half the stake
            "Large penalty reducing available stake"
        );
        
        // Get current stake amount
        uint256 availableStake = sapienVault.getTotalStaked(qaVictim);
        
        // Try to penalty more than available
        uint256 excessivePenalty = availableStake + 10_000 * 1e18;
        bytes32 decisionId = generateDecisionId();
        bytes memory signature = createQASignature(
            decisionId,
            qaVictim,
            uint8(ISapienQA.QAActionType.MAJOR_PENALTY),
            excessivePenalty,
            "Attempting penalty exceeding available stake"
        );
        
        uint256 treasuryBefore = sapienToken.balanceOf(TREASURY);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            qaVictim,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            excessivePenalty,
            decisionId,
            "Attempting penalty exceeding available stake",
            signature
        );
        
        uint256 treasuryAfter = sapienToken.balanceOf(TREASURY);
        
        // Should only collect available stake, not the full penalty
        assertEq(treasuryAfter - treasuryBefore, availableStake);
        
        // User should now have zero stake
        uint256 finalStakeAmount = sapienVault.getTotalStaked(qaVictim);
        assertEq(finalStakeAmount, 0);
        
        console.log("[PASS] Partial penalty for insufficient stake validated");
    }
    
    /**
     * @notice Test QA penalty processing when user has no stake
     */
    function test_QA_PenaltyProcessingNoStake() public {
        // Create a user with no stake
        address noStakeUser = makeAddr("noStakeUser");
        vm.prank(TREASURY);
        sapienToken.transfer(noStakeUser, USER_INITIAL_BALANCE);
        
        // Try to apply penalty to user with no stake
        bytes32 decisionId = generateDecisionId();
        bytes memory signature = createQASignature(
            decisionId,
            noStakeUser,
            uint8(ISapienQA.QAActionType.MINOR_PENALTY),
            SMALL_PENALTY,
            "Penalty for user with no stake"
        );
        
        uint256 treasuryBefore = sapienToken.balanceOf(TREASURY);
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            noStakeUser,
            ISapienQA.QAActionType.MINOR_PENALTY,
            SMALL_PENALTY,
            decisionId,
            "Penalty for user with no stake",
            signature
        );
        
        uint256 treasuryAfter = sapienToken.balanceOf(TREASURY);
        
        // No tokens should be transferred since user has no stake
        assertEq(treasuryAfter, treasuryBefore);
        
        // Decision should still be processed and recorded
        assertTrue(sapienQA.isDecisionProcessed(decisionId));
        assertEq(sapienQA.getUserQARecordCount(noStakeUser), 1);
        
        console.log("[PASS] QA penalty processing with no stake validated");
    }
    
    /**
     * @notice Test error conditions and access control
     */
    function test_QA_ErrorConditionsAndAccessControl() public {
        bytes32 decisionId = generateDecisionId();
        bytes memory signature = createQASignature(
            decisionId,
            regularUser,
            uint8(ISapienQA.QAActionType.MINOR_PENALTY),
            SMALL_PENALTY,
            "Test penalty"
        );
        
        // Test unauthorized access (non-QA manager)
        vm.prank(regularUser);
        vm.expectRevert();
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.MINOR_PENALTY,
            SMALL_PENALTY,
            decisionId,
            "Test penalty",
            signature
        );
        
        // Process decision successfully
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.MINOR_PENALTY,
            SMALL_PENALTY,
            decisionId,
            "Test penalty",
            signature
        );
        
        // Test replay attack prevention (duplicate decision ID)
        vm.prank(QA_MANAGER);
        vm.expectRevert();
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.MINOR_PENALTY,
            SMALL_PENALTY,
            decisionId,
            "Test penalty",
            signature
        );
        
        console.log("[PASS] Error conditions and access control validated");
    }
    
    /**
     * @notice Test signature validation with different parameters
     */
    function test_QA_SignatureValidation() public {
        bytes32 decisionId = generateDecisionId();
        uint256 penaltyAmount = SMALL_PENALTY;
        string memory reason = "Test signature validation";
        
        // Create valid signature
        bytes memory validSignature = createQASignature(
            decisionId,
            regularUser,
            uint8(ISapienQA.QAActionType.MINOR_PENALTY),
            penaltyAmount,
            reason
        );
        
        // Test signature with wrong user
        vm.prank(QA_MANAGER);
        vm.expectRevert();
        sapienQA.processQualityAssessment(
            minorViolator, // Different user
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            decisionId,
            reason,
            validSignature
        );
        
        // Test signature with wrong amount
        vm.prank(QA_MANAGER);
        vm.expectRevert();
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount * 2, // Different amount
            decisionId,
            reason,
            validSignature
        );
        
        // Test signature with wrong action type
        vm.prank(QA_MANAGER);
        vm.expectRevert();
        sapienQA.processQualityAssessment(
            regularUser,
            ISapienQA.QAActionType.MAJOR_PENALTY, // Different action type
            penaltyAmount,
            decisionId,
            reason,
            validSignature
        );
        
        console.log("[PASS] Signature validation edge cases validated");
    }
    
    /**
     * @notice Test multiple penalties on same user over time
     */
    function test_QA_MultiplePenaltiesOverTime() public {
        // Initial state
        uint256 initialTreasury = sapienToken.balanceOf(TREASURY);
        uint256 initialStakeAmount = sapienVault.getTotalStaked(repeatOffender);
        
        // Apply multiple penalties over time
        vm.warp(block.timestamp + 1 days);
        processQADecision(
            repeatOffender,
            ISapienQA.QAActionType.WARNING,
            0,
            "First warning"
        );
        
        vm.warp(block.timestamp + 7 days);
        processQADecision(
            repeatOffender,
            ISapienQA.QAActionType.MINOR_PENALTY,
            2000 * 1e18,
            "First penalty"
        );
        
        vm.warp(block.timestamp + 14 days);
        processQADecision(
            repeatOffender,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            8000 * 1e18,
            "Second penalty"
        );
        
        vm.warp(block.timestamp + 30 days);
        processQADecision(
            repeatOffender,
            ISapienQA.QAActionType.SEVERE_PENALTY,
            20000 * 1e18,
            "Third penalty"
        );
        
        // Verify cumulative effects
        uint256 finalTreasury = sapienToken.balanceOf(TREASURY);
        uint256 finalStakeAmount = sapienVault.getTotalStaked(repeatOffender);
        
        uint256 totalPenalties = 2000 * 1e18 + 8000 * 1e18 + 20000 * 1e18;
        assertEq(finalTreasury - initialTreasury, totalPenalties);
        assertEq(initialStakeAmount - finalStakeAmount, totalPenalties);
        
        // Verify all QA records were created
        assertEq(sapienQA.getUserQARecordCount(repeatOffender), 4);
        
        console.log("[PASS] Multiple penalties over time validated");
    }
    
    /**
     * @notice Test QA statistics and record keeping
     */
    function test_QA_StatisticsAndRecordKeeping() public {
        // Process various QA actions
        processQADecision(cleanUser, ISapienQA.QAActionType.WARNING, 0, "Warning 1");
        processQADecision(cleanUser, ISapienQA.QAActionType.WARNING, 0, "Warning 2");
        processQADecision(cleanUser, ISapienQA.QAActionType.MINOR_PENALTY, 1000 * 1e18, "Minor penalty");
        
        // Verify record count
        assertEq(sapienQA.getUserQARecordCount(cleanUser), 3);
        
        // Test that other users' records are isolated
        assertEq(sapienQA.getUserQARecordCount(regularUser), 0);
        
        console.log("[PASS] QA statistics and record keeping validated");
    }
    
    // ============ Helper Functions ============
    
    function generateDecisionId() internal returns (bytes32) {
        bytes32 decisionId = keccak256(abi.encodePacked("decision", decisionCounter, block.timestamp));
        decisionCounter++;
        return decisionId;
    }
    
    function createQASignature(
        bytes32 decisionId,
        address user,
        uint8 actionType,
        uint256 penaltyAmount,
        string memory reason
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            QA_DECISION_TYPEHASH,
            user,
            actionType,
            penaltyAmount,
            decisionId,
            keccak256(bytes(reason))
        ));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SapienQA"),
                keccak256("1"),
                block.chainid,
                address(sapienQA)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(QA_MANAGER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function processQADecision(
        address user,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        string memory reason
    ) internal {
        bytes32 decisionId = generateDecisionId();
        bytes memory signature = createQASignature(
            decisionId,
            user,
            uint8(actionType),
            penaltyAmount,
            reason
        );
        
        vm.prank(QA_MANAGER);
        sapienQA.processQualityAssessment(
            user,
            actionType,
            penaltyAmount,
            decisionId,
            reason,
            signature
        );
    }
}