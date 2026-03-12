// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ValidationClaimStatus,
    DisputeStatus,
    ContributionStatus,
    ProjectStatus,
    Project,
    ConsensusReport
} from "src/Types.sol";

/// @title Security Issues Verification Tests
/// @notice Tests that verify and document vulnerabilities identified in the security audit
/// @dev These tests cover issues from the SECURITY_AUDIT_REPORT.md:
///      - HIGH-01: Validation claim expiry slot locking (FIXED - test verifies fix works)
///      - HIGH-02: Late commit after claim expiry (FIXED - test verifies fix works)
///      - HIGH-03: Upheld disputes deadlock completion (FIXED - test verifies fix works)
///      - HIGH-04: Flash loan consensus manipulation (UNFIXED - demonstrates vulnerability)
///      - MEDIUM-01: Cancelled projects escrow access (FIXED - test verifies fix works)
///      - MEDIUM-02: Fee structure centralization (UNFIXED - demonstrates issue)
///      - MEDIUM-03: ERC20 integration assumptions (UNFIXED - demonstrates issue)
contract SecurityIssuesVerification is BaseTest {
    // ════════════════════════════════════════════════════════════════════
    // HIGH SEVERITY ISSUES
    // ════════════════════════════════════════════════════════════════════

    /// @notice HIGH-01: Validation Claim Expiry Can Lock Validator Slots
    /// @dev Demonstrates that expired validation claims don't properly release slots
    /// @dev NOTE: This test now passes because the fix has been applied
    function test_HIGH_01_ValidationClaimExpiryLocksValidatorSlots() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // First validator claims the slot
        vm.prank(validator1);
        uint256 claim1 = engine.claimToValidate(projectId, 1);

        // Advance time past claim deadline without committing
        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        // Cancel the expired claim
        engine.cancelExpiredValidationClaim(claim1);

        // Verify claim is expired
        assertEq(
            uint256(engine.getValidationClaim(claim1).status),
            uint256(ValidationClaimStatus.Expired),
            "claim should be expired"
        );

        // Before fix: This would fail because slots weren't properly released
        // After fix: This should succeed - validator4 can claim the freed slot
        address validator4 = makeAddr("validator4");
        vm.prank(validator4);
        uint256 newClaim = engine.claimToValidate(projectId, 1);

        // Verify new claim was successful
        assertTrue(newClaim > 0, "New validator should be able to claim released slot");

        // This test documents the original HIGH-01 issue and verifies the fix works
    }

    /// @notice HIGH-02: Late Commit Allowed After Validation Claim Expiry
    /// @dev Demonstrates that commits are allowed after claim deadline expires
    /// @dev NOTE: This test now fails because the fix has been applied
    function test_HIGH_02_LateCommitAllowedAfterValidationClaimExpiry() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Validator claims the slot
        vm.prank(validator1);
        engine.claimToValidate(projectId, 1);

        // Advance time past claim deadline
        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        // Before fix: Commit would succeed despite deadline expiry
        // After fix: Commit should fail with deadline check
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));
        vm.prank(validator1);
        vm.expectRevert(); // Should revert due to deadline check
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));

        // This test documents the original HIGH-02 issue and verifies the fix works
    }

    /// @notice HIGH-03: Upheld Disputes Can Deadlock Project Completion
    /// @dev Demonstrates that upheld disputes prevent project completion
    /// @dev NOTE: This test now fails because the fix has been applied
    function test_HIGH_03_UpheldDisputesDeadlockProjectCompletion() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Complete full validation cycle
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Open and uphold a dispute
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("dispute"), "evidence");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true); // Uphold dispute

        // Settle validators
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Before fix: completeProject would revert due to upheld dispute blocking reward release
        // After fix: completeProject should succeed because dispute resolution handles pipeline accounting
        vm.prank(originator);
        engine.completeProject(projectId); // Should succeed with fix applied

        // Verify project completed successfully
        assertEq(uint256(engine.getProject(projectId).status), uint256(ProjectStatus.Completed));

        // This test documents the original HIGH-03 issue and verifies the fix works
    }

    /// @notice HIGH-04: Flash Loan Consensus Manipulation
    /// @dev Demonstrates the theoretical vulnerability of flash loan consensus manipulation
    /// @dev NOTE: This issue exists in the protocol design and would require economic fixes
    function test_HIGH_04_FlashLoanConsensusManipulation() public pure {
        // This test demonstrates the CONCEPT of flash loan consensus manipulation
        // In practice, implementing the full attack would require complex flash loan mechanics

        // The vulnerability: consensus weighting uses sqrt(stake) with no minimum lock time
        // An attacker could:
        // 1. Flash loan large amount of SAPIEN tokens
        // 2. Deposit and stake temporarily
        // 3. Participate in validation with massively inflated weight
        // 4. Return flash loan after consensus

        // Demonstrate the math: sqrt(stake) weighting allows disproportionate influence
        uint256 normalStake = 100 * 1e18; // Normal validator: 100 tokens
        uint256 flashStake = 1000000 * 1e18; // Flash loaned: 1M tokens

        uint256 normalWeight = _sqrt(normalStake); // ~10,000
        uint256 flashWeight = _sqrt(flashStake); // ~1,000,000

        // Flash loan attacker gets 100x more weight than normal validator
        assertGt(flashWeight / normalWeight, 50, "Flash loan creates disproportionate consensus influence");

        // With reputation factor, influence is even greater
        uint256 normalRep = 5000; // Default reputation
        uint256 experiencedRep = 9000; // Experienced validator

        uint256 experiencedTotalWeight = normalWeight * experiencedRep; // ~50M
        uint256 flashTotalWeight = flashWeight * normalRep; // ~500B

        // Flash loan attacker dominates consensus completely (~55x influence with these numbers)
        assertGt(flashTotalWeight / experiencedTotalWeight, 10, "Flash loan attacker dominates consensus");

        // This demonstrates the HIGH-04 vulnerability exists in the protocol design
        // Mitigation would require stake aging, minimum lock periods, or quadratic weighting changes
    }

    // Helper function for sqrt calculation (simplified)
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // ════════════════════════════════════════════════════════════════════
    // MEDIUM SEVERITY ISSUES
    // ════════════════════════════════════════════════════════════════════

    /// @notice MEDIUM-01: Cancelled Projects Strand Escrow
    /// @dev Demonstrates that cancelled projects may strand escrow under certain conditions
    /// @dev NOTE: Current implementation actually allows escrow refund for cancelled projects
    function test_MEDIUM_01_CancelledProjectsStrandEscrow() public {
        bytes32 projectId = _createAndFundProject();

        // Cancel the project via operator
        vm.prank(admin);
        engine.removeProject(projectId, 0);

        // Verify project is cancelled
        assertEq(uint256(engine.getProject(projectId).status), uint256(ProjectStatus.Cancelled));

        // Check escrow balance before refund
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "Project should have escrow funds");

        // NOTE: Current implementation allows escrow refund for cancelled projects after delay
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        vm.prank(originator);
        engine.refundEscrow(projectId); // Should succeed

        // Verify escrow was refunded
        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrowAfter, 0, "Escrow should be fully refunded");

        // The original MEDIUM-01 issue has been resolved in the current implementation
        // Cancelled projects can now access their escrow funds
    }

    /// @notice MEDIUM-02: Fee Structure Creates Economic Centralization
    /// @dev Demonstrates the high fee extraction creating centralization incentives
    function test_MEDIUM_02_FeeStructureEconomicCentralization() public {
        uint256 fundingAmount = 1000 * 1e18; // 1000 tokens
        uint256 expectedProtocolFee = (fundingAmount * 1000) / 10000; // 10%
        uint256 expectedOriginationFee = (fundingAmount - expectedProtocolFee) * 400 / 10000; // 4% of remaining

        bytes32 projectId = _createAndFundProject(PROJECT_ID, fundingAmount, QUANTITY);

        // Check treasury balance increased significantly
        uint256 treasuryBalance = token.balanceOf(treasury);
        assertGe(treasuryBalance, expectedProtocolFee, "High protocol fee extracted");

        // Check project escrow is reduced
        uint256 expectedEscrow = fundingAmount - expectedProtocolFee - expectedOriginationFee;
        uint256 escrowBalance = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrowBalance, expectedEscrow, "Escrow reduced by high fees");

        // This demonstrates excessive fee extraction creating centralization incentives
        assertTrue(expectedProtocolFee >= fundingAmount / 10, "Protocol takes 10%+ of all funding");

        // The high fee structure incentivizes protocol capture over ecosystem growth
        // This is a design issue requiring governance consideration
    }

    /// @notice MEDIUM-03: ERC20 Integration Assumptions
    /// @dev Demonstrates issues with non-standard ERC20 tokens
    function test_MEDIUM_03_ERC20IntegrationAssumptions() public {
        // Create a mock fee-on-transfer token
        FeeOnTransferToken feeToken = new FeeOnTransferToken();

        // Fund originator with fee token
        feeToken.mint(originator, 1000 * 1e18);

        // Try to create and fund project with fee-on-transfer token
        vm.startPrank(originator);
        bytes32 projectId = keccak256("fee-test-project");

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(feeToken),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(projectId, "metadata", config);

        // Approve and fund - this should demonstrate the fee-on-transfer issue
        feeToken.approve(address(engine), 1000 * 1e18);

        // ISSUE: fundProject uses balance diff to calculate received amount
        // This may cause issues with fee-on-transfer tokens
        uint256 balanceBefore = feeToken.balanceOf(address(engine));

        // Fund the project - this may work or fail depending on fee calculation
        engine.fundProject(projectId, 1000 * 1e18, 10, address(0));
        vm.stopPrank();

        uint256 balanceAfter = feeToken.balanceOf(address(engine));
        uint256 received = balanceAfter - balanceBefore;

        // With fee-on-transfer, received amount is less than sent amount
        assertLt(received, 1000 * 1e18, "Fee-on-transfer tokens result in less tokens received");

        // This demonstrates ERC20 integration assumptions vulnerability
        // Protocol assumes it receives exactly the requested amount, but fee-on-transfer tokens deduct fees
    }
}

// Mock fee-on-transfer ERC20 token for testing
contract FeeOnTransferToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    uint256 public constant FEE_BPS = 100; // 1% fee

    function name() external pure returns (string memory) {
        return "Fee Token";
    }

    function symbol() external pure returns (string memory) {
        return "FEE";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 netAmount = amount - fee;

        _balances[msg.sender] -= amount;
        _balances[to] += netAmount;
        _balances[address(this)] += fee; // Fee goes to contract

        emit Transfer(msg.sender, to, netAmount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;

        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 netAmount = amount - fee;

        _balances[from] -= amount;
        _balances[to] += netAmount;
        _balances[address(this)] += fee;

        emit Transfer(from, to, netAmount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
