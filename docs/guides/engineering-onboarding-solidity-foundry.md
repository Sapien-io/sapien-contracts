# Smart Contract Engineering Onboarding (Solidity + Foundry)

> Audience: new engineering teammates contributing to this repository.
> Format: milestone-based, self-paced checklist.
> Goal: move from zero Solidity/Foundry experience to shipping safe, tested protocol changes.

## Program Outcomes

By the end of this onboarding, the engineer should be able to:

1. Explain the Sapien protocol lifecycle and core contract architecture.
2. Navigate this repository efficiently (`src`, `test`, `script`, `docs`).
3. Build, test, lint, and run local deployments with Foundry tooling.
4. Write and debug unit, fuzz, and invariant tests for protocol logic.
5. Ship a scoped production change with a strong test plan and risk analysis.

## Setup Checklist

### Environment Setup

- [ ] Install or upgrade Foundry.
- [ ] Initialize submodules and dependencies.
- [ ] Verify local toolchain (`forge`, `anvil`, `cast`).

```bash
# Install/upgrade Foundry
foundryup

# Ensure dependencies are present
git submodule update --init --recursive

# Verify toolchain
forge --version
anvil --version
cast --version
```

### Repository Sanity Checks

- [ ] Compile successfully.
- [ ] Run the full test suite successfully.
- [ ] Run lint successfully.

```bash
# Compile
forge build

# Run tests
forge test

# Lint contracts
make lint
```

### Optional Local Deployment Flow

- [ ] Start local Anvil chain in one terminal.
- [ ] Deploy contracts to local Anvil in a second terminal.

```bash
# Terminal 1: local chain
make anvil
```

```bash
# Terminal 2: deploy contracts to local Anvil
make deploy-anvil
```

## Repository Learning Map

| Area | Start Here | Why It Matters |
|---|---|---|
| Core contracts | `src/SapienCore.sol`, `src/SapienVault.sol` | Main protocol entry points and staking model |
| Shared state/types | `src/Types.sol`, `src/Constants.sol` | Storage layout, enums, protocol limits |
| Core business logic | `src/libraries/*.sol` | Lifecycle implementation by concern |
| Interface surface | `src/interfaces/*.sol` | Contract API shape for integrations |
| Unit + lifecycle tests | `test/` | Behavioral source of truth and edge cases |
| Security regressions | `test/findings/` | Historical vulnerabilities and fixes |
| Upgrade safety | `script/upgrade/README.md`, `test/upgrade/Upgrade.t.sol` | UUPS upgrade workflow and storage safety |
| Architecture docs | `docs/architecture/overview.md`, `docs/architecture/lifecycle.md` | High-level mental model before code deep dives |
| Frontend lifecycle reference | `docs/guides/protocol-lifecycle.md` | End-to-end state machine and timing windows |

## Training Checklist (Milestone-Based)

## Milestone 1: Solidity and Protocol Fundamentals

- [ ] Read:
  - [ ] `docs/architecture/overview.md`
  - [ ] `docs/architecture/lifecycle.md`
  - [ ] `docs/guides/protocol-lifecycle.md`
- [ ] Walk core files:
  - [ ] `src/Types.sol`
  - [ ] `src/Constants.sol`
  - [ ] `src/SapienCore.sol`
  - [ ] `src/SapienVault.sol`
- [ ] Deep dive libraries:
  - [ ] `src/libraries/OriginationLib.sol`
  - [ ] `src/libraries/ContributionLib.sol`
  - [ ] `src/libraries/ValidationLib.sol`
  - [ ] `src/libraries/ConsensusLib.sol`
  - [ ] `src/libraries/FinalizationLib.sol`
- [ ] Trace one full happy path from function call to state transitions.
- [ ] Trace one rejected or disputed path from function call to state transitions.
- [ ] Build a personal glossary of protocol terms and state transitions.

### Milestone 1 Completion Criteria

- [ ] Can explain the purpose of each library in plain language.
- [ ] Can describe where stake gets locked, released, and slashed.
- [ ] Can identify where consensus status changes are persisted.

## Milestone 2: Foundry and Testing Skills

- [ ] Run and understand these test suites:

```bash
# Core unit tests
forge test --match-path test/SapienCore.t.sol -vv
forge test --match-path test/SapienVault.t.sol -vv

# Library fuzz tests
forge test --match-path test/libraries/ConsensusLibFuzz.t.sol -vv
forge test --match-path test/libraries/ValidationLibFuzz.t.sol -vv

# Lifecycle tests
forge test --match-path test/lifecycle/Lifecycle.t.sol -vv
forge test --match-path test/lifecycle/SkillReputation.t.sol -vv

# Invariants
forge test --match-path test/invariant/SapienCoreInvariant.t.sol -vv
forge test --match-path test/invariant/SapienVaultInvariant.t.sol -vv
```

- [ ] Add one focused unit or fuzz test for a guardrail not already directly asserted.
- [ ] Pair-review one existing security regression test in `test/findings/` and explain what bug it prevents.

### Milestone 2 Completion Criteria

- [ ] Can write and run targeted tests quickly.
- [ ] Can use verbose traces to diagnose failures.
- [ ] Can justify why a test catches a meaningful failure mode.

## Milestone 3: Security, Upgrades, and Operations

- [ ] Read `script/upgrade/README.md`.
- [ ] Run `forge test --match-path test/upgrade/Upgrade.t.sol -vv`.
- [ ] Review at least 3 findings in `test/findings/` and summarize root cause plus patch strategy.
- [ ] Run `make coverage` and identify one uncovered behavior worth testing.

### Milestone 3 Completion Criteria

- [ ] Can explain upgrade risk categories (storage layout, initializer discipline, role safety).
- [ ] Can map historical findings to current safeguards.
- [ ] Can propose one practical risk reduction in tests or docs.

## Milestone 4: First Scoped Contribution

- [ ] Select a small bug fix, guardrail, or test-hardening improvement.
- [ ] Keep scope tight (one concern per PR).
- [ ] Implement change with minimal surface area.
- [ ] Add or extend tests that fail before and pass after.
- [ ] Run:
  - [ ] `forge build`
  - [ ] `forge test`
  - [ ] `make lint`
- [ ] Include a short PR write-up:
  - [ ] Problem statement
  - [ ] Why the fix is correct
  - [ ] Risk assessment
  - [ ] Test evidence

### Milestone 4 Completion Criteria

- [ ] First merged PR with passing tests and reviewer sign-off.
- [ ] Demonstrates independent debugging and clear technical communication.

## Working Rhythm Checklist

- [ ] Sync latest branch state before coding.
- [ ] Re-run targeted tests when the implementation scope changes.
- [ ] Prefer test-first for behavioral contract changes.
- [ ] Keep commits and diffs focused and reviewable.
- [ ] Run full build, test, and lint before opening a PR.
- [ ] Self-review diff for security and edge cases.

## Mentor Checkpoint Checklist

- [ ] Schedule mentor sessions.
- [ ] Use mentor sessions for architecture and protocol Q&A.
- [ ] Use mentor sessions for test review and debugging walkthroughs.
- [ ] At each milestone completion, review completion criteria and set the next milestone goal.

## External References

- Solidity docs: <https://docs.soliditylang.org/>
- Foundry book: <https://book.getfoundry.sh/>
- OpenZeppelin upgradeability docs: <https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable>

This program is designed to be practical: each milestone should end with concrete repo-specific output, not just reading.
