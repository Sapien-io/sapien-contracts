// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    Project,
    Claim,
    Contribution,
    Reputation,
    ContributionStatus,
    ConsensusReport,
    Dispute,
    OriginatorReport,
    ValidationClaim
} from "src/Types.sol";

/// @title ISapienCore
/// @notice Interface for the SapienCore contract — the unified entry-point for the Sapien
///         Proof-of-Quality (PoQ) protocol covering project origination, contribution,
///         commit-reveal validation, stake-weighted consensus, dispute resolution, and
///         reward distribution.
/// @dev Deployed behind an ERC-1967 UUPS proxy with ERC-7201 namespaced storage.
interface ISapienCore {
    // ── Errors ─────────────────────────────────────────────────────────

    /// @dev Caller is not the originator of the project.
    error NotProjectOriginator();

    /// @dev Project originators cannot submit contributions to their own project.
    error OriginatorCannotContribute();

    /// @dev POQ-8 FIX: Originator cannot validate their own project to prevent conflicts of interest.
    error OriginatorCannotValidate();

    /// @dev Caller is not the owner of the referenced claim.
    error NotClaimOwner();

    /// @dev The contribution index is not part of the specified claim.
    error IndexNotInClaim();

    /// @dev The claim deadline has already passed.
    error ClaimDeadlinePassed();

    /// @dev The claim deadline has not yet passed (required for expiration).
    error ClaimDeadlineNotPassed();

    /// @dev The user's available stake is below the required amount.
    /// @param required Minimum stake required.
    /// @param available Stake currently available.
    error InsufficientStake(uint256 required, uint256 available);

    /// @dev The user's reputation is below the project's minimum threshold.
    /// @param required Minimum reputation score needed.
    /// @param actual User's current reputation score.
    error InsufficientReputation(uint256 required, uint256 actual);

    /// @dev Not enough validators have revealed to compute consensus.
    /// @param have Number of reveals received.
    /// @param need Number of reveals required.
    error ConsensusNotReady(uint256 have, uint256 need);

    /// @dev Consensus has already been computed for this contribution nonce.
    error ConsensusAlreadyComputed();

    /// @dev The validator has already been settled for this round.
    error AlreadySettled();

    /// @dev The challenge period has not yet elapsed.
    error ChallengeNotElapsed();

    /// @dev The revealed score and salt do not match the stored commit hash.
    error InvalidReveal();

    /// @dev The adapter fee exceeds the protocol maximum.
    /// @param provided Fee basis points provided.
    /// @param max Maximum allowed basis points.
    error AdapterFeeTooHigh(uint256 provided, uint256 max);

    /// @dev The project is not in an active (funded) state.
    error ProjectNotActive();

    /// @dev The project does not exist.
    error ProjectNotFound();

    /// @dev The project configuration is invalid.
    /// @param reason Human-readable explanation.
    error InvalidProjectConfig(string reason);

    /// @dev No contribution slots remain for the project.
    error NoSlotsAvailable();

    /// @dev The requested claim quantity exceeds available slots.
    /// @param requested Number of slots requested.
    /// @param max Number of slots available.
    error ClaimQuantityTooHigh(uint256 requested, uint256 max);

    /// @dev The contribution index is out of bounds.
    error InvalidIndex();

    /// @dev The contribution slot is not in the Reserved state.
    error IndexNotReserved();

    /// @dev The contribution slot is not in the Pending (submitted) state.
    error IndexNotSubmitted();

    /// @dev The validator has already committed a score for this contribution.
    error AlreadyCommitted();

    /// @dev The validator has not committed and cannot reveal.
    error NotCommitted();

    /// @dev The reveal window has closed.
    error RevealWindowClosed();

    /// @dev The commit phase is still active; reveals are not yet allowed.
    error CommitPhaseActive();

    /// @dev The contribution was not accepted by consensus.
    error ContributionNotAccepted();

    /// @dev The contributor reward has already been released.
    error RewardAlreadyReleased();

    /// @dev The user has no pending reward to claim for the given token.
    error NoRewardToClaim();

    /// @dev The reward claim amount is below the protocol minimum.
    /// @param amount Amount attempted.
    /// @param minClaimAmount Minimum required.
    error ClaimAmountTooSmall(uint256 amount, uint256 minClaimAmount);

    /// @dev The user must wait for the cooldown period to expire before claiming again.
    /// @param timestamp Current block timestamp.
    /// @param cooldownEnd Timestamp when the cooldown expires.
    error ClaimCooldownActive(uint256 timestamp, uint256 cooldownEnd);

    /// @dev A zero address was provided where a non-zero address is required.
    error ZeroAddress();

    /// @dev A zero amount was provided where a non-zero amount is required.
    error ZeroAmount();

    /// @dev Escrow refund blocked: contributor settlements still pending.
    /// POQ-15 FIX: Prevents originator from draining escrow before all contributors claim.
    error PendingContributorSettlements();

