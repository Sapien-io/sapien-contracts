// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Constants {
    // ════════════════════════════════════════════════════════════════════
    // Constants
    // ════════════════════════════════════════════════════════════════════

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant MAX_CLAIM_QUANTITY = 20;
    uint256 public constant MAX_NUMBER_OF_VALIDATIONS = 10;

    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1000; // 10%
    uint256 public constant MAX_ADAPTER_FEE_BPS = 500; // 5%
    uint256 public constant MAX_VALIDATOR_REWARD_BPS = 2500; // 25%
    uint256 public constant BPS = 10_000;

    uint256 public constant DEFAULT_CHALLENGE_PERIOD = 1 days;
    uint256 public constant DEFAULT_CLAIM_DEADLINE = 1 days;
    uint256 public constant DEFAULT_COMMIT_DEADLINE = 1 days;
    uint256 public constant DEFAULT_REVEAL_DEADLINE = 1 days;
    uint256 public constant DEFAULT_FORCE_SETTLE_DELAY = 3 days;

    uint256 public constant MAX_CHALLENGE_PERIOD = 30 days;
    uint256 public constant MAX_CLAIM_DEADLINE = 30 days;
    uint256 public constant MAX_COMMIT_DEADLINE = 30 days;
    uint256 public constant MAX_REVEAL_DEADLINE = 30 days;
    uint256 public constant MAX_FORCE_SETTLE_DELAY = 90 days;

    uint256 public constant MIN_CHALLENGE_PERIOD = 1 hours;
    uint256 public constant MIN_CLAIM_DEADLINE = 1 hours;
    uint256 public constant MIN_COMMIT_DEADLINE = 1 hours;
    uint256 public constant MIN_REVEAL_DEADLINE = 1 hours;
    uint256 public constant MIN_FORCE_SETTLE_DELAY = 1 days;

    uint256 public constant VALIDATION_CLAIM_DEADLINE = 1 hours;

    // Dispute constants
    uint256 public constant DISPUTE_RESOLUTION_DEADLINE = 7 days;
    uint256 public constant MAX_DISPUTE_BOND_BPS = 5000; // 50% of rewardRate
    uint256 public constant DISPUTE_CHALLENGER_REWARD_BPS = 2000; // 20% of saved/slashed amount
    uint256 public constant MAX_ORIGINATOR_REPORT_BOND_BPS = 1000; // 10% of project totalRewards
    uint256 public constant MAX_DECAY_RATE_BPS = 500; // 5% max reputation decay per day (L-03)
    uint256 public constant PROJECT_COMPLETION_DELAY = 30 days; // grace period before escrow refund (M-03)
    // FORCE_SETTLE_DELAY moved to DEFAULT_FORCE_SETTLE_DELAY above

    // Reputation constants
    uint256 public constant DEFAULT_REPUTATION = 5000;
    uint256 public constant MAX_REPUTATION = 10_000;
    uint256 public constant MIN_REPUTATION = 500;
    uint256 public constant SUCCESS_INCREASE = 10;
    uint256 public constant REJECTION_DECREASE = 50;
    uint256 public constant MAX_DAILY_GAIN = 100;

    bytes32 public constant ORIGINATOR_ROLE_KEY = keccak256("ORIGINATOR");
}
