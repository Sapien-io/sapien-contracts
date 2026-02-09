// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title FeeOnTransferTokenTest
 * @notice Test demonstrating Issue #11: Fee-on-Transfer Token Compatibility
 *
 * VULNERABILITY DESCRIPTION:
 * The protocol uses safeTransferFrom for reward tokens but doesn't account for
 * fee-on-transfer tokens. If a project uses a fee-on-transfer token:
 * - Originator sends 100 tokens
 * - Protocol receives 98 tokens (2% fee)
 * - project.state.totalRewardsAvailable records 100
 * - Actual tokens available: 98
 * - Result: Last contributors can't claim rewards
 *
 * ATTACK VECTOR: Exotic Token Behavior
 *
 * LOCATION: SapienCore.sol lines 315-340 (_fundProject)
 *
 * SEVERITY: Low (requires originator to use exotic token)
 */

/**
 * @notice Mock fee-on-transfer token for testing
 */
contract FeeOnTransferToken is ERC20 {
    uint256 public feePercent; // Fee in basis points (100 = 1%)

    constructor(uint256 _feePercent) ERC20("FeeToken", "FEE") {
        feePercent = _feePercent;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 netAmount = amount - fee;

        // Burn the fee (or send to fee collector in real implementation)
        if (fee > 0) {
            _burn(msg.sender, fee);
        }

        return super.transfer(to, netAmount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 netAmount = amount - fee;

        // Burn the fee
        if (fee > 0) {
            _burn(from, fee);
        }

        // Update allowance manually to avoid issues
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            _approve(from, msg.sender, currentAllowance - amount);
        }

        _transfer(from, to, netAmount);
        return true;
    }
}

contract FeeOnTransferTokenTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("fee-token-test");
    FeeOnTransferToken public feeToken;

    function setUp() public override {
        super.setUp();

        // Create fee-on-transfer token (2% fee)
        feeToken = new FeeOnTransferToken(200); // 2% fee
        feeToken.mint(originator, 10000 ether);

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);
    }

    /**
     * @notice Test: Fee-on-transfer causes reward shortfall
     * @dev Protocol records full amount but receives less
     */
    function test_FeeOnTransferRewardShortfall() public {
        uint256 fundAmount = 100 ether;
        uint256 feePercent = feeToken.feePercent();
        uint256 expectedFee = (fundAmount * feePercent) / 10000;
        uint256 expectedReceived = fundAmount - expectedFee;

        console.log("=== Fee-on-Transfer Token Test ===");
        console.log("Funding amount:", fundAmount);
        console.log("Fee percent:", feePercent, "basis points");
        console.log("Expected fee:", expectedFee);
        console.log("Expected received:", expectedReceived);

        // Create project with fee token
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(feeToken), "fee-token-test", 0, 0, 2, 1000, "");
        feeToken.approve(address(core), fundAmount);

        uint256 originatorBalanceBefore = feeToken.balanceOf(originator);
        uint256 rewardsBalanceBefore = feeToken.balanceOf(address(rewards));

        core.fundProject(PROJECT_ID, fundAmount, 10);
        vm.stopPrank();

        uint256 originatorBalanceAfter = feeToken.balanceOf(originator);
        uint256 rewardsBalanceAfter = feeToken.balanceOf(address(rewards));

        console.log("\n=== Actual Token Movements ===");
        console.log("Originator sent:", originatorBalanceBefore - originatorBalanceAfter);
        console.log("Rewards received:", rewardsBalanceAfter - rewardsBalanceBefore);

        // Check recorded vs actual
        uint256 recordedRewards = core.getProject(PROJECT_ID).state.totalRewardsAvailable;
        uint256 actualTokens = rewardsBalanceAfter - rewardsBalanceBefore;

        console.log("\n=== Discrepancy ===");
        console.log("Recorded totalRewardsAvailable:", recordedRewards);
        console.log("Actual tokens in rewards contract:", actualTokens);

        if (recordedRewards > actualTokens) {
            console.log("VULNERABILITY CONFIRMED!");
            console.log("Shortfall:", recordedRewards - actualTokens);
            console.log("Last contributors will not be able to claim rewards!");
        }
    }

    /**
     * @notice Test: Fix verification - Fee-on-transfer tokens now properly accounted for
     * @dev Issue #11 fix: Balance check after transfer adjusts recorded amount
     */
    function test_E2E_FeeOnTransferFixVerification() public {
        uint256 fundAmount = 100 ether;
        uint256 slots = 5;

        // Create and fund project with fee token
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(feeToken), "fee-token-test", 0, 0, 2, 1000, "");
        feeToken.approve(address(core), fundAmount);
        core.fundProject(PROJECT_ID, fundAmount, slots);
        vm.stopPrank();

        console.log("=== Fix Verification: Fee-on-Transfer Token Handling ===");
        console.log("Funded amount:", fundAmount);
        console.log("Fee percent:", feeToken.feePercent(), "basis points");

        // Check recorded vs actual
        uint256 recordedRewards = core.getProject(PROJECT_ID).state.totalRewardsAvailable;
        uint256 actualTokens = feeToken.balanceOf(address(rewards));

        console.log("Recorded totalRewardsAvailable:", recordedRewards);
        console.log("Actual tokens in rewards contract:", actualTokens);

        // With the fix, recorded rewards should match actual tokens received
        // (or be close if there's rounding)
        uint256 difference =
            recordedRewards > actualTokens ? recordedRewards - actualTokens : actualTokens - recordedRewards;

        console.log("Difference:", difference);

        // The fix adjusts totalRewardsAvailable to match actual received
        // Allow small rounding difference (1 wei)
        assertLe(difference, 1, "Recorded rewards should match actual tokens");
        console.log("\nFIX VERIFIED: Recorded rewards match actual tokens received!");
    }

    /**
     * @notice Test: Document recommended mitigation
     */
    function test_DocumentMitigation() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("1. CHECK BALANCE BEFORE/AFTER TRANSFER:");
        console.log("   uint256 balanceBefore = token.balanceOf(address(this));");
        console.log("   token.safeTransferFrom(sender, address(this), amount);");
        console.log("   uint256 balanceAfter = token.balanceOf(address(this));");
        console.log("   uint256 actualReceived = balanceAfter - balanceBefore;");
        console.log("   // Use actualReceived instead of amount");
        console.log("");
        console.log("2. DOCUMENT UNSUPPORTED TOKEN TYPES:");
        console.log("   // In NatSpec or README:");
        console.log("   // WARNING: Fee-on-transfer tokens are not supported");
        console.log("   // Using such tokens may result in reward shortfalls");
        console.log("");
        console.log("3. TOKEN WHITELIST:");
        console.log("   mapping(address => bool) public supportedTokens;");
        console.log("   if (!supportedTokens[rewardToken]) revert UnsupportedToken();");
        console.log("");
        console.log("4. REQUIRE MINIMUM BALANCE AFTER TRANSFER:");
        console.log("   require(token.balanceOf(address(rewards)) >= minRequired);");
    }

    function _validateContribution(bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt1 = keccak256(abi.encodePacked("salt1", contribIndex));
        bytes32 salt2 = keccak256(abi.encodePacked("salt2", contribIndex));
        bytes32 salt3 = keccak256(abi.encodePacked("salt3", contribIndex));
        uint256 stake = 100 ether;

        vm.startPrank(validator1);
        uint256 v1Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt1)));
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt2)));
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt3)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contribIndex, score, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contribIndex, score, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, contribIndex, score, salt3);
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