    /// @dev The validation score is outside the valid range.
    error InvalidScore();

    /// @dev Validators cannot score their own contribution.
    error CannotValidateOwnContribution();

    /// @dev The validator has already revealed their score.
    error AlreadyRevealed();

    /// @dev The caller has not claimed the contribution index for validation.
    error ValidationNotClaimed();

    /// @dev The provided commit hash is invalid (e.g., zero).
    error InvalidCommitHash();

    /// @dev The project has not been marked as completed.
    error ProjectNotCompleted();

    /// @dev The project still has contributions in the active pipeline.
    error ProjectHasActivePipeline();

    /// @dev POQ-8 FIX: The project has no accepted contributions and cannot be completed.
    error NoAcceptedContributions();

    /// @dev No pending contributions are eligible for this validator to claim.
    error NoEligibleContributions();

    /// @dev The force-settle delay has not elapsed since the challenge period ended.
    error ForceSettleTooEarly();

    /// @dev The evidence hash is invalid (e.g., zero).
    error InvalidEvidenceHash();

    /// @dev The provided deadline exceeds the protocol maximum.
    /// @param provided Deadline value provided.
    /// @param max Maximum allowed value.
    error DeadlineTooLong(uint256 provided, uint256 max);
    error DeadlineTooShort(uint256 provided, uint256 min);

    // ── Dispute Errors ──────────────────────────────────────────────────

    /// @dev A dispute is already open for this contribution.
    error DisputeAlreadyOpen();

    /// @dev The dispute has already been resolved.
    error DisputeAlreadyClosed();

    /// @dev No open dispute exists for the contribution.
    error DisputeNotOpen();

    /// @dev The dispute window has closed and new disputes cannot be opened.
    error DisputeWindowClosed();

    /// @dev A dispute is currently in progress; the action is blocked.
    error DisputeInProgress();

    /// @dev The dispute resolution deadline has not expired (required for escalation).
    error DisputeResolutionNotExpired();

    /// @dev Emitted when attempting to recycle a slot while prior-round validators have not yet settled.
    error PriorRoundNotSettled();

    /// @dev Contributors cannot dispute their own contribution.
    error CannotDisputeOwnContribution();

    /// @dev Consensus must be computed before a dispute can be opened.
    error ConsensusNotComputed();

    /// @dev The dispute bond exceeds the protocol maximum.
    /// @param provided Bond basis points provided.
    /// @param max Maximum allowed basis points.
    error DisputeBondTooHigh(uint256 provided, uint256 max);

    // ── Skill Registry Errors ───────────────────────────────────────────

    /// @dev The specified skill is not registered in the skill registry.
    error SkillNotRegistered();

    /// @dev The skill is already registered.
    error SkillAlreadyRegistered();

    // ── Originator Report Errors ────────────────────────────────────────

    /// @dev An originator report is already open for this project.
    error OriginatorReportAlreadyOpen();

    /// @dev No open originator report exists for the project.
    error OriginatorReportNotOpen();

    /// @dev The project is not eligible for cancellation.
    error ProjectNotCancellable();

    /// @dev All eligible contributions have already been settled for this cancelled project.
    error SettlementAlreadyComplete();

    // ── Events ─────────────────────────────────────────────────────────

    // ── Projects ────────────────────────────────────────────────────────

    /// @notice Emitted when a new project is created.
    /// @param projectId Unique identifier for the project.
    /// @param originator Address of the project creator.
    /// @param metadataCid IPFS CID pointing to the project metadata.
    event ProjectCreated(bytes32 indexed projectId, address indexed originator, string metadataCid);

    /// @notice Emitted when a project is funded and activated.
    /// @param projectId Unique identifier for the project.
    /// @param amount Total reward tokens deposited.
    /// @param quantity Number of contribution slots created.
    event ProjectFunded(bytes32 indexed projectId, uint256 amount, uint256 quantity);

    /// @notice Emitted when an operator removes a project.
    /// @param projectId Unique identifier for the project.
    /// @param admin Address of the operator who removed it.
    event ProjectRemoved(bytes32 indexed projectId, address indexed admin);

    // ── Claims & Contributions ──────────────────────────────────────────

    /// @notice Emitted when a contributor claims one or more contribution slots.
    /// @param claimId Unique identifier for the claim.
    /// @param projectId Project the claim belongs to.
    /// @param claimant Address of the contributor.
    /// @param indices Array of contribution slot indices assigned.
    event ClaimCreated(uint256 indexed claimId, bytes32 indexed projectId, address indexed claimant, uint256[] indices);

    /// @notice Emitted when an expired claim's unsubmitted slots are released.
    /// @param claimId Unique identifier for the claim.
    /// @param unsubmittedCount Number of slots returned to the pool.
    event ClaimExpired(uint256 indexed claimId, uint256 unsubmittedCount);

