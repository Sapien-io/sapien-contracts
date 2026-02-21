// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    Reputation,
    StakeAccount
} from "src/Types.sol";

/// @title SapienCoreHandler
/// @notice Foundry invariant-test handler that drives the full PoQ protocol lifecycle
///         through valid state transitions while tracking ghost variables for invariant checks.
/// @dev Uses a state-machine approach: tracks which projects/contributions are at which phase
///      and only invokes the appropriate next operation. Ghost variables track token flows
///      for solvency invariants.
contract SapienCoreHandler is Test {
    // ── Contracts ────────────────────────────────────────────────────────
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    // ── Actors ──────────────────────────────────────────────────────────
    address public originator;
    address[] public contributors;
    address[] public validators;
    address public adapter;

    // ── Protocol state tracking ─────────────────────────────────────────
    bytes32[] public projectIds;
    mapping(bytes32 => bool) public projectExists;

    // Track contributions ready for validation
    struct PendingContribution {
        bytes32 projectId;
        uint256 index;
    }
    PendingContribution[] public pendingContributions;

    // Track contributions that have been validated (ready for consensus)
    struct ValidatedContribution {
        bytes32 projectId;
        uint256 index;
    }
    ValidatedContribution[] public validatedContributions;

    // Track contributions with consensus computed (ready for settlement)
    struct SettleableContribution {
        bytes32 projectId;
        uint256 index;
    }
    SettleableContribution[] public settleableContributions;

    // Track accepted contributions (ready for reward release)
    struct AcceptedContribution {
        bytes32 projectId;
        uint256 index;
    }
    AcceptedContribution[] public acceptedContributions;

    // Track which validators committed per contribution
    mapping(bytes32 => mapping(uint256 => address[])) public committedValidators;
    mapping(bytes32 => mapping(uint256 => uint256)) public commitCount;

    // Track which validators need settlement per contribution
    mapping(bytes32 => mapping(uint256 => address[])) public validatorsToSettle;

    // ── Ghost variables ─────────────────────────────────────────────────
    uint256 public ghost_totalFunded; // Total tokens sent to engine
    uint256 public ghost_totalProtocolFees; // Total protocol fees taken
    uint256 public ghost_totalOriginationFees; // Total origination adapter fees
    uint256 public ghost_totalRewardsClaimed; // Total tokens claimed by users
    uint256 public ghost_projectCount;
    uint256 public ghost_contributionCount;
    uint256 public ghost_consensusCount;
    uint256 public ghost_settleCount;
    uint256 public ghost_rewardReleaseCount;

    // ── Call counters ───────────────────────────────────────────────────
    uint256 public calls_createProject;
    uint256 public calls_fundProject;
    uint256 public calls_claimToContribute;
    uint256 public calls_contribute;
    uint256 public calls_commitValidation;
    uint256 public calls_revealValidation;
    uint256 public calls_computeConsensus;
    uint256 public calls_settleValidator;
    uint256 public calls_releaseReward;
    uint256 public calls_claimReward;

    // ── Configuration ───────────────────────────────────────────────────
    uint256 public constant FUND_AMOUNT = 10_000e18;
    uint256 public constant QUANTITY = 5;
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;
    uint16 public constant NUM_VALIDATIONS = 3;
    uint256 public nextProjectSeed;

    constructor(
        SapienCore engine_,
        SapienVault vault_,
        MockERC20 token_,
        address originator_,
        address[] memory contributors_,
        address[] memory validators_,
        address adapter_
    ) {
        engine = engine_;
        vault = vault_;
        token = token_;
        originator = originator_;
        adapter = adapter_;

        for (uint256 i; i < contributors_.length; ++i) {
            contributors.push(contributors_[i]);
        }
        for (uint256 i; i < validators_.length; ++i) {
            validators.push(validators_[i]);
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    function _selectContributor(uint256 seed) internal view returns (address) {
        return contributors[seed % contributors.length];
    }

    function _selectValidator(uint256 seed) internal view returns (address) {
        return validators[seed % validators.length];
    }

    // ── Phase 0: Project creation & funding ─────────────────────────────

    function createAndFundProject(uint256 fundAmount) external {
        fundAmount = bound(fundAmount, 1_000e18, 100_000e18);

        bytes32 projectId = keccak256(abi.encodePacked("invariant-project", nextProjectSeed++));
        if (projectExists[projectId]) return;

        // Mint tokens for originator
        token.mint(originator, fundAmount);

        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: NUM_VALIDATIONS,
            requiredSkill: bytes32(0),
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0
        });

        engine.createProject(projectId, "", config);

        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, QUANTITY, adapter);

        vm.stopPrank();

        projectIds.push(projectId);
        projectExists[projectId] = true;

        ghost_totalFunded += fundAmount;
        // Protocol fee: fundAmount * protocolFeeBps / BPS
        uint256 protocolFee = (fundAmount * 100) / 10_000; // 1% default
        ghost_totalProtocolFees += protocolFee;
        uint256 remaining = fundAmount - protocolFee;
        // Origination fee: remaining * originationFeeBps / BPS
        uint256 originationFee = (remaining * 200) / 10_000; // 2% default
        ghost_totalOriginationFees += originationFee;

        ghost_projectCount++;
        calls_createProject++;
        calls_fundProject++;
    }

    // ── Phase 1: Claim & Contribute ─────────────────────────────────────

    function claimAndContribute(uint256 projectSeed, uint256 contributorSeed) external {
        if (projectIds.length == 0) return;

        bytes32 projectId = projectIds[projectSeed % projectIds.length];
        address contributor = _selectContributor(contributorSeed);

        Project memory proj = engine.getProject(projectId);
        if (proj.availableSlots == 0) return;
        if (proj.status != ProjectStatus.Funded && proj.status != ProjectStatus.Active) return;

        // Ensure contributor has enough stake
        uint256 totalStaked = vault.totalStaked(contributor);
        StakeAccount memory acct = vault.getStakeAccount(contributor);
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        uint256 available = totalStaked > totalLocked ? totalStaked - totalLocked : 0;

        if (available < STAKE_AMOUNT) {
            // Top up contributor stake
            uint256 needed = STAKE_AMOUNT - available + 1e18; // buffer
            token.mint(contributor, needed);
            vm.startPrank(contributor);
            token.approve(address(vault), needed);
            vault.deposit(needed, contributor);
            vm.stopPrank();
        }

        // Claim 1 index
        vm.startPrank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, adapter);

        // Submit contribution immediately
        bytes32 hash = keccak256(abi.encodePacked("submission", projectId, indices[0], block.timestamp));
        engine.contribute(claimId, indices[0], hash, "");
        vm.stopPrank();

        // Track as pending (ready for validation)
        pendingContributions.push(PendingContribution({projectId: projectId, index: indices[0]}));

        ghost_contributionCount++;
        calls_claimToContribute++;
        calls_contribute++;
    }

    // ── Phase 2: Commit-Reveal Validation ───────────────────────────────

    function commitValidation(uint256 contribSeed, uint256 validatorSeed) external {
        if (pendingContributions.length == 0) return;

        uint256 ci = contribSeed % pendingContributions.length;
        PendingContribution memory pc = pendingContributions[ci];

        // Check we haven't exceeded required validations
        if (commitCount[pc.projectId][pc.index] >= NUM_VALIDATIONS) return;

        address validator = _selectValidator(validatorSeed);

        // Check validator is not the contributor
        Contribution memory contrib = engine.getContribution(pc.projectId, pc.index);
        if (contrib.contributor == validator) return;

        // Check validator hasn't already committed
        address[] storage committed = committedValidators[pc.projectId][pc.index];
        for (uint256 i; i < committed.length; ++i) {
            if (committed[i] == validator) return;
        }

        // Ensure validator has enough capacity
        StakeAccount memory acct = vault.getStakeAccount(validator);
        if (acct.validatorCapacity < VALIDATOR_STAKE) {
            uint256 totalStaked = vault.totalStaked(validator);
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 available = totalStaked > totalLocked ? totalStaked - totalLocked : 0;

            if (available < VALIDATOR_STAKE) {
                uint256 needed = VALIDATOR_STAKE - available + 1e18;
                token.mint(validator, needed);
                vm.startPrank(validator);
                token.approve(address(vault), needed);
                vault.deposit(needed, validator);
                vm.stopPrank();
            }

            vm.startPrank(validator);
            engine.lockValidatorCapacity(VALIDATOR_STAKE);
            vm.stopPrank();
        }

        // Generate score (bounded)
        uint16 score = uint16(bound(uint256(keccak256(abi.encodePacked(validatorSeed, pc.index))), 5000, 9000));
        bytes32 salt = keccak256(abi.encodePacked("salt", validator, pc.index, block.timestamp));
        uint256 nonce = engine.getSubmissionNonce(pc.projectId, pc.index);
        bytes32 commitHash = keccak256(abi.encodePacked(pc.projectId, pc.index, nonce, validator, score, salt));

        vm.startPrank(validator);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = pc.index;
            engine.claimToValidate(pc.projectId, _indices);
        }
        engine.commitValidation(pc.projectId, pc.index, commitHash, uint128(VALIDATOR_STAKE), address(0));
        engine.revealValidation(pc.projectId, pc.index, score, salt);
        vm.stopPrank();

        committed.push(validator);
        commitCount[pc.projectId][pc.index]++;

        // If we've reached required validations, move to validated list
        if (commitCount[pc.projectId][pc.index] >= NUM_VALIDATIONS) {
            validatedContributions.push(ValidatedContribution({projectId: pc.projectId, index: pc.index}));

            // Copy validators for settlement tracking
            for (uint256 i; i < committed.length; ++i) {
                validatorsToSettle[pc.projectId][pc.index].push(committed[i]);
            }

            // Remove from pending (swap and pop)
            pendingContributions[ci] = pendingContributions[pendingContributions.length - 1];
            pendingContributions.pop();
        }

        calls_commitValidation++;
        calls_revealValidation++;
    }

    // ── Phase 3: Compute Consensus ──────────────────────────────────────

    function computeConsensus(uint256 seed) external {
        if (validatedContributions.length == 0) return;

        uint256 vi = seed % validatedContributions.length;
        ValidatedContribution memory vc = validatedContributions[vi];

        engine.computeConsensus(vc.projectId, vc.index);

        // Move to settleable
        settleableContributions.push(SettleableContribution({projectId: vc.projectId, index: vc.index}));

        // Check if accepted for reward tracking
        Contribution memory contrib = engine.getContribution(vc.projectId, vc.index);
        if (contrib.status == ContributionStatus.Accepted) {
            acceptedContributions.push(AcceptedContribution({projectId: vc.projectId, index: vc.index}));
        }

        // Remove from validated (swap and pop)
        validatedContributions[vi] = validatedContributions[validatedContributions.length - 1];
        validatedContributions.pop();

        ghost_consensusCount++;
        calls_computeConsensus++;
    }

    // ── Phase 4: Settle Validators ──────────────────────────────────────

    function settleValidator(uint256 contribSeed, uint256 validatorSeed) external {
        if (settleableContributions.length == 0) return;

        uint256 si = contribSeed % settleableContributions.length;
        SettleableContribution memory sc = settleableContributions[si];

        address[] storage toSettle = validatorsToSettle[sc.projectId][sc.index];
        if (toSettle.length == 0) return;

        uint256 vIdx = validatorSeed % toSettle.length;
        address validator = toSettle[vIdx];

        vm.prank(validator);
        uint256 nonce = engine.getContribution(sc.projectId, sc.index).consensusNonce;
        engine.settleValidator(sc.projectId, sc.index, nonce);

        // Remove settled validator (swap and pop)
        toSettle[vIdx] = toSettle[toSettle.length - 1];
        toSettle.pop();

        // If all validators settled, remove from settleable list
        if (toSettle.length == 0) {
            settleableContributions[si] = settleableContributions[settleableContributions.length - 1];
            settleableContributions.pop();
        }

        ghost_settleCount++;
        calls_settleValidator++;
    }

    // ── Phase 5: Release Contributor Rewards ────────────────────────────

    function releaseContributorReward(uint256 seed) external {
        if (acceptedContributions.length == 0) return;

        uint256 ai = seed % acceptedContributions.length;
        AcceptedContribution memory ac = acceptedContributions[ai];

        Contribution memory contrib = engine.getContribution(ac.projectId, ac.index);
        if (contrib.rewardReleased) {
            // Already released, remove from list
            acceptedContributions[ai] = acceptedContributions[acceptedContributions.length - 1];
            acceptedContributions.pop();
            return;
        }

        // Warp past challenge period
        if (block.timestamp < contrib.challengeEndsAt) {
            vm.warp(contrib.challengeEndsAt + 1);
        }

        engine.releaseContributorReward(ac.projectId, ac.index);

        // Remove from list
        acceptedContributions[ai] = acceptedContributions[acceptedContributions.length - 1];
        acceptedContributions.pop();

        ghost_rewardReleaseCount++;
        calls_releaseReward++;
    }

    // ── Phase 6: Claim Rewards ──────────────────────────────────────────

    function claimReward(uint256 actorSeed) external {
        // Try claiming for any actor (contributors, validators, adapter)
        address[] memory allActors = new address[](contributors.length + validators.length + 1);
        uint256 idx;
        for (uint256 i; i < contributors.length; ++i) {
            allActors[idx++] = contributors[i];
        }
        for (uint256 i; i < validators.length; ++i) {
            allActors[idx++] = validators[i];
        }
        allActors[idx] = adapter;

        address actor = allActors[actorSeed % allActors.length];
        uint256 pending = engine.getPendingRewards(actor, address(token));
        if (pending == 0) return;

        vm.prank(actor);
        engine.claimReward(address(token));

        ghost_totalRewardsClaimed += pending;
        calls_claimReward++;
    }

    // ── View helpers for invariant tests ────────────────────────────────

    function getProjectCount() external view returns (uint256) {
        return projectIds.length;
    }

    function getPendingContributionCount() external view returns (uint256) {
        return pendingContributions.length;
    }

    function getValidatedContributionCount() external view returns (uint256) {
        return validatedContributions.length;
    }

    function getSettleableContributionCount() external view returns (uint256) {
        return settleableContributions.length;
    }

    function getAcceptedContributionCount() external view returns (uint256) {
        return acceptedContributions.length;
    }
}
