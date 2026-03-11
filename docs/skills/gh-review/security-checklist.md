# Solidity Security Checklist

Detailed vulnerability-class reference for PR reviews. Only loaded when deeper analysis is needed.

---

## Reentrancy

- [ ] External calls occur after all state updates (checks-effects-interactions)
- [ ] `nonReentrant` modifier on value-transferring functions
- [ ] Cross-function reentrancy: function A calls external, reenters function B sharing state
- [ ] Read-only reentrancy: view functions return stale state during callback
- [ ] ERC-777 / ERC-1155 callback hooks as reentry vectors

## Access Control

- [ ] All external/public functions have appropriate modifiers
- [ ] Role-based checks cannot be bypassed via delegatecall
- [ ] `onlyOwner` / admin functions scoped to minimum privilege
- [ ] Initializer functions protected (`initializer` modifier, `_disableInitializers`)
- [ ] No unprotected `selfdestruct` or `delegatecall`
- [ ] `msg.sender` vs `tx.origin` — never use `tx.origin` for auth

## Arithmetic & Precision

- [ ] `unchecked` blocks audited for overflow/underflow
- [ ] Division before multiplication avoided (precision loss)
- [ ] Rounding direction favors protocol (round down on withdraw, up on deposit)
- [ ] Casting between sizes checked (uint256 -> uint128 truncation)
- [ ] Percentage/basis-point math uses correct denominator (10_000 for bps)

## Input Validation

- [ ] Zero address checks on critical parameters
- [ ] Zero amount checks on transfers and stakes
- [ ] Array length bounds to prevent gas griefing
- [ ] Calldata length validation for low-level calls
- [ ] Enum values validated (Solidity doesn't auto-check in all contexts)

## Token Interactions

- [ ] ERC-20 `transfer`/`transferFrom` return values checked (or use SafeERC20)
- [ ] Fee-on-transfer tokens handled (compare balances before/after)
- [ ] Rebasing tokens: stored balances may diverge from actual
- [ ] ERC-20 approval race condition mitigated (approve 0 first, or use increase/decrease)
- [ ] Token decimals not hardcoded — read from contract

## Flash Loan Sensitivity

- [ ] Governance votes not manipulable via flash-borrowed tokens
- [ ] Share price / exchange rate not manipulable in single tx
- [ ] First-depositor attack mitigated (dead shares or minimum deposit)
- [ ] Vault donation attack mitigated (inflation attack)

## Upgradeability

- [ ] No new variables inserted before existing ones
- [ ] Initializer version bumped for reinitializations
- [ ] Implementation contract has `_disableInitializers` in constructor
- [ ] Upgrade authorization checked (UUPS `_authorizeUpgrade`)

## Gas & DoS

- [ ] No unbounded loops over dynamic arrays
- [ ] Pull-over-push for payments (pending rewards pattern)
- [ ] Failed external calls don't block critical functions
- [ ] Block gas limit considered for batch operations
- [ ] Griefing: can a low-cost action impose high cost on others?

## State Management

- [ ] Storage vs memory vs calldata used correctly
- [ ] Struct packing optimized for storage slots
- [ ] Mappings cleaned up when entries removed
- [ ] Events emitted for all state-changing operations
- [ ] State machine transitions are monotonic (no backward moves)

## Commit-Reveal Schemes

- [ ] Commit hash includes sender address to prevent front-running
- [ ] Reveal deadline enforced — no indefinite commit phase
- [ ] Salt entropy sufficient (not derived from predictable values)
- [ ] Revealed values validated against commit hash before use
- [ ] Unrevealed commits handled (timeout + slash or refund)

## Cross-Contract

- [ ] Return values from external calls checked and validated
- [ ] Interface assumptions match actual implementation
- [ ] Callback functions validate caller identity
- [ ] Shared storage between proxy and implementation aligned
- [ ] Library delegatecall preserves expected context