    /// @notice Emitted when a contribution is submitted for a claimed slot.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param contributor Address of the contributor.
    /// @param submissionHash Hash of the submission content.
    /// @param dataCid IPFS CID pointing to the contribution data.
    event ContributionSubmitted(
        bytes32 indexed projectId, uint256 indexed index, address contributor, bytes32 submissionHash, string dataCid
    );

    // ── Validation ──────────────────────────────────────────────────────

    /// @notice Emitted when a validator claims contribution indices for validation.
    /// @param claimId Unique identifier for the validation claim.
    /// @param projectId Project the validation claim belongs to.
    /// @param validator Address of the validator.
    /// @param indices Contribution indices claimed for validation.
    event ValidationClaimCreated(
        uint256 indexed claimId, bytes32 indexed projectId, address indexed validator, uint256[] indices
    );

    /// @notice Emitted when an expired validation claim's uncommitted slots are released.
    /// @param claimId Unique identifier for the validation claim.
    /// @param uncommittedCount Number of slots that were not committed.
    event ValidationClaimExpired(uint256 indexed claimId, uint256 uncommittedCount);

    /// @notice Emitted when a validator commits a sealed score for a contribution.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param validator Address of the committing validator.
    event ValidationCommitted(bytes32 indexed projectId, uint256 indexed index, address indexed validator);

    /// @notice Emitted when a validator reveals their previously committed score.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param validator Address of the revealing validator.
    /// @param score The revealed quality score.
    event ValidationRevealed(
        bytes32 indexed projectId, uint256 indexed index, address indexed validator, uint256 score
    );

    // ── Finalization ────────────────────────────────────────────────────

    /// @notice Emitted when consensus is computed for a contribution.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param weightedAverage Stake-weighted average score.
    /// @param status Resulting contribution status (Accepted or Rejected).
    event ConsensusReached(
        bytes32 indexed projectId, uint256 indexed index, uint256 weightedAverage, ContributionStatus status
    );

    /// @notice Emitted when a validator is settled after consensus.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param validator Address of the settled validator.
    /// @param outlier Whether the validator was classified as an outlier.
    event ValidatorSettled(bytes32 indexed projectId, uint256 indexed index, address indexed validator, bool outlier);

    /// @notice Emitted when an expired validator commitment is cancelled and stake slashed.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param validator Address of the validator whose commitment expired.
    event ValidatorCommitmentExpired(bytes32 indexed projectId, uint256 indexed index, address indexed validator);

    /// @notice Emitted when a contributor's reward is released to their pending balance.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param contributor Address of the contributor.
    /// @param amount Reward amount released.
    event ContributorRewardReleased(
        bytes32 indexed projectId, uint256 indexed index, address indexed contributor, uint256 amount
    );

