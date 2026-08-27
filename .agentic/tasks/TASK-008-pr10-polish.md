# TASK-008: PR #10 pre-merge polish — doc-count accuracy and evals harness hygiene

## Status

Status: done
Updated: 2026-08-27

## Risk profile

Profile: standard

## Profile rationale

The change is documentation accuracy (fixture/test/registration counts in
TASK-006 and the PR description) plus low-risk harness hygiene in the
framework's own evaluation tooling (fence parsing mirroring, a PowerShell
version guard, deterministic fixture generation). No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior is involved; no specialist module trigger applies.
The standard profile with the existing fast-CI gates (both eval runners, JSON
contracts) and a handoff-gate validation of this file provides adequate
verification depth.

## Acceptance criteria

- AC-1: TASK-006 and the PR description state accurate final counts: 42 shared fixtures, 57 Bats cases, 41 Pester cases, 11 managed-file registrations.
- AC-2: Both eval runners treat triple-tilde fences exactly like the production task validator (any line containing a triple-backtick or triple-tilde marker toggles fence state), so authoritative-section parsing mirrors production for both fence flavors.
- AC-3: `run-evals.ps1` declares `#Requires -Version 7.0` so unsupported hosts fail with a clear parse-time error instead of a confusing runtime error.
- AC-4: `generate-scenarios.ps1` emits `verification-result.json` with deterministic key order (`[ordered]`), so regeneration is byte-stable.
- AC-5: Existing gates stay green: `evals/run-evals.ps1` 8/8, the composite handoff gate passes this file, and the fast CI legs (which run both eval runners) pass on the new head.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Counts verified by enumeration (`Get-ChildItem` = 42 fixtures; `@test` lines = 57; Pester `It` blocks = 41; install.sh registrations added by the PR = 11) and written into TASK-006 and the PR description | passed |
| AC-2 | Both runners' fence detection changed to substring matching (triple backtick / triple tilde) mirroring `validate-task.sh:787-795`; `run-evals.ps1` still 8/8 with the PR fixtures | passed |
| AC-3 | `#Requires -Version 7.0` placed after the shebang; script parses under pwsh 7 | passed |
| AC-4 | `New-VerificationDoc` top-level hashtable changed to `[ordered]@{}`; ConvertTo-Json key order verified as insertion order | passed |
| AC-5 | `run-evals.ps1` exit 0 (8/8); `validate-handoff.ps1` exit 0 on this file; fast CI (Ubuntu bash + Windows pwsh incl. `evals-sh`/`evals-ps`) green on the pushed head | passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation and framework-internal harness hygiene with no specialist trigger

## Files changed

- .agentic/tasks/TASK-006-context-modules-and-evals.md — final counts corrected (42 shared fixtures, 57 Bats cases, 41 Pester cases, 11 managed-file registrations).
- evals/run-evals.sh — embedded python authoritative-section parser now treats any line containing a triple-backtick or triple-tilde marker as a fence toggle, mirroring `validate-task.sh`.
- evals/run-evals.ps1 — same fence-parity change plus `#Requires -Version 7.0` shebang guard.
- evals/generate-scenarios.ps1 — `New-VerificationDoc` uses `[ordered]@{}` for deterministic JSON key order.
- .agentic/tasks/TASK-007-pr10-review-fixes.md — remaining-risks list updated (doc drift moved to TASK-008).
- .agentic/STATUS.md — TASK-008 entry (this task).

## Verification

### Baseline

Before this task, TASK-006 and the PR description claimed "fourteen shared fixtures", "21 Bats cases", "19 Pester cases", and "nine managed-file registrations"; actuals were 40 (+2 TASK-007 regressions = 42) fixtures, 57 Bats cases, 41 Pester Its, and 11 registrations. The eval harness treated only triple-backtick fences while the production task validator also treats triple-tilde fences; `run-evals.ps1` had no version guard; `generate-scenarios.ps1` serialized a plain hashtable with unspecified key order.

### Final

- Counts re-verified by enumeration and corrected in TASK-006; PR description updated via `gh pr edit`.
- `run-evals.ps1` parse OK and exit 0 (8/8) after the fence and version-guard changes.
- `generate-scenarios.ps1` parse OK; `[ordered]` JSON key order verified directly.
- `validate-handoff.ps1` exit 0 on this task file (and on TASK-006/TASK-007 after their edits).
- Fast CI on the pushed head exercises `evals-sh` (Ubuntu bash) and `evals-ps` (Windows); Bats and the full Pester suite run in CI (Full).

## Remaining risks

- The `run-evals.sh` fence change is exercised by CI (`evals-sh` is a required check) but not executed in this sandbox; Bash 3.2/BSD-vs-GNU portability of the change is limited to string containment, which is shell-version-independent.
- Still accepted as follow-ups (recorded in TASK-007): JSON `""` vs `null` shape parity; eval-scenario coverage gaps (forbidden-path scenario, no-module enforcement, profile-floor non-equality cases); dead `loaded`-token diagnostics; CI lint coverage for `evals/run-evals.sh` (shellcheck/`bash -n` lists).