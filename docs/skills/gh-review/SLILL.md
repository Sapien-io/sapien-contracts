---
name: gh-pr-security-review
description: Review GitHub pull requests for security vulnerabilities, code quality, and correctness in Solidity smart contracts. Use when the user asks to review a PR, review a GitHub pull request, check PR security, audit a diff, or provides a GitHub PR URL. Also use when the user asks to review code changes, staged changes, or branch diffs for security issues.
---

# GitHub PR Security Review

## Workflow

### Step 1: Gather PR Context

Fetch PR metadata and diff using `gh`:

```bash
# Get PR details
gh pr view <PR_NUMBER_OR_URL> --json title,body,baseRefName,headRefName,files,additions,deletions,changedFiles

# Get the full diff
gh pr diff <PR_NUMBER_OR_URL>

# Get existing review comments
gh api repos/{owner}/{repo}/pulls/{number}/comments

# Get CI check status
gh pr checks <PR_NUMBER_OR_URL>
```

If a PR URL is provided, extract the number. If no PR is specified, check for the current branch's PR:

```bash
gh pr view --json number,title,baseRefName 2>/dev/null
```

### Step 2: Scope the Review

1. List all changed files from the diff
2. Classify each file:
   - `src/**/*.sol` — **security-critical** (full review)
   - `test/**/*.sol` — **test quality** (coverage, assertions, edge cases)
   - `script/**/*.sol` — **deployment safety** (parameters, access control)
   - Config/docs — **informational** (quick scan)
3. For each security-critical file, read the full file (not just the diff) to understand surrounding context

### Step 3: Security Analysis

For every changed `.sol` file in `src/`, analyze the diff with full file context:

#### 3a. State & Storage

- New/modified storage variables: check ordering, packing, upgrade compatibility
- State transitions: verify all paths leave state consistent
- Mapping/array changes: check for unbounded growth, missing cleanup

#### 3b. Access Control

- New external/public functions: verify modifiers and authorization
- Modified access checks: ensure no privilege escalation
- Removed checks: flag as HIGH unless clearly intentional

#### 3c. Value Flows

- Token transfers: check for reentrancy, return value handling, fee-on-transfer
- ETH handling: check for stuck ETH, failed sends, msg.value validation
- Arithmetic: check rounding direction, precision loss, overflow in unchecked blocks
- Escrow/vault changes: verify accounting invariants

#### 3d. External Interactions

- New external calls: identify trust assumptions
- Changed call ordering: check for reentrancy introduction
- Oracle usage: check staleness, manipulation vectors

#### 3e. Commit-Reveal / Timing

- Deadline changes: verify no bypass paths
- Block.timestamp usage: check manipulation tolerance
- Sequencing: verify commit-before-reveal enforcement

#### 3f. Cross-Function Impact

- Trace how changed functions are called by other unchanged functions
- Check if modified return values break callers
- Verify event emissions match state changes

### Step 4: Test Coverage Assessment

For changed `src/` functions, verify:

- Corresponding test changes exist
- Happy path covered
- Revert conditions tested
- Edge cases (zero, max, boundary values)
- If missing: flag as finding

### Step 5: Generate Review

Output findings using this format:

#### Finding Format

```
### [SEVERITY] Title

**File:** `path/to/file.sol:L123-L145`
**Type:** security | correctness | gas | quality

**Description:** What the issue is and why it matters.

**Impact:** What can go wrong and for whom.

**Suggestion:**
<code fix>
```

#### Severity Levels

| Severity | Criteria |
|----------|----------|
| CRITICAL | Direct fund loss, contract takeover, broken invariant |
| HIGH | Conditional fund loss, privilege escalation, DoS of critical path |
| MEDIUM | Limited impact, griefing, state inconsistency under edge conditions |
| LOW | Gas inefficiency, style, missing events, minor improvements |
| INFO | Suggestions, questions for the author, documentation |

### Step 6: Post Review (if requested)

Post findings as PR review comments using `gh`:

```bash
# Post a general review comment
gh pr review <NUMBER> --comment --body "review body here"

# Post inline comments on specific lines
gh api repos/{owner}/{repo}/pulls/{number}/reviews --method POST \
  -f body="Security Review Summary" \
  -f event="COMMENT" \
  -f comments[][path]="src/File.sol" \
  -f comments[][line]=123 \
  -f comments[][body]="[HIGH] Finding description"
```

Only post to GitHub when the user explicitly asks. Default to local output.

## Anti-Patterns

| Trap | Correction |
|------|------------|
| Reviewing only the diff lines | Read full file context around changes |
| "OpenZeppelin handles it" | Verify correct usage, check version, check overrides |
| Ignoring test files | Missing tests for new code paths = finding |
| Assuming benign intent | Model adversarial actors at every trust boundary |
| Reviewing line-by-line only | Trace cross-function and cross-contract impact |

## Checklist Before Completing Review

- [ ] All `src/` changes analyzed with full file context
- [ ] Storage layout impact assessed (if upgradeable)
- [ ] Access control changes verified
- [ ] Arithmetic and value flow checked
- [ ] External call safety verified
- [ ] Test coverage gaps identified
- [ ] Findings documented with severity and suggestions
- [ ] Cross-contract impact of changes considered

## Additional References

For detailed Solidity vulnerability checklists, see [solidity-checklist.md](solidity-checklist.md).