    /// @notice Emitted when a user withdraws accumulated pending rewards.
    /// @param user Address of the claimant.
    /// @param token Address of the reward token.
    /// @param amount Amount withdrawn.
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);

    // ── Reputation ──────────────────────────────────────────────────────

    /// @notice Emitted when a user's reputation score changes.
    /// @param user Address of the user.
    /// @param role Role identifier (e.g., contributor or validator skill hash).
    /// @param oldScore Previous reputation score.
    /// @param newScore Updated reputation score.
    event ReputationUpdated(address indexed user, bytes32 indexed role, uint256 oldScore, uint256 newScore);

    // ── Adapter Fees ────────────────────────────────────────────────────

    /// @notice Emitted when an origination adapter fee is paid during project funding.
    /// @param projectId Project the fee relates to.
    /// @param adapter Address of the adapter receiving the fee.
    /// @param amount Fee amount in reward tokens.
    event OriginationFeePaid(bytes32 indexed projectId, address indexed adapter, uint256 amount);

    /// @notice Emitted when a contribution adapter fee is paid during claim creation.
    /// @param projectId Project the fee relates to.
    /// @param index Contribution slot index.
    /// @param adapter Address of the adapter receiving the fee.
    /// @param amount Fee amount in reward tokens.
    event ContributionAdapterFeePaid(
        bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount
    );

    /// @notice Emitted when a validation adapter fee is paid during settlement.
    /// @param projectId Project the fee relates to.
    /// @param index Contribution slot index.
    /// @param adapter Address of the adapter receiving the fee.
    /// @param amount Fee amount in reward tokens.
    event ValidationAdapterFeePaid(
        bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount
    );

    // ── Disputes ────────────────────────────────────────────────────────

    /// @notice Emitted when a dispute is opened against a contribution's consensus outcome.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param challenger Address of the disputer.
    /// @param bond Bond amount locked by the challenger.
    /// @param evidenceCid IPFS CID pointing to dispute evidence.
    event DisputeOpened(
        bytes32 indexed projectId, uint256 indexed index, address indexed challenger, uint256 bond, string evidenceCid
    );

    /// @notice Emitted when an operator resolves a dispute.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param upheld Whether the dispute was upheld (true) or rejected (false).
    event DisputeResolved(bytes32 indexed projectId, uint256 indexed index, bool upheld);

    /// @notice Emitted when a dispute is escalated after the resolution deadline expires.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    event DisputeEscalated(bytes32 indexed projectId, uint256 indexed index);

    // ── Originator Reports ──────────────────────────────────────────────

    /// @notice Emitted when an originator is reported for misconduct.
    /// @param projectId Project the report targets.
    /// @param reporter Address of the reporter.
    /// @param bond Bond amount locked by the reporter.
    event OriginatorReported(bytes32 indexed projectId, address indexed reporter, uint256 bond);

    /// @notice Emitted when an operator resolves an originator report.
    /// @param projectId Project the report targets.
    /// @param upheld Whether the report was upheld (true) or rejected (false).
    event OriginatorReportResolved(bytes32 indexed projectId, bool upheld);

    /// @notice Emitted when an originator report is escalated after the resolution deadline expires.
    /// @param projectId Project the report targets.
    event OriginatorReportEscalated(bytes32 indexed projectId);

    /// @notice Emitted when a project is cancelled (e.g., due to an upheld originator report).
    /// @param projectId Project that was cancelled.
    event ProjectCancelled(bytes32 indexed projectId);

    /// @notice Emitted when a batch of contributor rewards is settled for a cancelled project.
    /// @param projectId Project the settlement belongs to.
    /// @param cursor New cursor position after this batch.
    /// @param processed Number of contributions settled in this batch.
    event ContributorRewardsSettled(bytes32 indexed projectId, uint256 cursor, uint256 processed);

    // ── Skill Registry ──────────────────────────────────────────────────

    /// @notice Emitted when a new skill is registered by the admin.
    /// @param skillId The bytes32 hash identifying the skill.
    /// @param name The human-readable skill name that was hashed.
    event SkillRegistered(bytes32 indexed skillId, string name);

    /// @notice Emitted when a skill is deregistered by the admin.
    /// @param skillId The bytes32 hash identifying the skill.
    /// @param name The human-readable skill name that was hashed.
    event SkillDeregistered(bytes32 indexed skillId, string name);

    // ── Admin ───────────────────────────────────────────────────────────

    /// @notice Emitted when the protocol fee is updated.
    /// @param newFeeBps New protocol fee in basis points.
    event ProtocolFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when the origination adapter fee cap is updated.
    /// @param newFeeBps New origination fee in basis points.
    event OriginationFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when the contribution adapter fee cap is updated.
    /// @param newFeeBps New contribution fee in basis points.
    event ContributionFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when the validation adapter fee cap is updated.
    /// @param newFeeBps New validation fee in basis points.
    event ValidationFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when the reputation decay rate is updated.
    /// @param newDecayRate New decay rate in basis points per day.
    event DecayRateUpdated(uint256 newDecayRate);

    /// @notice Emitted when the dispute bond percentage is updated.
    /// @param newBps New dispute bond in basis points of reward rate.
    event DisputeBondBpsUpdated(uint256 newBps);

    /// @notice Emitted when the per-slot originator stake requirement is updated.
    /// @param newAmount New stake amount required per slot.
    event OriginatorStakeRequirementUpdated(uint256 newAmount);

    /// @notice Emitted when the originator report bond percentage is updated.
    /// @param newBps New bond in basis points of total project rewards.
    event OriginatorReportBondBpsUpdated(uint256 newBps);

    /// @notice Emitted when the global minimum validation stake is updated.
    /// @param newAmount New minimum stake amount.
    event MinValidationStakeUpdated(uint256 newAmount);

    /// @notice Emitted when a project is marked as completed by its originator.
    /// @param projectId Project that was completed.
    event ProjectCompleted(bytes32 indexed projectId);

    /// @notice Emitted when remaining escrow is refunded to the originator after project completion.
    /// @param projectId Project the escrow belongs to.
    /// @param amount Amount refunded.
    event EscrowRefunded(bytes32 indexed projectId, uint256 amount);

    /// @notice Emitted when the protocol treasury address is updated.
    /// @param newTreasury New treasury address.
    event TreasuryUpdated(address indexed newTreasury);

    /// @notice Emitted when the minimum reward claim amount is updated.
    /// @param newAmount New minimum claim amount.
    event MinClaimAmountUpdated(uint256 newAmount);

    /// @notice Emitted when the reward claim cooldown period is updated.
    /// @param newCooldown New cooldown duration in seconds.
    event ClaimCooldownUpdated(uint256 newCooldown);

    /// @notice Emitted when the contribution claim deadline is updated.
    /// @param newDeadline New deadline duration in seconds.
    event ClaimDeadlineUpdated(uint256 newDeadline);

    /// @notice Emitted when the challenge period duration is updated.
    /// @param newPeriod New challenge period in seconds.
    event ChallengePeriodUpdated(uint256 newPeriod);

    /// @notice Emitted when the validation commit deadline is updated.
    /// @param newDeadline New commit deadline duration in seconds.
    event CommitDeadlineUpdated(uint256 newDeadline);

    /// @notice Emitted when the validation reveal deadline is updated.
    /// @param newDeadline New reveal deadline duration in seconds.
    event RevealDeadlineUpdated(uint256 newDeadline);

    /// @notice Emitted when the force-settle delay is updated.
    /// @param newDelay New force-settle delay in seconds.
    event ForceSettleDelayUpdated(uint256 newDelay);

    // ── Origination ─────────────────────────────────────────────

    /// @notice Register a new project with its metadata and configuration.
    /// @dev The project is created in `Created` status. The caller becomes the originator.
    ///      Must be followed by `fundProject` to activate the project.
    /// @param projectId Unique identifier for the project (chosen off-chain).
    /// @param metadataCid IPFS CID pointing to the project's metadata document.
    /// @param config Project configuration struct (reward token, thresholds, etc.).
    function createProject(bytes32 projectId, string calldata metadataCid, Project calldata config) external;

    /// @notice Fund a previously created project, activating it for contributions.
    /// @dev Transfers reward tokens from the originator into escrow, deducts the protocol fee,
    ///      pays an optional origination adapter fee, and locks originator stake if required.
    ///      Transitions the project from `Created` to `Active`.
    /// @param projectId Unique identifier for the project.
    /// @param amount Total reward tokens to deposit (before fees).
    /// @param quantity Number of contribution slots to create.
    /// @param adapter Optional adapter address for origination fee (address(0) for none).
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) external;

    /// @notice Remove a project that has not yet been funded. Operator-only.
    /// @param projectId Unique identifier for the project to remove.
    function removeProject(bytes32 projectId) external;

    // ── Contribution ─────────────────────────────────────────────

    /// @notice Claim one or more contribution slots for a project.
    /// @dev Reserves the requested number of slots and locks the contributor's stake.
    ///      The contributor must submit work before the claim deadline.
    /// @param projectId Project to contribute to.
    /// @param quantity Number of contribution slots to claim.
    /// @param adapter Optional adapter address for contribution fee (address(0) for none).
    /// @return claimId Unique identifier for the new claim.
    /// @return indices Array of contribution slot indices assigned to the claim.
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        external
        returns (uint256 claimId, uint256[] memory indices);

    /// @notice Submit a contribution for a single claimed slot.
    /// @dev Transitions the slot from Reserved to Pending and records the submission hash.
    ///      Must be called by the claim owner before the claim deadline.
    /// @param claimId Identifier of the contributor's claim.
    /// @param index Contribution slot index (must be part of the claim).
    /// @param submissionHash Hash of the submitted content for integrity verification.
    /// @param dataCid IPFS CID pointing to the contribution data.
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid) external;

    /// @notice Submit contributions for multiple claimed slots in a single transaction.
    /// @dev Batch version of `contribute`. All arrays must have the same length.
    /// @param claimId Identifier of the contributor's claim.
    /// @param indices Array of contribution slot indices.
    /// @param submissionHashes Array of submission content hashes.
    /// @param dataCids Array of IPFS CIDs pointing to each contribution's data.
    function batchContribute(
        uint256 claimId,
        uint256[] calldata indices,
        bytes32[] calldata submissionHashes,
        string[] calldata dataCids
    ) external;

    /// @notice Expire a claim and release any unsubmitted contribution slots back to the pool.
    /// @dev Can be called by anyone after the claim deadline has passed. Slashes the
    ///      contributor's locked stake for unsubmitted slots.
    /// @param claimId Identifier of the claim to expire.
    /// @param indices Array of unsubmitted slot indices to release.
    function expireClaim(uint256 claimId, uint256[] calldata indices) external;

    // ── Validation ─────────────────────────────────────────────────────

    /// @notice Lock tokens as validator capacity, enabling the caller to commit validations.
    /// @dev Tokens are moved from available balance to the validator capacity bucket in the vault.
    /// @param amount Amount of tokens to lock as validator capacity.
    function lockValidatorCapacity(uint256 amount) external;

    /// @notice Unlock tokens from validator capacity back to available balance.
    /// @param amount Amount of tokens to unlock.
    function unlockValidatorCapacity(uint256 amount) external;

    /// @notice Claim one or more contribution indices for validation.
    /// @dev Creates a validation claim by randomly assigning pending contributions from the
    ///      project. The validator specifies how many they want; the protocol picks which ones.
    /// @param projectId Project containing the contributions.
    /// @param quantity Number of contributions the validator wants to be assigned.
    /// @return claimId Unique identifier for the new validation claim.
    function claimToValidate(bytes32 projectId, uint256 quantity) external returns (uint256 claimId);

    /// @notice Commit a sealed validation score for a contribution (commit phase of commit-reveal).
    /// @dev The commit hash should be `keccak256(abi.encodePacked(score, salt))`. The validator's
    ///      stake is locked proportionally. Must be called before the commit deadline.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param commitHash Sealed hash of the score and salt.
    /// @param stakeAmount Amount of validator capacity to stake on this validation.
    /// @param adapter Optional adapter address for validation fee (address(0) for none).
    function commitValidation(
        bytes32 projectId,
        uint256 index,
        bytes32 commitHash,
        uint256 stakeAmount,
        address adapter
    ) external;

    /// @notice Commit sealed validation scores for multiple contributions in a single transaction.
    /// @dev Batch version of `commitValidation`. All arrays must have the same length.
    /// @param projectId Project containing the contributions.
    /// @param indices Array of contribution slot indices.
    /// @param commitHashes Array of sealed score hashes.
    /// @param stakeAmounts Array of stake amounts per validation.
    /// @param adapter Optional adapter address for validation fee (address(0) for none).
    function batchCommitValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        bytes32[] calldata commitHashes,
        uint256[] calldata stakeAmounts,
        address adapter
    ) external;

    /// @notice Reveal a previously committed validation score (reveal phase of commit-reveal).
    /// @dev The provided score and salt must hash to the stored commit hash. Must be called
    ///      within the reveal window (after commit deadline, before reveal deadline).
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param score The quality score (must be within the valid range).
    /// @param salt Random salt used when committing.
    function revealValidation(bytes32 projectId, uint256 index, uint256 score, bytes32 salt) external;

    /// @notice Reveal previously committed validation scores for multiple contributions.
    /// @dev Batch version of `revealValidation`. All arrays must have the same length.
    /// @param projectId Project containing the contributions.
    /// @param indices Array of contribution slot indices.
    /// @param scores Array of quality scores.
    /// @param salts Array of salts corresponding to each commit.
    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) external;

    /// @notice Cancel an expired validation claim and release uncommitted slots.
    /// @dev Can be called by anyone after the validation claim deadline passes.
    /// @param claimId Identifier of the validation claim to cancel.
    function cancelExpiredValidationClaim(uint256 claimId) external;

    // ── Finalization ───────────────────────────────────────────────────

    /// @notice Compute stake-weighted consensus for a contribution after sufficient reveals.
    /// @dev Calculates the weighted average score, standard deviation, and identifies outlier
    ///      validators. Sets the contribution status to Accepted or Rejected based on the
    ///      project's consensus threshold. Starts the challenge period.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    function computeConsensus(bytes32 projectId, uint256 index) external;

    /// @notice Settle the calling validator's stake and rewards for a contribution.
    /// @dev Must be called after the challenge period ends and no dispute is in progress.
    ///      Outlier validators are slashed; accurate validators receive their stake back
    ///      plus a share of the validator reward pool. Updates reputation.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce to settle against.
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external;

    /// @notice Force-settle an unresponsive validator after an extended delay.
    /// @dev Permissionless — can be called by anyone once the force-settle delay has elapsed
    ///      past the challenge period. The validator is settled as if they called `settleValidator`.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce to settle against.
    /// @param validator Address of the validator to force-settle.
    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator) external;

    /// @notice Release a contributor's reward to their pending balance after consensus.
    /// @dev The contribution must be Accepted and the challenge period must have elapsed
    ///      with no active dispute. The reward is moved from project escrow to the
    ///      contributor's pending rewards balance.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    function releaseContributorReward(bytes32 projectId, uint256 index) external;

    /// @notice Withdraw accumulated pending rewards for a specific token.
    /// @dev Transfers the user's full pending balance for the given token. Subject to
    ///      minimum claim amount and cooldown period restrictions.
    /// @param token Address of the reward token to withdraw.
    function claimReward(address token) external;

    // ── Disputes ─────────────────────────────────────────────────────────

    /// @notice Open a dispute against a contribution's consensus outcome.
    /// @dev The challenger must post a bond proportional to the contribution's reward rate.
    ///      Can only be called during the challenge period, and not by the contributor themselves.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param evidenceHash Hash of the dispute evidence for integrity verification.
    /// @param evidenceCid IPFS CID pointing to the dispute evidence.
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid) external;

    /// @notice Resolve an open dispute. Operator-only.
    /// @dev If upheld, the consensus outcome is invalidated and a new validation round begins.
    ///      The challenger's bond is returned and the contributor's reward is redistributed.
    ///      If rejected, the challenger's bond is forfeited to the contributor.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce of the dispute to resolve.
    /// @param upheld Whether the dispute is upheld (true) or rejected (false).
    function resolveDispute(bytes32 projectId, uint256 index, uint256 nonce, bool upheld) external;

    /// @notice Escalate an unresolved dispute after the resolution deadline expires.
    /// @dev Permissionless — can be called by anyone once the resolution deadline passes.
    ///      The dispute is automatically upheld, triggering re-validation.
    /// @param projectId Project containing the contribution.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce of the dispute to escalate.
    function escalateDispute(bytes32 projectId, uint256 index, uint256 nonce) external;

    // ── Originator Reports ──────────────────────────────────────────────

    /// @notice Report a project originator for misconduct.
    /// @dev The reporter must post a bond proportional to the project's total rewards.
    ///      Only one report can be open per project at a time.
    /// @param projectId Project to report.
    /// @param evidenceHash Hash of the evidence for integrity verification.
    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) external;

    /// @notice Resolve an open originator report. Operator-only.
    /// @dev If upheld, the project is cancelled and the originator's stake is slashed.
    ///      If rejected, the reporter's bond is forfeited.
    /// @param projectId Project the report targets.
    /// @param upheld Whether the report is upheld (true) or rejected (false).
    function resolveOriginatorReport(bytes32 projectId, bool upheld) external;

    /// @notice Escalate an unresolved originator report after the resolution deadline expires.
    /// @dev Permissionless — can be called by anyone once the resolution deadline passes.
    ///      The report is automatically upheld and the project is cancelled.
    /// @param projectId Project the report targets.
    function escalateOriginatorReport(bytes32 projectId) external;

    // ── Batch Settlement ─────────────────────────────────────────────────

    /// @notice Settle contributor rewards for a cancelled project in bounded batches.
    /// @dev Permissionless — can be called by anyone (contributors, keepers, operators).
    ///      Processes up to `batchSize` contributions starting from the internal cursor.
    ///      Only settles contributions that are Accepted, finalized (challenge elapsed),
    ///      and have no open/upheld dispute. Call repeatedly until all contributions
    ///      are processed. Contributors can also use `releaseContributorReward()` to
    ///      individually claim their reward on a cancelled project.
    /// @param projectId Project to settle rewards for (must be Cancelled).
    /// @param batchSize Maximum number of contribution indices to process in this call.
    /// @return processed Number of contributions actually settled in this batch.
    function settleContributorRewards(bytes32 projectId, uint256 batchSize) external returns (uint256 processed);

    /// @notice Retrieve the current reward settlement cursor for a project.
    /// @param projectId Project to query.
    /// @return The current cursor position (next index to process).
    function getSettlementCursor(bytes32 projectId) external view returns (uint256);

    // ── Project Completion ───────────────────────────────────────────────

    /// @notice Mark a project as completed by its originator.
    /// @dev Can only be called by the project originator when all contributions have been
    ///      processed (no active pipeline). Transitions the project to Completed status
    ///      and unlocks the originator's stake.
    /// @param projectId Project to complete.
    function completeProject(bytes32 projectId) external;

    /// @notice Refund remaining escrow to the originator after project completion.
    /// @dev Can only be called after the project is completed. Returns any unused reward
    ///      tokens from the project escrow to the originator's pending rewards.
    /// @param projectId Project to refund.
    function refundEscrow(bytes32 projectId) external;

    // ── Skill Registry ─────────────────────────────────────────────────

    /// @notice Register a new skill in the protocol skill registry. Admin-only.
    /// @dev The skill name is hashed via keccak256 and stored as bytes32. The original name
    ///      is emitted in the event for off-chain indexing.
    /// @param name The human-readable skill name (e.g., "DATA_ANNOTATION").
    function registerSkill(string calldata name) external;

    /// @notice Remove a skill from the registry. Admin-only.
    /// @dev Does not affect in-flight projects -- only prevents new projects from using this skill.
    /// @param name The human-readable skill name to deregister.
    function deregisterSkill(string calldata name) external;

    /// @notice Check whether a skill is registered.
    /// @param skillId The bytes32 hash identifying the skill.
    /// @return True if the skill is registered.
    function isSkillRegistered(bytes32 skillId) external view returns (bool);

    // ── Views ──────────────────────────────────────────────────────────

    /// @notice Retrieve the full configuration and state of a project.
    /// @param projectId Unique identifier for the project.
    /// @return The Project struct.
    function getProject(bytes32 projectId) external view returns (Project memory);

    /// @notice Retrieve a contribution claim's details.
    /// @param claimId Unique identifier for the claim.
    /// @return The Claim struct.
    function getClaim(uint256 claimId) external view returns (Claim memory);

    /// @notice Retrieve a validation claim's details.
    /// @param claimId Unique identifier for the validation claim.
    /// @return The ValidationClaim struct.
    function getValidationClaim(uint256 claimId) external view returns (ValidationClaim memory);

    /// @notice Retrieve the full state of a contribution at a given index.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @return The Contribution struct.
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory);

    /// @notice Retrieve a user's reputation for a given role.
    /// @dev Returns default reputation values if the user has no recorded history.
    /// @param user Address of the user.
    /// @param role Role identifier (skill hash).
    /// @return The Reputation struct.
    function getReputation(address user, bytes32 role) external view returns (Reputation memory);

    /// @notice Retrieve the amount of pending (unclaimed) rewards for a user and token.
    /// @param user Address of the user.
    /// @param token Address of the reward token.
    /// @return The pending reward amount.
    function getPendingRewards(address user, address token) external view returns (uint256);

    /// @notice Retrieve the current adapter fee rates.
    /// @return originationBps Origination fee in basis points.
    /// @return contributionBps Contribution fee in basis points.
    /// @return validationBps Validation fee in basis points.
    function getAdapterFees()
        external
        view
        returns (uint256 originationBps, uint256 contributionBps, uint256 validationBps);

    /// @notice Retrieve the origination adapter address for a project.
    /// @param projectId Unique identifier for the project.
    /// @return The adapter address (address(0) if none).
    function getOriginationAdapter(bytes32 projectId) external view returns (address);

    /// @notice Retrieve the contribution adapter address for a claim.
    /// @param claimId Unique identifier for the contribution claim.
    /// @return The adapter address (address(0) if none).
    function getContributionAdapter(uint256 claimId) external view returns (address);

    /// @notice Retrieve the validation adapter address for a specific validator commit.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce.
    /// @param validator Address of the validator.
    /// @return The adapter address (address(0) if none).
    function getValidationAdapter(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (address);

    /// @notice Retrieve the top of the return stack for a project (next slot to reclaim).
    /// @param projectId Unique identifier for the project.
    /// @return The current return stack top index.
    function getReturnStackTop(bytes32 projectId) external view returns (uint256);

    /// @notice Retrieve the current submission nonce for a contribution slot.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @return The current submission nonce.
    function getSubmissionNonce(bytes32 projectId, uint256 index) external view returns (uint256);

    /// @notice Retrieve the consensus report for a contribution at its current nonce.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @return The ConsensusReport struct.
    function getConsensusReport(bytes32 projectId, uint256 index) external view returns (ConsensusReport memory);

    /// @notice Check whether a validator was classified as an outlier for a contribution.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param validator Address of the validator.
    /// @return True if the validator was an outlier.
    function isValidatorOutlier(bytes32 projectId, uint256 index, address validator) external view returns (bool);

    /// @notice Check whether a validator has been settled for a specific consensus nonce.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @param nonce Consensus nonce.
    /// @param validator Address of the validator.
    /// @return True if the validator has been settled.
    function isValidatorSettled(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (bool);

    /// @notice Retrieve the address of the SapienVault contract.
    /// @return The vault address.
    function vault() external view returns (address);

    /// @notice Retrieve the protocol treasury address.
    /// @return The treasury address.
    function treasury() external view returns (address);

    /// @notice Retrieve the remaining escrow balance for a project and token.
    /// @param projectId Unique identifier for the project.
    /// @param token Address of the reward token.
    /// @return The escrowed amount.
    function getProjectEscrow(bytes32 projectId, address token) external view returns (uint256);

    /// @notice Retrieve the dispute record for a contribution at its current nonce.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @return The Dispute struct.
    function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory);

    /// @notice Retrieve the originator report for a project.
    /// @param projectId Unique identifier for the project.
    /// @return The OriginatorReport struct.
    function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory);

    /// @notice Retrieve the amount of originator stake locked for a project.
    /// @param projectId Unique identifier for the project.
    /// @return The locked stake amount.
    function getOriginatorLockedStake(bytes32 projectId) external view returns (uint256);

    /// @notice Retrieve the current dispute-related configuration parameters.
    /// @return disputeBondBps_ Dispute bond in basis points of the contribution reward rate.
    /// @return originatorStakeReq_ Per-slot originator stake requirement.
    /// @return originatorReportBondBps_ Originator report bond in basis points of total project rewards.
    function getDisputeConfig()
        external
        view
        returns (uint256 disputeBondBps_, uint256 originatorStakeReq_, uint256 originatorReportBondBps_);

    /// @notice Retrieve the number of validator reveals for a contribution at its current nonce.
    /// @param projectId Project the contribution belongs to.
    /// @param index Contribution slot index.
    /// @return The reveal count.
    function getRevealCount(bytes32 projectId, uint256 index) external view returns (uint256);

    // ── Configurable Deadline Getters ───────────────────────────────────

    /// @notice Duration contributors have to submit work after claiming slots (in seconds).
    /// @return The current claim deadline duration.
    function claimDeadline() external view returns (uint256);

    /// @notice Duration of the challenge period after consensus is computed (in seconds).
    /// @return The current challenge period duration.
    function challengePeriod() external view returns (uint256);

    /// @notice Duration validators have to commit scores after a contribution is submitted (in seconds).
    /// @return The current commit deadline duration.
    function commitDeadline() external view returns (uint256);

    /// @notice Duration validators have to reveal scores after the commit deadline (in seconds).
    /// @return The current reveal deadline duration.
    function revealDeadline() external view returns (uint256);

    /// @notice Additional delay after the challenge period before force-settle is allowed (in seconds).
    /// @return The current force-settle delay duration.
    function forceSettleDelay() external view returns (uint256);

    /// @notice Current reputation decay rate in basis points per day.
    /// @return The decay rate in basis points.
    function decayRateBps() external view returns (uint256);
}
