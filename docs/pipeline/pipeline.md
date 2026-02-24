**Architecture**: Sapien PoQ v0.5 -- SapienCore + SapienVault + 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib). See `docs/security/AUDIT_SCOPE.md`.

---

A0 -- Orchestrator Agent

Job: plan execution, route artifacts, enforce gates.
Inputs: repo path, commit range, config, threat model notes.
Outputs: run plan, final report bundle, CI status.

---

A1 -- Intent and Spec Extractor Agent

Job: what does the protocol claim to do?
Skill File: `intent-audit-review-skill.md`
Inputs: README, docs, comments, NatSpec, PR description.
Outputs:
	- intent.md (system summary + claims)
	- assumptions.json (oracle assumptions, admin assumptions, trust boundaries)
	- critical_flows.md (fund/claim/contribute/validate/finalize/dispute/etc.)

---

A2 -- Surface Mapper Agent

Job: map attack surface and trust surface.
Skill File: `trust-surface-review-skill.md`
Inputs: compiled AST, call graph, inheritance graph, deployments (if any).
Outputs:
	- surface.json: external/public functions, payable paths, external calls, DELEGATECALL sites
	- roles.json: roles, modifiers, access checks
	- assets.json: tracked assets, accounting variables, custody locations

---

A3 -- Static Security Auditor Agent

Job: identify known vulnerability classes with evidence.
Skill Files: `security-review-skill.md`, `security-pattern-review-skill.md`, `asymmetry-review-skill.md`, `edge-case-review-skill.md`
Inputs: Slither + custom detectors output, Surface Map.
Outputs:
	- findings_static.json with per-finding: CWE-style class, severity, evidence locations, exploit sketch

---

A4 -- Invariant Designer Agent

Job: translate protocol into invariants + properties to test.
Skill File: `invariant-review-skill.md`
Inputs: Intent + Surface + Assets Map.
Outputs:
	- invariants.md (human-readable)
	- properties.json (machine-readable properties per function/flow)
	- echidna_targets.json or foundry_invariant_targets.json

---

A5 -- Fuzz and Invariant Runner Agent (Tool Agent)

Job: execute Foundry fuzz/invariant tests (and Echidna if you use it).
Skill Files: `lifecycle-testing-skill.md`, `adversarial-testing-skill.md`
Inputs: properties/invariant targets, repo.
Outputs:
	- fuzz_results.json (repro seeds, failing calls, traces)
	- coverage.json
	- gas_snapshots.json (optional)

(This agent is mostly a wrapper around tooling; minimal "LLM reasoning.")

---

A6 -- Economic / MEV Adversary Agent

Job: "code is correct, economics are broken" analysis.
Skill File: `sandwich-review-skill.md`
Inputs: Critical flows, external calls, fee logic, rounding.
Outputs:
	- findings_econ.json (sandwichability, manipulation vectors, free options, griefing, rounding bias)
	- mev_scenarios.md with step-by-step attacker playbooks

---

A7 -- Upgradeability and Storage Safety Agent

Job: ensure upgrade paths won't brick / get hijacked.
Skill File: `upgrade-storage-review-skill.md`
Inputs: UUPS pattern, ERC-7201 storage layout, initializer patterns, admin checks.
Outputs:
	- findings_upgrade.json (storage collision risk, init issues, auth issues, upgrade hooks)
	- storage_layout.diff (if PR changes storage)

---

A8 -- Permissions and Trust Risk Agent

Job: answer "who can rug / pause / drain / change parameters?"
Skill File: `trust-surface-review-skill.md` (shared with A2)
Inputs: roles.json, Surface map, admin functions.
Outputs:
	- trust_report.md (capabilities by role, blast radius)
	- centralization_risks.json (severity + mitigations)

---

A9 -- Diff and Regression Agent

Job: what changed, and what new risks did it introduce?
Inputs: git diff, prior report baseline, current artifacts.
Outputs:
	- regression_findings.json (behavior changes, removed checks, new externals)
	- review_focus.md (hotspot list)

---

A10 -- Triage and Risk Scoring Agent

Job: deduplicate, prioritize, and assign.
Skill File: `risk-scoring-review-skill.md`
Inputs: all findings JSON + fuzz evidence + intent.
Outputs:
	- risk_matrix.json (severity x likelihood)
	- fix_plan.md (ordered fixes, owners, effort)
	- release_blockers.md (must-fix before deploy)

---

A11 -- Final Report Writer Agent

Job: produce a clean audit-style output.
Inputs: triage outputs + evidence.
Outputs:
	- REPORT.md (executive summary + technical findings)
	- REPORT.json (for dashboards)
	- REPRO.md (how to reproduce any failing tests / exploits)

---

A12 -- Gas Auditor Agent

Job: identify gas inefficiencies and optimization opportunities.
Skill File: `gas-review-skill.md`
Inputs: Contract code, compiler settings, gas snapshots.
Outputs:
	- gas_findings.json: location, current usage, optimized usage, savings estimate.

---

A13 -- Integration Auditor Agent

Job: check assumptions about external protocols (ERC20, ERC-4626).
Skill File: `integration-review-skill.md`
Inputs: external call sites, documentation of external protocols.
Outputs:
	- integration_risks.json: token behavior quirks, oracle edge cases, protocol incompatibilities.

---

Pipeline stages and gates

Stage 1: Intake + Scope

Run: A0 -> A1 -> A9
Gate: If scope unclear, still proceed but mark "assumptions incomplete."

Stage 2: Mapping + Static

Run: A2 -> A3 -> A8 -> A7 -> A12 -> A13
Gate: If Critical static findings exist (e.g., auth bypass, reentrancy on value path), mark FAIL and still run fuzz (to get evidence), but stop any "ship approval."

Stage 3: Properties + Fuzz

Run: A4 -> A5
Gate: Any invariant failure = FAIL (block release) until triaged.

Stage 4: Econ/MEV

Run: A6
Gate: If econ finding is Critical+High-likelihood (e.g., flash loan consensus manipulation), FAIL.

Stage 5: Consolidation

Run: A10 -> A11
Gate: Only PASS if no release blockers.

---

Artifact contracts (make agents composable)

Use a strict schema for findings so agents don't argue.

Finding JSON (example shape):

{
  "id": "SEC-REENT-001",
  "title": "Reentrancy on claimReward() allows double-withdraw",
  "severity": "CRITICAL",
  "likelihood": "HIGH",
  "impact": "Loss of funds",
  "component": "SapienCore (FinalizationLib)",
  "evidence": [
    {"file":"FinalizationLib.sol","lineStart":123,"lineEnd":180,"note":"External call before state update"},
    {"type":"trace","ref":"fuzz_results.json#case42"}
  ],
  "exploit_sketch": [
    "Attacker deposits into SapienVault",
    "Calls claimReward() via malicious receiver",
    "Reenters before balance decrement",
    "Withdraws twice"
  ],
  "recommended_fix": "Apply checks-effects-interactions; add nonReentrant; move state update before external call.",
  "status": "OPEN"
}

Severity rubric (simple, consistent)
	- CRITICAL: direct fund loss / permanent takeover / bricking.
	- HIGH: fund loss possible with conditions, serious governance abuse, major invariant breaks.
	- MEDIUM: limited loss/griefing, DoS, MEV extraction with constraints.
	- LOW: footguns, minor edge cases, best practices.
	- INFO: style, clarity, maintainability.
