// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus, ContributionStatus} from "src/Types.sol";

/// @title FinalizationLibFuzz
/// @notice Fuzz tests attempting to break FinalizationLib with edge cases
contract FinalizationLibFuzz is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public contributor = makeAddr("contributor");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");

    bytes32 public constant PROJECT_ID = keccak256("test-project");
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;

    uint256 public acceptedIndex;

    function setUp() public {
        token = new MockERC20("Test", "TST");

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        SapienCore engineImpl = new SapienCore();
        bytes memory engineInit = abi.encodeCall(SapienCore.initialize, (admin, address(vault), treasury));
        engine = SapienCore(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        engine.registerSkill("DATA_ANNOTATION");
        vm.stopPrank();

        _setupBalances();
        _createProjectAndAcceptContribution();
    }

    function _setupBalances() internal {
        token.mint(originator, 1_000_000e18);
        vm.prank(originator);
        token.approve(address(engine), type(uint256).max);

        address[4] memory users = [contributor, validator1, validator2, validator3];
        for (uint256 i; i < users.length; ++i) {
            token.mint(users[i], STAKE_AMOUNT * 100);
            vm.startPrank(users[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, users[i]);
            vm.stopPrank();
        }
    }

    function _createProjectAndAcceptContribution() internal {
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
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
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.startPrank(originator);
        engine.createProject(PROJECT_ID, "", config);
        engine.fundProject(PROJECT_ID, 100_000e18, 50, address(0));
        vm.stopPrank();

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        acceptedIndex = indices[0];

        _validateAndAccept(acceptedIndex, 8000);
    }

    function _validateAndAccept(uint256 index, uint256 score) internal {
        address[3] memory validators = [validator1, validator2, validator3];
        bytes32[3] memory salts;

        // Commit phase
        for (uint256 i; i < 3; ++i) {
            salts[i] = keccak256(abi.encodePacked("salt", validators[i], index));
            bytes32 commitHash = keccak256(abi.encodePacked(score, salts[i]));

            vm.prank(validators[i]);
            engine.claimToValidate(PROJECT_ID, 1);

            vm.prank(validators[i]);
            engine.lockValidatorCapacity(VALIDATOR_STAKE);

            vm.prank(validators[i]);
            engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
        }

        // Warp past commit deadline to allow reveals (only once)
        vm.warp(block.timestamp + engine.commitDeadline());

        // Reveal phase
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.revealValidation(PROJECT_ID, index, score, salts[i]);
        }

        engine.computeConsensus(PROJECT_ID, index);
    }

    function _fullValidation(address val, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(val);
        engine.claimToValidate(PROJECT_ID, 1);

        vm.prank(val);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.prank(val);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(PROJECT_ID, index, score, salt);
    }

    function testFuzz_settleValidator_afterChallengePeriod() public {
        _warpPastChallengePeriod();

        uint256 pendingBefore = engine.getPendingRewards(validator1, address(token));

        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);

        uint256 pendingAfter = engine.getPendingRewards(validator1, address(token));
        assertGe(pendingAfter, pendingBefore, "Validator should receive reward");
    }

    function testFuzz_settleValidator_revertsBeforeChallengePeriod() public {
        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);
    }

    function testFuzz_settleValidator_revertsDoubleSettle() public {
        _warpPastChallengePeriod();

        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);
    }

    function testFuzz_settleValidator_revertsNoConsensus(uint256 randomIndex) public {
        randomIndex = bound(randomIndex, 100, 1000);

        _warpPastChallengePeriod();

        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 0, 1));
        engine.settleValidator(PROJECT_ID, randomIndex, 0);
    }

    function testFuzz_settleValidator_revertsNotCommitted(address randomValidator) public {
        vm.assume(randomValidator != validator1 && randomValidator != validator2 && randomValidator != validator3);
        vm.assume(randomValidator != address(0));

        _warpPastChallengePeriod();

        vm.prank(randomValidator);
        vm.expectRevert(ISapienCore.NotCommitted.selector);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);
    }

    function testFuzz_forceSettleValidator_afterDelay() public {
        _warpPastChallengePeriod();
        vm.warp(block.timestamp + engine.forceSettleDelay() + 1);

        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        engine.forceSettleValidator(PROJECT_ID, acceptedIndex, 0, validator1);
    }

    function testFuzz_forceSettleValidator_revertsTooEarly() public {
        _warpPastChallengePeriod();

        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        vm.expectRevert(ISapienCore.ForceSettleTooEarly.selector);
        engine.forceSettleValidator(PROJECT_ID, acceptedIndex, 0, validator1);
    }

    function testFuzz_releaseContributorReward_afterChallengePeriod() public {
        _warpPastChallengePeriod();

        uint256 pendingBefore = engine.getPendingRewards(contributor, address(token));

        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        uint256 pendingAfter = engine.getPendingRewards(contributor, address(token));
        assertGt(pendingAfter, pendingBefore, "Contributor should receive reward");
    }

    function testFuzz_releaseContributorReward_revertsBeforeChallengePeriod() public {
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);
    }

    function testFuzz_releaseContributorReward_revertsDoubleRelease() public {
        _warpPastChallengePeriod();

        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.expectRevert(ISapienCore.RewardAlreadyReleased.selector);
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);
    }

    function testFuzz_releaseContributorReward_revertsNotAccepted(uint256 randomIndex) public {
        randomIndex = bound(randomIndex, 100, 1000);

        _warpPastChallengePeriod();

        vm.expectRevert(ISapienCore.ContributionNotAccepted.selector);
        engine.releaseContributorReward(PROJECT_ID, randomIndex);
    }

    function testFuzz_claimReward_validClaim() public {
        _warpPastChallengePeriod();

        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        uint256 pending = engine.getPendingRewards(contributor, address(token));
        uint256 balanceBefore = token.balanceOf(contributor);

        vm.prank(contributor);
        engine.claimReward(address(token));

        uint256 balanceAfter = token.balanceOf(contributor);
        assertEq(balanceAfter - balanceBefore, pending);
    }

    function testFuzz_claimReward_revertsNoPending() public {
        address randomUser = makeAddr("random");

        vm.prank(randomUser);
        vm.expectRevert(ISapienCore.NoRewardToClaim.selector);
        engine.claimReward(address(token));
    }

    function testFuzz_claimReward_revertsBelowMinimum(uint256 minAmount) public {
        minAmount = bound(minAmount, 1e18, 1_000_000e18);

        vm.prank(admin);
        engine.setMinClaimAmount(minAmount);

        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        uint256 pending = engine.getPendingRewards(contributor, address(token));
        if (pending < minAmount) {
            vm.prank(contributor);
            vm.expectRevert(abi.encodeWithSelector(ISapienCore.ClaimAmountTooSmall.selector, pending, minAmount));
            engine.claimReward(address(token));
        }
    }

    function testFuzz_claimReward_respectsCooldown(uint256 cooldownDuration) public {
        cooldownDuration = bound(cooldownDuration, 30 days, 90 days);

        vm.prank(admin);
        engine.setClaimCooldown(cooldownDuration);

        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(contributor);
        engine.claimReward(address(token));

        uint256 claimedAt = block.timestamp;

        bytes32 proj2 = keccak256("cooldown-test-2");
        uint256 contribIdx2 = _createNewProjectWithAcceptedContributionFor(proj2, contributor);

        _warpPastChallengePeriod();
        engine.releaseContributorReward(proj2, contribIdx2);

        vm.prank(contributor);
        vm.expectRevert();
        engine.claimReward(address(token));

        vm.warp(claimedAt + cooldownDuration + 1);

        vm.prank(contributor);
        engine.claimReward(address(token));
    }

    function testFuzz_completeProject_validCompletion() public {
        _warpPastChallengePeriod();

        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(originator);
        engine.completeProject(PROJECT_ID);

        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(uint8(proj.status), uint8(ProjectStatus.Completed));
    }

    function testFuzz_completeProject_revertsNotOriginator(address notOriginator) public {
        vm.assume(notOriginator != originator);

        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(notOriginator);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.completeProject(PROJECT_ID);
    }

    function testFuzz_completeProject_revertsPendingContributions() public {
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(PROJECT_ID);
    }

    function testFuzz_completeProject_revertsActiveReservedClaim() public {
        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(contributor);
        engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(PROJECT_ID);
    }

    function testFuzz_refundEscrow_afterCompletionDelay() public {
        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(originator);
        engine.completeProject(PROJECT_ID);

        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        uint256 escrow = engine.getProjectEscrow(PROJECT_ID, address(token));
        uint256 balanceBefore = token.balanceOf(originator);

        vm.prank(originator);
        engine.refundEscrow(PROJECT_ID);

        uint256 balanceAfter = token.balanceOf(originator);
        assertEq(balanceAfter - balanceBefore, escrow);
    }

    function testFuzz_refundEscrow_revertsBeforeDelay() public {
        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(originator);
        engine.completeProject(PROJECT_ID);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.refundEscrow(PROJECT_ID);
    }

    function testFuzz_refundEscrow_revertsNotCompleted() public {
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectNotCompleted.selector);
        engine.refundEscrow(PROJECT_ID);
    }

    function testFuzz_refundEscrow_revertsNotOriginator(address notOriginator) public {
        vm.assume(notOriginator != originator);

        _warpPastChallengePeriod();
        engine.releaseContributorReward(PROJECT_ID, acceptedIndex);

        vm.prank(originator);
        engine.completeProject(PROJECT_ID);

        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        vm.prank(notOriginator);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.refundEscrow(PROJECT_ID);
    }

    function testFuzz_cancelExpiredCommitment_afterRevealDeadline() public {
        bytes32 newProjectId = keccak256("expired-commit-project");
        uint256 contribIndex = _createNewProjectWithPendingContribution(newProjectId);

        address expiredValidator = makeAddr("expiredValidator");
        _setupUser(expiredValidator);

        vm.prank(expiredValidator);
        engine.claimToValidate(newProjectId, 1);

        vm.prank(expiredValidator);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));
        vm.prank(expiredValidator);
        engine.commitValidation(newProjectId, contribIndex, commitHash, VALIDATOR_STAKE, address(0));

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        engine.cancelExpiredCommitment(newProjectId, contribIndex, expiredValidator);
    }

    function testFuzz_cancelExpiredCommitment_revertsBeforeDeadline() public {
        bytes32 newProjectId = keccak256("not-expired-project");
        uint256 contribIndex = _createNewProjectWithPendingContribution(newProjectId);

        address expiredValidator = makeAddr("notExpiredValidator");
        _setupUser(expiredValidator);

        vm.prank(expiredValidator);
        engine.claimToValidate(newProjectId, 1);

        vm.prank(expiredValidator);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));
        vm.prank(expiredValidator);
        engine.commitValidation(newProjectId, contribIndex, commitHash, VALIDATOR_STAKE, address(0));

        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(newProjectId, contribIndex, expiredValidator);
    }

    function testFuzz_multipleValidatorsSettle_correctRewardDistribution() public {
        _warpPastChallengePeriod();

        uint256 pending1Before = engine.getPendingRewards(validator1, address(token));
        uint256 pending2Before = engine.getPendingRewards(validator2, address(token));
        uint256 pending3Before = engine.getPendingRewards(validator3, address(token));

        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);

        vm.prank(validator2);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);

        vm.prank(validator3);
        engine.settleValidator(PROJECT_ID, acceptedIndex, 0);

        uint256 pending1After = engine.getPendingRewards(validator1, address(token));
        uint256 pending2After = engine.getPendingRewards(validator2, address(token));
        uint256 pending3After = engine.getPendingRewards(validator3, address(token));

        assertGe(pending1After, pending1Before);
        assertGe(pending2After, pending2Before);
        assertGe(pending3After, pending3Before);
    }

    function _warpPastChallengePeriod() internal {
        vm.warp(block.timestamp + engine.challengePeriod() + 1);
    }

    function _setupUser(address user) internal {
        token.mint(user, STAKE_AMOUNT * 100);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 50, user);
        vm.stopPrank();
    }

    function _setupAdditionalRewards(address user) internal {
        bytes32 anotherProjectId = keccak256(abi.encodePacked("additional", block.timestamp));
        uint256 contribIndex = _createNewProjectWithAcceptedContributionFor(anotherProjectId, user);
        _warpPastChallengePeriod();
        engine.releaseContributorReward(anotherProjectId, contribIndex);
    }

    function _createNewProjectWithPendingContribution(bytes32 projectId) internal returns (uint256 contribIndex) {
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
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
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.startPrank(originator);
        engine.createProject(projectId, "", config);
        engine.fundProject(projectId, 100_000e18, 50, address(0));
        vm.stopPrank();

        address newContrib = makeAddr(string(abi.encodePacked("contrib-", projectId)));
        _setupUser(newContrib);

        vm.prank(newContrib);
        (uint256 newClaimId, uint256[] memory newIndices) = engine.claimToContribute(projectId, 1, address(0));
        contribIndex = newIndices[0];

        vm.prank(newContrib);
        engine.contribute(newClaimId, contribIndex, keccak256("submission"), "");
    }

    function _createNewProjectWithAcceptedContributionFor(bytes32 projectId, address contribUser)
        internal
        returns (uint256 contribIndex)
    {
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
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
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.startPrank(originator);
        engine.createProject(projectId, "", config);
        engine.fundProject(projectId, 100_000e18, 50, address(0));
        vm.stopPrank();

        _ensureStake(contribUser, STAKE_AMOUNT);

        vm.prank(contribUser);
        (uint256 newClaimId, uint256[] memory newIndices) = engine.claimToContribute(projectId, 1, address(0));
        contribIndex = newIndices[0];

        vm.prank(contribUser);
        engine.contribute(newClaimId, contribIndex, keccak256("submission"), "");

        _validateOnProject(projectId, contribIndex, 8000);
    }

    function _validateOnProject(bytes32 projectId, uint256 index, uint256 score) internal {
        address[3] memory validators = [validator1, validator2, validator3];
        bytes32[3] memory salts;

        // Commit phase
        for (uint256 i; i < 3; ++i) {
            salts[i] = keccak256(abi.encodePacked("salt", validators[i], projectId, index));
            bytes32 commitHash = keccak256(abi.encodePacked(score, salts[i]));

            vm.prank(validators[i]);
            engine.claimToValidate(projectId, 1);

            _ensureValidatorCapacity(validators[i], VALIDATOR_STAKE);

            vm.prank(validators[i]);
            engine.commitValidation(projectId, index, commitHash, VALIDATOR_STAKE, address(0));
        }

        // Warp past commit deadline to allow reveals (only once)
        vm.warp(block.timestamp + engine.commitDeadline());

        // Reveal phase
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.revealValidation(projectId, index, score, salts[i]);
        }

        engine.computeConsensus(projectId, index);
    }

    function _fullValidationOnProject(address val, bytes32 projectId, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(val);
        engine.claimToValidate(projectId, 1);

        _ensureValidatorCapacity(val, VALIDATOR_STAKE);

        vm.prank(val);
        engine.commitValidation(projectId, index, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }

    function _ensureStake(address user, uint256 needed) internal {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18;
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }

    function _ensureValidatorCapacity(address val, uint256 needed) internal {
        _ensureStake(val, needed * 2);
        vm.prank(val);
        engine.lockValidatorCapacity(needed);
    }
}
