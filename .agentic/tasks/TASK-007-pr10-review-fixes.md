# TASK-007: PR #10 review fixes — sentinel parity, JSON diagnostic contract, tooling classification

## Status

Status: done
Updated: 2026-08-27

## Risk profile

Profile: standard

## Profile rationale

The change corrects the context-module validator added in PR #10: it aligns
the PowerShell sentinel grammar with the Bash validator's anchored grammar,
fixes a stale Pester assertion that contradicted the validators' documented
JSON redaction, and classifies missing perl as BLOCKED instead of INVALID.
No authentication, payments, secrets handling, data migration, production
infrastructure, irreversible operation, public-API compatibility commitment,
privacy-regulated data, or safety-critical behavior is implemented; the
security-review module's load triggers (authentication/authorization/secrets/
cryptography changes) do not apply to validator grammar and test corrections.
Escalation signals were reviewed; none apply. The standard profile with the
existing CI gates provides adequate verification depth.

## Acceptance criteria

- AC-1: `validate-context.ps1` enforces the identical anchored sentinel grammar as `validate-context.sh`: `None selected` must be followed by end-of-line or whitespace + one separator (`—`/`–`/`-`) + whitespace + a substantive rationale; the malformed sentinels `None selected-but-not-really` and `None selected because ...` classify INVALID (1) in both languages with byte-identical first-line messages.
- AC-2: A double-space sentinel separator (`None selected  —  rationale`) remains VALID (0) in both languages, matching the documented `\s+` grammar.
- AC-3: The full 42-fixture context corpus classifies without regression (13 VALID / 27 INVALID / 2 BLOCKED); the shared-fixture cross-language parity set stays language-independent.
- AC-4: JSON diagnostics never leak task-provided identifiers; the Pester suite asserts the redacted (null/empty) identifier instead of the task value.
- AC-5: Missing perl classifies as BLOCKED (2) with stable code `TOOLING_UNAVAILABLE`, which is part of the `context-selection-v1.schema.json` diagnostics enum and maps to a neutral JSON message.
- AC-6: Existing gates stay green: `evals/run-evals.ps1` 8/8, composite handoff gate passes TASK-002 and TASK-006, and this task file passes the composite handoff gate.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats/Pester golden fixtures `context-sentinel-hyphen-nospace.md` / `context-sentinel-because.md` expect INVALID(1); PowerShell run measures exit 1 with the shared message; Bash code path reviewed line-by-line against the same message strings | passed |
| AC-2 | New fixture `context-sentinel-double-space.md`; PowerShell run measures exit 0; Bash path equivalent by code review | passed |
| AC-3 | Full 42-fixture PowerShell run: 13/0/27/1/2 breakdown, no fixture flipped versus the pre-change corpus except the intended hyphen-nospace correction | passed |
| AC-4 | `ValidateContext.Tests.ps1` JSON-mode assertion changed to `BeNullOrEmpty`; measured `identifier` empty in emitted JSON | passed |
| AC-5 | `validate-context.sh` perl-missing path now calls `fail_blocked`; schema enum extended with `TOOLING_UNAVAILABLE`; BLOCKED JSON message arm added | passed |
| AC-6 | `run-evals.ps1` exit 0 (8/8); `validate-handoff.ps1` exit 0 on TASK-002 and TASK-006; `validate-handoff.ps1` exit 0 on this file | passed |

## Approval gates

- None identified

## Context modules

- None selected — framework-internal validator and test corrections with no specialist trigger

## Files changed

- .agentic/scripts/validate-context.ps1 — sentinel grammar mirrors the Bash anchored grammar (whitespace + separator + whitespace + rationale); malformed sentinels INVALID.
- .agentic/scripts/validate-context.sh — sentinel suffix parsed with the anchored grammar via byte-exact parameter expansion (replaces the single-space case arms); missing perl reclassified BLOCKED (`TOOLING_UNAVAILABLE`) with a neutral JSON message arm.
- .agentic/schemas/context-selection-v1.schema.json — diagnostics enum gains `TOOLING_UNAVAILABLE`.
- tests/pester/ValidateContext.Tests.ps1 — JSON identifier assertion now expects redaction; golden tests for the two new sentinel fixtures.
- tests/bats/validate_context_test.bats — golden tests for the two new sentinel fixtures.
- tests/fixtures/context-tasks/context-sentinel-because.md, context-sentinel-double-space.md — new shared fixtures (new).
- .agentic/STATUS.md — TASK-007 entry (this task).

## Verification

### Baseline

PR head `cfd1649`: `validate-context.ps1` classified `context-sentinel-hyphen-nospace.md` (`None selected-but-not-really`) as VALID (0) while both the Bats golden test and the Pester golden test require INVALID (1); `ValidateContext.Tests.ps1` asserted `identifier -eq 'mystery-module'` against an implementation that deliberately redacts identifiers to null/empty; the Bash perl-missing path exited INVALID (1) with code `TOOLING_UNAVAILABLE`, which is absent from the result schema's diagnostics enum; full Bats/Pester suites had not run at HEAD (last CI (Full) run predates the final commits).

### Final

- PowerShell parse check clean for `.agentic/scripts/validate-context.ps1` and `ValidateContext.Tests.ps1`.
- 42-fixture corpus via `validate-context.ps1`: 13 VALID / 27 INVALID / 2 BLOCKED; no regression versus baseline except the intended hyphen-nospace correction; `context-sentinel-because.md` → INVALID(1), `context-sentinel-double-space.md` → VALID(0).
- Byte-identical first-line messages confirmed between both validators for all four sentinel diagnostics.
- JSON mode: sentinel failures emit `MODULE_SELECTION_UNRESOLVED` with redacted identifier; schema enum contains `TOOLING_UNAVAILABLE`.
- `pwsh -NoProfile -File evals/run-evals.ps1` → exit 0 (8/8, negative control fails exactly `FORBIDDEN_ACTIONS_ABSENT`).
- `validate-handoff.ps1` exit 0 on TASK-002, TASK-006, and this task file.
- Bats and Pester suites not runnable in the review sandbox (Pester registry access and bash signal-pipe creation are blocked); the Bash validator changes were verified by line-by-line review and message-parity checks, and the next CI (Full) run on the new HEAD exercises them.

## Remaining risks

- The Bash validator changes are not executed in this sandbox; CI (Full) must run green on the new HEAD (bats + full Pester incl. the parity and golden tests).
- Accepted follow-ups from the PR review, deliberately not fixed here: JSON `identifier`/`section` shape differs across languages (`""` vs `null`, both schema-valid); `FORBIDDEN_ACTIONS_ABSENT` is a substring scan and several eval checks are vacuously satisfied by the shipped scenarios; the `loaded`-token diagnostics are unreachable dead code. (Fixture/test-count drift in TASK-006 and the PR body was corrected in TASK-008.)
