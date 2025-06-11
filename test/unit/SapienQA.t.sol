// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienQA} from "src/SapienQA.sol";
import {SapienVault} from "src/SapienVault.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienQA} from "src/interfaces/ISapienQA.sol";
import {Constants} from "src/utils/Constants.sol";
import {Actors} from "script/Actors.sol";
import {ERC1967Proxy} from
    "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SapienQATest is Test {
    SapienQA public qaContract;
    SapienVault public vault;
    SapienToken public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public qaManager;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // Use a private key that we can control for the qaManager
    uint256 private constant QA_MANAGER_PRIVATE_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    // Sample decision for testing
    bytes32 constant DECISION_ID = keccak256("decision_001");
    string constant REASON = "Inappropriate behavior in community";
    uint256 constant PENALTY_AMOUNT = 1000 * 1e18; // 1000 tokens

    // Helper function to get current expiration time
    function _getExpiration() internal view returns (uint256) {
        return block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
    }

    event QualityAssessmentProcessed(
        address indexed userAddress,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string reason,
        address processor
    );

    event PenaltyReceived(address indexed userAddress, uint256 amount, bytes32 decisionId);

    event QAPenaltyPartial(address indexed userAddress, uint256 requestedAmount, uint256 actualAmount, string reason);

    event QAPenaltyFailed(address userAddress, uint256 amount, string reason);

    function setUp() public {
        // Generate qaManager address from the private key we control
        qaManager = vm.addr(QA_MANAGER_PRIVATE_KEY);

        // Deploy contracts
        token = new SapienToken(admin);

        // Deploy SapienVault implementation
        SapienVault vaultImpl = new SapienVault();

        // Create initialization data for the vault (we'll update with QA contract address later)
        bytes memory vaultInitData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(token),
            admin,
            makeAddr("pauseManager"),
            treasury,
            address(0x1) // Temporary QA address, will be updated when we deploy QA contract
        );

        // Deploy proxy
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInitData)));

        // Deploy QA contract with the vault address
        vm.startPrank(admin);
        qaContract = new SapienQA(treasury, address(vault), qaManager, admin);

        // Grant QA_SIGNER_ROLE to qaManager so they can sign decisions
        qaContract.grantRole(Constants.QA_SIGNER_ROLE, qaManager);

        // Grant the QA contract the SAPIEN_QA_ROLE on the vault
        vault.grantRole(Constants.SAPIEN_QA_ROLE, address(qaContract));

        vm.stopPrank();

        // Transfer tokens for testing (admin has all tokens from constructor)
        vm.startPrank(admin);
        token.transfer(user1, 10000 * 1e18);
        token.transfer(user2, 10000 * 1e18);
        vm.stopPrank();
    }

    function test_QA_BasicFunctionality() public view {
        // Test that the contract was deployed correctly
        assertEq(qaContract.treasury(), treasury);
        assertEq(qaContract.vaultContract(), address(vault));

        // Test that admin has admin role (admin deployed the contract)
        bytes32 adminRole = qaContract.DEFAULT_ADMIN_ROLE();
        assertTrue(qaContract.hasRole(adminRole, admin));

        // Test statistics
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalPenalties, 0);
        assertEq(totalWarnings, 0);
    }

    function test_QA_AccessControl_AdminFunctions() public {
        address newTreasury = makeAddr("newTreasury");
        address newVault = makeAddr("newVault");
        address unauthorized = makeAddr("unauthorized");

        // Get current treasury for restore
        address currentTreasury = qaContract.treasury();
        address currentVault = qaContract.vaultContract();

        // Test successful admin operations
        vm.startPrank(admin);
        qaContract.updateTreasury(newTreasury);
        assertEq(qaContract.treasury(), newTreasury);

        qaContract.updateVaultContract(newVault);
        assertEq(qaContract.vaultContract(), newVault);
        vm.stopPrank();

        // Test unauthorized access - this should cover the revert path in onlyAdmin
        vm.prank(unauthorized);
        vm.expectRevert();
        qaContract.updateTreasury(currentTreasury);

        vm.prank(unauthorized);
        vm.expectRevert();
        qaContract.updateVaultContract(currentVault);

        // Test with user1 (should also fail)
        vm.prank(user1);
        vm.expectRevert();
        qaContract.updateTreasury(currentTreasury);
    }

    function test_QA_AccessControl_QAManagerRole() public view {
        // Test that qaManager has the QA_MANAGER_ROLE
        assertTrue(qaContract.hasRole(Constants.QA_MANAGER_ROLE, qaManager));

        // Test that other addresses don't have the role
        assertFalse(qaContract.hasRole(Constants.QA_MANAGER_ROLE, user1));
        assertFalse(qaContract.hasRole(Constants.QA_MANAGER_ROLE, admin));
        assertFalse(qaContract.hasRole(Constants.QA_MANAGER_ROLE, treasury));
    }

    // =============================================================
    // COMPREHENSIVE ACCESS CONTROL TESTS
    // =============================================================

    function test_QA_AccessControl_ProcessQualityAssessment_UnauthorizedCaller() public {
        // Create user stake for the test
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        bytes32 testDecisionId = keccak256("unauthorized_test");
        uint256 penaltyAmount = 1000 * 1e18;

        // Generate valid signature (this would normally be from an authorized signer)
        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, testDecisionId, REASON);

        // Test unauthorized users cannot call processQualityAssessment
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = user1;
        unauthorizedUsers[1] = user2;
        unauthorizedUsers[2] = admin; // Even admin can't call this
        unauthorizedUsers[3] = treasury;

        for (uint256 i = 0; i < unauthorizedUsers.length; i++) {
            vm.prank(unauthorizedUsers[i]);
            vm.expectRevert();
            qaContract.processQualityAssessment(
                user1,
                ISapienQA.QAActionType.MINOR_PENALTY,
                penaltyAmount,
                testDecisionId,
                REASON,
                _getExpiration(),
                signature
            );
        }

        // Verify that the decision was not processed
        assertFalse(qaContract.isDecisionProcessed(testDecisionId));
    }

    function test_QA_AccessControl_ProcessQualityAssessment_ValidQAManager() public {
        // Create user stake for the test
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        bytes32 testDecisionId = keccak256("valid_qa_manager_test");
        uint256 penaltyAmount = 1000 * 1e18;

        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, testDecisionId, REASON);

        // Test that valid QA manager can call the function
        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            testDecisionId,
            REASON,
            _getExpiration(),
            signature
        );

        // Verify the decision was processed
        assertTrue(qaContract.isDecisionProcessed(testDecisionId));
    }

    function test_QA_AccessControl_AdminFunctions_ZeroAddressValidation() public {
        // Test that admin functions reject zero addresses
        vm.startPrank(admin);

        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        qaContract.updateTreasury(address(0));

        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        qaContract.updateVaultContract(address(0));

        vm.stopPrank();
    }

    function test_QA_AccessControl_RoleManagement() public {
        address newQAManager = makeAddr("newQAManager");
        address newAdmin = makeAddr("newAdmin");

        // Test admin can grant and revoke QA_MANAGER_ROLE
        vm.startPrank(admin);

        // Grant QA manager role to new address
        qaContract.grantRole(Constants.QA_MANAGER_ROLE, newQAManager);
        assertTrue(qaContract.hasRole(Constants.QA_MANAGER_ROLE, newQAManager));

        // Revoke QA manager role from original qaManager
        qaContract.revokeRole(Constants.QA_MANAGER_ROLE, qaManager);
        assertFalse(qaContract.hasRole(Constants.QA_MANAGER_ROLE, qaManager));

        // Grant admin role to new address
        qaContract.grantRole(qaContract.DEFAULT_ADMIN_ROLE(), newAdmin);
        assertTrue(qaContract.hasRole(qaContract.DEFAULT_ADMIN_ROLE(), newAdmin));

        vm.stopPrank();

        // Test that non-admin cannot manage roles
        vm.prank(user1);
        vm.expectRevert();
        qaContract.grantRole(Constants.QA_MANAGER_ROLE, user1);

        vm.prank(user1);
        vm.expectRevert();
        qaContract.revokeRole(Constants.QA_MANAGER_ROLE, newQAManager);
    }

    function test_QA_AccessControl_SignatureValidation_UnauthorizedSigner() public {
        // Create user stake
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        bytes32 testDecisionId = keccak256("unauthorized_signer_test");
        uint256 penaltyAmount = 1000 * 1e18;

        // Generate signature from unauthorized private key
        uint256 unauthorizedPrivateKey = 0x999; // Different from QA_MANAGER_PRIVATE_KEY

        bytes memory unauthorizedSignature = _generateSignatureWithKey(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, testDecisionId, REASON, unauthorizedPrivateKey
        );

        // Test that QA manager calling with unauthorized signature fails
        vm.prank(qaManager);
        vm.expectRevert(); // Should revert with UnauthorizedSigner
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            testDecisionId,
            REASON,
            _getExpiration(),
            unauthorizedSignature
        );
    }

    function test_QA_AccessControl_SignatureValidation_InvalidSignatureLength() public {
        // Create user stake
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        bytes32 testDecisionId = keccak256("invalid_sig_length_test");
        uint256 penaltyAmount = 1000 * 1e18;

        // Create signature with invalid length (64 bytes instead of 65)
        bytes memory invalidSignature = new bytes(64);

        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.InvalidSignatureLength.selector);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            testDecisionId,
            REASON,
            _getExpiration(),
            invalidSignature
        );
    }

    function test_QA_AccessControl_MultipleQAManagers() public {
        address qaManager2 = makeAddr("qaManager2");
        uint256 qaManager2PrivateKey = 0x456;
        qaManager2 = vm.addr(qaManager2PrivateKey);

        // Admin grants QA manager role to second manager
        vm.prank(admin);
        qaContract.grantRole(Constants.QA_MANAGER_ROLE, qaManager2);

        // Grant QA_SIGNER_ROLE to qaManager2 so they can sign decisions
        vm.prank(admin);
        qaContract.grantRole(Constants.QA_SIGNER_ROLE, qaManager2);

        // Create user stake
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        // Test that both QA managers can process assessments
        bytes32 decision1 = keccak256("qa_manager_1_decision");
        bytes32 decision2 = keccak256("qa_manager_2_decision");

        // First QA manager processes assessment
        bytes memory signature1 =
            _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, decision1, "First manager warning");

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, decision1, "First manager warning", _getExpiration(), signature1
        );

        // Second QA manager processes assessment
        bytes memory signature2 = _generateSignatureWithKey(
            user1, ISapienQA.QAActionType.WARNING, 0, decision2, "Second manager warning", qaManager2PrivateKey
        );

        vm.prank(qaManager2);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, decision2, "Second manager warning", _getExpiration(), signature2
        );

        // Verify both decisions were processed
        assertTrue(qaContract.isDecisionProcessed(decision1));
        assertTrue(qaContract.isDecisionProcessed(decision2));

        // Verify statistics show 2 warnings
        (, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalWarnings, 2);
    }

    function test_QA_AccessControl_AdminTransferAndRoleRevocation() public {
        address newAdmin = makeAddr("newAdmin");

        // Verify original admin has the role
        assertTrue(qaContract.hasRole(qaContract.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(qaContract.hasRole(qaContract.DEFAULT_ADMIN_ROLE(), newAdmin));

        // Test admin can grant admin role (similar to how role management test works)
        vm.startPrank(admin);

        // Grant admin role to new address
        qaContract.grantRole(qaContract.DEFAULT_ADMIN_ROLE(), newAdmin);
        assertTrue(qaContract.hasRole(qaContract.DEFAULT_ADMIN_ROLE(), newAdmin));

        vm.stopPrank();

        // Both admins should be able to perform admin functions
        address testTreasury1 = makeAddr("testTreasury1");
        address testTreasury2 = makeAddr("testTreasury2");

        // Original admin updates treasury
        vm.prank(admin);
        qaContract.updateTreasury(testTreasury1);
        assertEq(qaContract.treasury(), testTreasury1);

        // New admin can also update treasury
        vm.prank(newAdmin);
        qaContract.updateTreasury(testTreasury2);
        assertEq(qaContract.treasury(), testTreasury2);

        // Test non-admin cannot perform admin functions
        vm.prank(user1);
        vm.expectRevert();
        qaContract.updateTreasury(testTreasury1);
    }

    function test_QA_AccessControl_ViewFunctionsPublicAccess() public {
        // Test that view functions are accessible by any address
        address[] memory callers = new address[](5);
        callers[0] = user1;
        callers[1] = user2;
        callers[2] = admin;
        callers[3] = treasury;
        callers[4] = qaManager;

        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);

            // These should not revert for any caller
            qaContract.getUserQAHistory(user1);
            qaContract.getUserQARecordCount(user1);
            qaContract.isDecisionProcessed(DECISION_ID);
            qaContract.getQAStatistics();
            qaContract.treasury();
            qaContract.vaultContract();
            qaContract.hasRole(Constants.QA_MANAGER_ROLE, qaManager);
        }
    }

    // =============================================================
    // HELPER FUNCTIONS FOR ACCESS CONTROL TESTS
    // =============================================================

    function _generateSignatureWithKey(
        address userAddress,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string memory reason,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        return _generateSignatureWithKeyAndExpiration(
            userAddress, actionType, penaltyAmount, decisionId, reason, expiration, privateKey
        );
    }

    function _generateSignatureWithKeyAndExpiration(
        address userAddress,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string memory reason,
        uint256 expiration,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        // Use the QA contract's createQADecisionHash function
        bytes32 structHash = qaContract.createQADecisionHash(
            decisionId, userAddress, uint8(actionType), penaltyAmount, reason, expiration
        );

        bytes32 domainSeparator = qaContract.getDomainSeparator();

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    // =============================================================
    // END OF ACCESS CONTROL TESTS
    // =============================================================

    function test_QA_VaultIntegration() public {
        // Create user stake
        vm.startPrank(user1);
        token.approve(address(vault), 5000 * 1e18);
        vault.stake(5000 * 1e18, Constants.LOCKUP_90_DAYS);
        vm.stopPrank();

        uint256 penaltyAmount = 1000 * 1e18;
        uint256 initialBalance = vault.getTotalStaked(user1);
        uint256 initialTreasuryBalance = token.balanceOf(treasury);

        // QA contract should be able to process penalty
        vm.prank(address(qaContract));
        uint256 actualPenalty = vault.processQAPenalty(user1, penaltyAmount);

        // Verify actual penalty matches requested (sufficient stake available)
        assertEq(actualPenalty, penaltyAmount);

        // Verify stake was reduced
        assertEq(vault.getTotalStaked(user1), initialBalance - penaltyAmount);

        // Verify treasury received tokens (penalties now go to treasury for security)
        assertEq(token.balanceOf(treasury), initialTreasuryBalance + penaltyAmount);
    }

    function test_QA_ConstructorValidation() public {
        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        new SapienQA(address(0), address(vault), qaManager, admin);

        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        new SapienQA(treasury, address(0), qaManager, admin);

        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        new SapienQA(treasury, address(vault), address(0), address(0));
    }

    function test_QA_ProcessQualityAssessmentWarning() public {
        // Create stake for user1
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        // Generate valid signature for warning
        bytes memory signature = _generateSignature(
            user1,
            ISapienQA.QAActionType.WARNING,
            0, // No penalty for warning
            DECISION_ID,
            REASON
        );

        // Process warning
        vm.expectEmit(true, true, true, true);
        emit QualityAssessmentProcessed(user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, qaManager);

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), signature
        );

        // Verify decision is recorded
        assertTrue(qaContract.isDecisionProcessed(DECISION_ID));

        // Verify QA history
        ISapienQA.QARecord[] memory history = qaContract.getUserQAHistory(user1);
        assertEq(history.length, 1);
        assertEq(uint8(history[0].actionType), uint8(ISapienQA.QAActionType.WARNING));
        assertEq(history[0].penaltyAmount, 0);
        assertEq(history[0].decisionId, DECISION_ID);
        assertEq(history[0].reason, REASON);

        // Verify statistics
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalPenalties, 0);
        assertEq(totalWarnings, 1);
    }

    function test_QA_ProcessQualityAssessmentMinorPenalty() public {
        // Create stake for user1
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        uint256 initialUserBalance = vault.getTotalStaked(user1);
        uint256 initialTreasuryBalance = token.balanceOf(treasury);

        // Generate valid signature for minor penalty
        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, PENALTY_AMOUNT, DECISION_ID, REASON);

        // Process penalty
        vm.expectEmit(true, true, true, true);
        emit QualityAssessmentProcessed(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, PENALTY_AMOUNT, DECISION_ID, REASON, qaManager
        );

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            PENALTY_AMOUNT,
            DECISION_ID,
            REASON,
            _getExpiration(),
            signature
        );

        // Verify stake was reduced
        assertEq(vault.getTotalStaked(user1), initialUserBalance - PENALTY_AMOUNT);

        // Verify treasury received penalty (penalties now go to treasury for security)
        assertEq(token.balanceOf(treasury), initialTreasuryBalance + PENALTY_AMOUNT);

        // Verify statistics
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalPenalties, PENALTY_AMOUNT);
        assertEq(totalWarnings, 0);
    }

    function test_QA_ProcessQualityAssessmentInvalidSignature() public {
        bytes memory invalidSignature = new bytes(65);

        vm.prank(qaManager);
        vm.expectRevert(); // ECDSA will revert on invalid signature
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), invalidSignature
        );
    }

    function test_QA_ProcessQualityAssessmentValidationErrors() public {
        bytes memory signature = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON);

        // Test zero address
        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.ZeroAddress.selector);
        qaContract.processQualityAssessment(
            address(0), ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), signature
        );

        // Test invalid decision ID
        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.InvalidDecisionId.selector);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, bytes32(0), REASON, _getExpiration(), signature
        );

        // Test empty reason
        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.EmptyReason.selector);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, "", _getExpiration(), signature
        );

        // Test penalty for warning
        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.InvalidPenaltyForWarning.selector);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 100, DECISION_ID, REASON, _getExpiration(), signature
        );

        // Test no penalty for penalty action
        bytes memory penaltySignature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, 0, DECISION_ID, REASON);

        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.PenaltyAmountRequired.selector);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, 0, DECISION_ID, REASON, _getExpiration(), penaltySignature
        );
    }

    function test_QA_ReplayAttackPrevention() public {
        bytes memory signature = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON);

        // First call should succeed
        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), signature
        );

        // Second call with same decision ID should fail
        vm.prank(qaManager);
        vm.expectRevert(ISapienQA.DecisionAlreadyProcessed.selector);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), signature
        );
    }

    function test_QA_SignatureExpiration() public {
        // Create user stake for the test
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        bytes32 testDecisionId = keccak256("expiration_test");
        uint256 penaltyAmount = 1000 * 1e18;

        // Fast forward time to ensure we have a meaningful timestamp
        vm.warp(100000); // Set timestamp to 100000 seconds

        // Generate signature with past expiration
        uint256 pastExpiration = 50000; // Well in the past (less than current timestamp)
        bytes memory expiredSignature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, testDecisionId, REASON, pastExpiration
        );

        // Test that expired signature fails
        vm.prank(qaManager);
        vm.expectRevert(abi.encodeWithSelector(ISapienQA.ExpiredSignature.selector, pastExpiration));
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            testDecisionId,
            REASON,
            pastExpiration,
            expiredSignature
        );

        // Verify decision was not processed
        assertFalse(qaContract.isDecisionProcessed(testDecisionId));

        // Test that valid signature works - use different decision ID
        bytes32 testDecisionId2 = keccak256("expiration_test_2");
        uint256 futureExpiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        bytes memory validSignature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, testDecisionId2, REASON, futureExpiration
        );

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            testDecisionId2,
            REASON,
            futureExpiration,
            validSignature
        );

        // Verify decision was processed
        assertTrue(qaContract.isDecisionProcessed(testDecisionId2));
    }

    function test_QA_PenaltyProcessingFailure() public {
        // Create user with limited stake but request penalty more than available
        _createUserStake(user1, 1000 * 1e18, Constants.LOCKUP_90_DAYS);

        uint256 requestedPenalty = 2000 * 1e18; // More than available stake
        uint256 availableStake = 1000 * 1e18; // User's actual stake

        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, requestedPenalty, DECISION_ID, REASON);

        // Should apply partial penalty and emit QAPenaltyPartial event
        vm.expectEmit(true, true, true, true);
        emit QAPenaltyPartial(user1, requestedPenalty, availableStake, "Insufficient stake for full penalty");

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            requestedPenalty,
            DECISION_ID,
            REASON,
            _getExpiration(),
            signature
        );

        // Decision should be processed
        assertTrue(qaContract.isDecisionProcessed(DECISION_ID));

        // Penalty amount in record should be the available stake (partial penalty)
        ISapienQA.QARecord[] memory history = qaContract.getUserQAHistory(user1);
        assertEq(history[0].penaltyAmount, availableStake);

        // User's stake should be completely drained
        assertEq(vault.getTotalStaked(user1), 0);

        // Verify statistics updated with actual penalty applied
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalPenalties, availableStake);
        assertEq(totalWarnings, 0);
    }

    function test_QA_PenaltyProcessingNoStake() public {
        // Try to penalize user with no stake at all
        bytes32 noStakeDecisionId = keccak256("no_stake_decision");

        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, 1000 * 1e18, noStakeDecisionId, REASON);

        // Should emit QAPenaltyFailed since no stake available
        vm.expectEmit(true, true, true, true);
        emit QAPenaltyFailed(user1, 1000 * 1e18, "Unknown error processing penalty");

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            1000 * 1e18,
            noStakeDecisionId,
            REASON,
            _getExpiration(),
            signature
        );

        // Decision should still be processed but with 0 penalty
        assertTrue(qaContract.isDecisionProcessed(noStakeDecisionId));

        // Penalty amount in record should be 0
        ISapienQA.QARecord[] memory history = qaContract.getUserQAHistory(user1);
        assertEq(history[0].penaltyAmount, 0);
    }

    function test_QA_GetUserQARecordCount() public {
        // Initially should be 0
        assertEq(qaContract.getUserQARecordCount(user1), 0);

        // Create stake for user1
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        // Add a warning
        bytes memory signature = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON);

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, DECISION_ID, REASON, _getExpiration(), signature
        );

        // Should now be 1
        assertEq(qaContract.getUserQARecordCount(user1), 1);

        // Add another warning with different decision ID
        bytes32 decisionId2 = keccak256("decision_002");
        signature = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, decisionId2, REASON);

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, decisionId2, REASON, _getExpiration(), signature
        );

        // Should now be 2
        assertEq(qaContract.getUserQARecordCount(user1), 2);

        // Verify other user still has 0 records
        assertEq(qaContract.getUserQARecordCount(user2), 0);
    }

    function test_QA_ProcessQualityAssessmentPenalty() public {
        // Create stake for user1
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        uint256 initialUserBalance = vault.getTotalStaked(user1);
        uint256 initialTreasuryBalance = token.balanceOf(treasury);

        // Generate valid signature for penalty
        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, PENALTY_AMOUNT, DECISION_ID, REASON);

        // Process penalty
        vm.expectEmit(true, true, true, true);
        emit QualityAssessmentProcessed(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, PENALTY_AMOUNT, DECISION_ID, REASON, qaManager
        );

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            PENALTY_AMOUNT,
            DECISION_ID,
            REASON,
            _getExpiration(),
            signature
        );

        // Verify stake was reduced
        assertEq(vault.getTotalStaked(user1), initialUserBalance - PENALTY_AMOUNT);

        // Verify treasury received penalty
        assertEq(token.balanceOf(treasury), initialTreasuryBalance + PENALTY_AMOUNT);

        // Verify statistics
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalPenalties, PENALTY_AMOUNT);
        assertEq(totalWarnings, 0);
    }

    function test_QA_PenaltyProcessingVaultPausedError() public {
        // Create user with stake
        _createUserStake(user1, 5000 * 1e18, Constants.LOCKUP_90_DAYS);

        // Pause the vault to force a specific error when processing penalty
        vm.prank(makeAddr("pauseManager"));
        vault.pause();

        bytes32 pausedDecisionId = keccak256("paused_vault_decision");
        uint256 requestedPenalty = 1000 * 1e18;

        bytes memory signature =
            _generateSignature(user1, ISapienQA.QAActionType.MINOR_PENALTY, requestedPenalty, pausedDecisionId, REASON);

        // The vault paused error will be caught by the generic catch block, not Error() block
        // So we expect "Unknown error processing penalty"
        vm.expectEmit(true, true, true, true);
        emit QAPenaltyFailed(user1, requestedPenalty, "Unknown error processing penalty");

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            requestedPenalty,
            pausedDecisionId,
            REASON,
            _getExpiration(),
            signature
        );

        // Decision should still be processed but with 0 penalty
        assertTrue(qaContract.isDecisionProcessed(pausedDecisionId));

        // Penalty amount in record should be 0 since vault call failed
        ISapienQA.QARecord[] memory history = qaContract.getUserQAHistory(user1);
        // Find the record with our decision ID
        bool found = false;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].decisionId == pausedDecisionId) {
                assertEq(history[i].penaltyAmount, 0);
                found = true;
                break;
            }
        }
        assertTrue(found, "Should have found the paused decision record");

        // Unpause vault for cleanup
        vm.prank(makeAddr("pauseManager"));
        vault.unpause();
    }

    function test_QA_PenaltyProcessingStringError() public {
        // Since the Error(string memory) catch block is hard to trigger with the current vault,
        // let's create a scenario that would trigger it by deploying a mock vault
        // For this test, we'll modify the vaultContract address temporarily

        // Deploy a mock vault that always reverts with a string error
        MockVaultWithStringError mockVault = new MockVaultWithStringError();

        // Update QA contract to use mock vault temporarily
        vm.prank(admin);
        qaContract.updateVaultContract(address(mockVault));

        bytes32 stringErrorDecisionId = keccak256("string_error_decision");
        uint256 requestedPenalty = 1000 * 1e18;

        bytes memory signature = _generateSignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, requestedPenalty, stringErrorDecisionId, REASON
        );

        // The mock vault will revert with "Mock vault string error"
        vm.expectEmit(true, true, true, true);
        emit QAPenaltyFailed(user1, requestedPenalty, "Mock vault string error");

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            requestedPenalty,
            stringErrorDecisionId,
            REASON,
            _getExpiration(),
            signature
        );

        // Decision should be processed with 0 penalty
        assertTrue(qaContract.isDecisionProcessed(stringErrorDecisionId));

        // Restore original vault
        vm.prank(admin);
        qaContract.updateVaultContract(address(vault));
    }

    /**
     * @dev Comprehensive end-to-end QA scenario test that validates the complete user journey
     * through the Quality Assurance system. This test demonstrates:
     *
     * WORKFLOW COVERAGE:
     * - User onboarding with token staking
     * - Progressive QA enforcement (warnings → penalties)
     * - State management across multiple QA actions
     * - Complete audit trail maintenance
     *
     * SYSTEM INTEGRATION:
     * - SapienQA ↔ SapienVault integration for penalty enforcement
     * - Token balance management and transfers
     * - EIP-712 signature verification for QA decisions
     * - Event emission for audit logging
     *
     * DATA INTEGRITY:
     * - QA record persistence and retrieval
     * - Statistics tracking (warnings vs penalties)
     * - Replay attack prevention
     * - User isolation (actions on one user don't affect others)
     *
     * REALISTIC SCENARIO:
     * 1. User stakes 10,000 tokens with 90-day lockup
     * 2. User receives first warning (no penalty)
     * 3. User receives second warning (escalation pattern)
     * 4. User receives minor penalty (500 tokens)
     * 5. User receives major penalty (1,000 tokens)
     * 6. System verifies complete state consistency
     *
     * This test serves as both a regression test and integration validation,
     * ensuring all QA system components work together correctly in production scenarios.
     */
    function test_QA_EndToEndScenario() public {
        // =============================================================
        // COMPREHENSIVE END-TO-END QA SCENARIO TEST
        // =============================================================
        // This test simulates a complete user journey through the QA system:
        // 1. User stakes tokens in vault
        // 2. User receives warnings and penalties
        // 3. Verify all state changes throughout process
        // =============================================================

        console.log("=== Starting End-to-End QA Scenario ===");

        // Phase 1: Setup and initial staking
        _setupEndToEndUser();

        // Phase 2: Process warnings
        _processWarnings();

        // Phase 3: Process penalties
        _processPenalties();

        // Phase 4: Verify final state
        _verifyFinalState();

        console.log("=== End-to-End QA Scenario Completed Successfully ===");
    }

    function _setupEndToEndUser() internal {
        console.log("=== Phase 1: User stakes tokens ===");

        uint256 stakeAmount = 10000 * 1e18;

        vm.startPrank(user1);
        token.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount, Constants.LOCKUP_90_DAYS);
        vm.stopPrank();

        // Verify initial state
        assertEq(vault.getTotalStaked(user1), stakeAmount);
        assertEq(qaContract.getUserQARecordCount(user1), 0);

        (uint256 penalties, uint256 warnings) = qaContract.getQAStatistics();
        assertEq(penalties, 0);
        assertEq(warnings, 0);
    }

    function _processWarnings() internal {
        console.log("=== Phase 2: Processing warnings ===");

        // First warning
        bytes32 warningId1 = keccak256("warning_001");
        string memory reason1 = "First violation warning";

        bytes memory sig1 = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, warningId1, reason1);

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, warningId1, reason1, _getExpiration(), sig1
        );

        // Second warning
        bytes32 warningId2 = keccak256("warning_002");
        string memory reason2 = "Second violation warning";

        bytes memory sig2 = _generateSignature(user1, ISapienQA.QAActionType.WARNING, 0, warningId2, reason2);

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1, ISapienQA.QAActionType.WARNING, 0, warningId2, reason2, _getExpiration(), sig2
        );

        // Verify warnings
        assertEq(qaContract.getUserQARecordCount(user1), 2);
        (uint256 penalties, uint256 warnings) = qaContract.getQAStatistics();
        assertEq(warnings, 2);
        assertEq(penalties, 0);
    }

    function _processPenalties() internal {
        console.log("=== Phase 3: Processing penalties ===");

        uint256 initialStake = vault.getTotalStaked(user1);
        uint256 penalty1 = 500 * 1e18;
        uint256 penalty2 = 1000 * 1e18;

        // First penalty
        bytes32 penaltyId1 = keccak256("penalty_001");
        bytes memory sig1 = _generateSignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penalty1, penaltyId1, "Minor penalty applied"
        );

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penalty1,
            penaltyId1,
            "Minor penalty applied",
            _getExpiration(),
            sig1
        );

        // Verify first penalty
        assertEq(vault.getTotalStaked(user1), initialStake - penalty1);

        // Second penalty
        bytes32 penaltyId2 = keccak256("penalty_002");
        bytes memory sig2 = _generateSignature(
            user1, ISapienQA.QAActionType.MAJOR_PENALTY, penalty2, penaltyId2, "Major penalty applied"
        );

        vm.prank(qaManager);
        qaContract.processQualityAssessment(
            user1,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            penalty2,
            penaltyId2,
            "Major penalty applied",
            _getExpiration(),
            sig2
        );

        // Verify second penalty
        assertEq(vault.getTotalStaked(user1), initialStake - penalty1 - penalty2);
        assertEq(qaContract.getUserQARecordCount(user1), 4);
    }

    function _verifyFinalState() internal view {
        console.log("=== Phase 4: Final verification ===");

        // Verify complete QA history
        ISapienQA.QARecord[] memory history = qaContract.getUserQAHistory(user1);
        assertEq(history.length, 4);

        // Verify action types
        assertEq(uint8(history[0].actionType), uint8(ISapienQA.QAActionType.WARNING));
        assertEq(uint8(history[1].actionType), uint8(ISapienQA.QAActionType.WARNING));
        assertEq(uint8(history[2].actionType), uint8(ISapienQA.QAActionType.MINOR_PENALTY));
        assertEq(uint8(history[3].actionType), uint8(ISapienQA.QAActionType.MAJOR_PENALTY));

        // Verify penalty amounts
        assertEq(history[0].penaltyAmount, 0);
        assertEq(history[1].penaltyAmount, 0);
        assertEq(history[2].penaltyAmount, 500 * 1e18);
        assertEq(history[3].penaltyAmount, 1000 * 1e18);

        // Verify final statistics
        (uint256 totalPenalties, uint256 totalWarnings) = qaContract.getQAStatistics();
        assertEq(totalWarnings, 2);
        assertEq(totalPenalties, 1500 * 1e18); // 500 + 1000

        // Verify user2 is unaffected
        assertEq(qaContract.getUserQARecordCount(user2), 0);
        assertEq(vault.getTotalStaked(user2), 0);

        // Verify timestamp ordering
        assertTrue(history[1].timestamp >= history[0].timestamp);
        assertTrue(history[2].timestamp >= history[1].timestamp);
        assertTrue(history[3].timestamp >= history[2].timestamp);
    }

    // =============================================================
    // DIRECT VERIFY SIGNATURE TESTS
    // =============================================================

    function test_QA_VerifySignature_ValidSignature() public view {
        // Test that a valid signature passes verification
        bytes32 decisionId = keccak256("valid_signature_test");
        string memory reason = "Valid signature test";
        uint256 penaltyAmount = 1000 * 1e18;
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;

        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiration
        );

        // This should not revert
        qaContract.verifySignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiration, signature
        );
    }

    function test_QA_VerifySignature_ExpiredSignature() public {
        bytes32 decisionId = keccak256("expired_signature_test");
        string memory reason = "Expired signature test";
        uint256 penaltyAmount = 1000 * 1e18;

        // Create an expired signature (1 second in the past)
        uint256 expiredTime = block.timestamp - 1;
        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiredTime
        );

        // Should revert with ExpiredSignature
        vm.expectRevert(abi.encodeWithSelector(ISapienQA.ExpiredSignature.selector, expiredTime));
        qaContract.verifySignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiredTime, signature
        );
    }

    function test_QA_VerifySignature_InvalidSignatureLength_TooShort() public {
        bytes32 decisionId = keccak256("short_signature_test");
        string memory reason = "Short signature test";
        uint256 penaltyAmount = 1000 * 1e18;
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;

        // Create a signature that's too short (only 32 bytes instead of 65)
        bytes memory shortSignature = new bytes(32);

        vm.expectRevert(ISapienQA.InvalidSignatureLength.selector);
        qaContract.verifySignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiration, shortSignature
        );
    }

    function test_QA_VerifySignature_InvalidSignatureLength_TooLong() public {
        bytes32 decisionId = keccak256("long_signature_test");
        string memory reason = "Long signature test";
        uint256 penaltyAmount = 1000 * 1e18;
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;

        // Create a signature that's too long (100 bytes instead of 65)
        bytes memory longSignature = new bytes(100);

        vm.expectRevert(ISapienQA.InvalidSignatureLength.selector);
        qaContract.verifySignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiration, longSignature
        );
    }

    // Helper function to reduce stack depth
    function _createCorruptedSignature(
        address user,
        ISapienQA.QAActionType actionType,
        uint256 amount,
        bytes32 id,
        string memory text,
        uint256 expiry
    ) internal view returns (bytes memory) {
        // Generate a valid signature first
        bytes memory validSig = _generateSignatureWithExpiration(user, actionType, amount, id, text, expiry);

        // Corrupt the signature by flipping some bits
        bytes memory corruptedSig = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            if (i < validSig.length) {
                corruptedSig[i] = bytes1(uint8(validSig[i]) ^ 0xFF); // Flip all bits
            }
        }

        return corruptedSig;
    }

    function test_QA_VerifySignature_CorruptedSignatureData() public {
        bytes32 decisionId = keccak256("corrupted_signature_test");
        string memory reason = "Corrupted signature test";
        uint256 penaltyAmount = 1000 * 1e18;
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;

        // Get corrupted signature using helper function
        bytes memory corruptedSignature = _createCorruptedSignature(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId, reason, expiration
        );

        // Should revert because the recovered address won't have the QA_SIGNER_ROLE
        vm.expectRevert(); // Will revert with UnauthorizedSigner but the exact address is unpredictable
        qaContract.verifySignature(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            penaltyAmount,
            decisionId,
            reason,
            expiration,
            corruptedSignature
        );
    }

    function test_QA_VerifySignature_WarningActionType() public view {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        bytes32 decisionId = keccak256("warning_action_test");

        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.WARNING, 0, decisionId, "Warning action test", expiration
        );

        qaContract.verifySignature(
            user1, ISapienQA.QAActionType.WARNING, 0, decisionId, "Warning action test", expiration, signature
        );
    }

    function test_QA_VerifySignature_MinorPenaltyActionType() public view {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        bytes32 decisionId = keccak256("minor_penalty_test");

        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MINOR_PENALTY, 500 * 1e18, decisionId, "Minor penalty test", expiration
        );

        qaContract.verifySignature(
            user1,
            ISapienQA.QAActionType.MINOR_PENALTY,
            500 * 1e18,
            decisionId,
            "Minor penalty test",
            expiration,
            signature
        );
    }

    function test_QA_VerifySignature_MajorPenaltyActionType() public view {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        bytes32 decisionId = keccak256("major_penalty_test");

        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.MAJOR_PENALTY, 1000 * 1e18, decisionId, "Major penalty test", expiration
        );

        qaContract.verifySignature(
            user1,
            ISapienQA.QAActionType.MAJOR_PENALTY,
            1000 * 1e18,
            decisionId,
            "Major penalty test",
            expiration,
            signature
        );
    }

    function test_QA_VerifySignature_SeverePenaltyActionType() public view {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        bytes32 decisionId = keccak256("severe_penalty_test");

        bytes memory signature = _generateSignatureWithExpiration(
            user1, ISapienQA.QAActionType.SEVERE_PENALTY, 2000 * 1e18, decisionId, "Severe penalty test", expiration
        );

        qaContract.verifySignature(
            user1,
            ISapienQA.QAActionType.SEVERE_PENALTY,
            2000 * 1e18,
            decisionId,
            "Severe penalty test",
            expiration,
            signature
        );
    }

    // Helper functions

    function _createUserStake(address user, uint256 amount, uint256 lockupPeriod) internal {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.stake(amount, lockupPeriod);
        vm.stopPrank();
    }

    function _generateSignature(
        address userAddress,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string memory reason
    ) internal view returns (bytes memory) {
        uint256 expiration = block.timestamp + Constants.QA_SIGNATURE_VALIDITY_PERIOD;
        return _generateSignatureWithExpiration(userAddress, actionType, penaltyAmount, decisionId, reason, expiration);
    }

    function _generateSignatureWithExpiration(
        address userAddress,
        ISapienQA.QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string memory reason,
        uint256 expiration
    ) internal view returns (bytes memory) {
        // Create the hash and sign it inline to avoid stack depth issues
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                qaContract.getDomainSeparator(),
                qaContract.createQADecisionHash(
                    decisionId, userAddress, uint8(actionType), penaltyAmount, reason, expiration
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(QA_MANAGER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
}

// Mock contract for testing string error scenarios
contract MockVaultWithStringError {
    function processQAPenalty(address, /*userAddress*/ uint256 /*penaltyAmount*/ ) external pure returns (uint256) {
        revert("Mock vault string error");
    }
}
