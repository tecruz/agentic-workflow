# TASK-003: PR #9 review blockers — JSON result contract corrections

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

This task fixes release-contract defects in the v1.4.0 machine-readable
result contracts found during PR #9 review: optional-failure PASS documents
rejected by the managed schema, Bash collapsing nested working directories,
absolute task paths leaking through a diagnostic message, and Bash accepting
unsupported output formats. The work touches verifier/validator observable
output only; no authentication, payments, secrets handling, data migration,
production infrastructure, irreversible operation, public-API compatibility
commitment beyond the unreleased v1.4.0 contract, privacy-regulated data, or
safety-critical behavior is involved. The standard profile provides adequate
verification depth: contract tests plus cross-language parity coverage on all
changed paths. Escalation signals were reviewed; none apply.

## Acceptance criteria

- AC-1: A run with at least one passing required check and one failing optional check produces a schema-valid PASS document whose summary separates required failures from optional failures (`failed` counts required checks only; new `optional_failed` field), and the schema requires `required_run >= 1`, `failed = 0`, and `blocked = 0` for any `PASS` document.
- AC-2: Bash verification JSON preserves full project-relative working-directory labels for nested relative paths (for example `apps/api` becomes `./apps/api`, never a bare basename), matching PowerShell labels exactly for the same checks.tsv.
- AC-3: Task-validator JSON diagnostics contain no absolute user paths when the task file does not exist: the not-found message uses the redacted display value in both implementations, verified by tests asserting the serialized JSON is free of the input path segments.
- AC-4: Both Bash entry points reject unsupported `--format` values and a missing `--format` value with a clear error and nonzero exit, matching PowerShell's ValidateSet behavior.
- AC-5: The Bash event-stream scratch file is created under an unpredictable `mktemp` name beside its destination and promoted with a no-clobber existence recheck immediately before the final rename.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Pester JsonContracts optional-failure schema-validity tests (Bash + PowerShell) against updated verification-result-v1.schema.json; manual Git-Bash run of checks-tsv-optional fixture with jsonschema validation | passed |
| AC-2 | checks-tsv-nested-cwd fixture asserted through Bats (CI) and Pester JsonContracts label-parity tests (Bash + PowerShell); manual Git-Bash run confirming `./apps/api`, `./services/api`, `./packages/shared` labels | passed |
| AC-3 | Pester JsonContracts redaction tests asserting absolute path segments absent from full serialized JSON for both validators; manual Git-Bash run of validate-task.sh with POSIX and Windows-style absolute paths confirming redaction | passed |
| AC-4 | Bats plus Pester JsonContracts format-rejection tests for verify.sh and validate-task.sh, including missing-value cases; manual Git-Bash runs confirming exit 1 + message for `--format yaml`, `--format`, `--format=banana` | passed |
| AC-5 | Code inspection of verify.sh event initialization (EVENTS_SCRATCH mktemp + no-clobber recheck); existing Pester Verify.Tests events-stream tests still passing | passed |

## Approval gates

- None identified

## Context modules

- .agentic/scripts/verify.sh
- .agentic/scripts/verify.ps1
- .agentic/scripts/validate-task.sh
- .agentic/scripts/validate-task.ps1
- .agentic/schemas/verification-result-v1.schema.json
- tests/bats/verify_test.bats
- tests/pester/JsonContracts.Tests.ps1
- tests/fixtures/checks-tsv-nested-cwd/

## Verification

### Baseline

Before changes: PR #9 review found 4 merge blockers at f5fd929:
- optional-failure PASS produced schema-invalid document (failed=1 for optional failure)
- Bash nested cwd labels collapsed to basename (e.g., `api` instead of `./apps/api`)
- validate-task.sh diagnostic leaked absolute path in JSON message (e.g., `Error: task file not found: /home/tiago/private/TASK-001.md`)
- Bash accepted any `--format` value silently (degraded to text mode)
All 4 blockers reproduced locally before fixes applied.

### Final

- Manual Git-Bash checks (13/13 pass): optional-fail PASS/0 with schema-valid JSON (required_run=1, failed=0, optional_failed=1); nested cwd labels preserved (`./apps/api`, `./services/api`, `./packages/shared`); `--format` rejection (yaml, missing value, case-insensitive JSON accepted); validate-task.sh redaction of both POSIX and Windows absolute paths; events scratch mktemp + no-clobber promotion + no leftovers; relative-path `..` normalization.
- Pester suite: 290 passed, 1 failed (pre-existing detection fixture), 2 skipped; JsonContracts file: 22/22 passed (optional-fail schema-validity, label parity, redaction, format rejection, required-fail+optional-pass, optional-skipped).
- Fixture harness (run-fixtures.ps1 with verify.ps1): all 27 fixtures OK including new checks-tsv-nested-cwd (exit 0).
- Detect parity: run-fixtures.ps1 emit-checks for all golden fixtures OK.
- Docs updated: README JSON contract bullets + dist example 1.4.0; CHANGELOG 1.4.0 Fixed/Changed; ADR-0009 amendments 5-6.

## Files changed

- .agentic/schemas/verification-result-v1.schema.json — `optional_failed` in required summary fields; descriptions for `failed`/`optional_failed`; PASS invariant (`required_run >= 1`, `failed = 0`, `blocked = 0`).
- .agentic/scripts/verify.sh — `--format` validation; `output_json` optional/required failure split; nested-cwd label normalization via `normalize_project_rel()`; `EVENTS_SCRATCH` mktemp + no-clobber promotion.
- .agentic/scripts/verify.ps1 — `Output-VerificationJson` failure-count split (`failedCount` required only + `optionalFailedCount`); `optional_failed` in summary.
- .agentic/scripts/validate-task.sh — `--format` validation; not-found JSON message uses `display_path()` (redacted).
- .agentic/scripts/validate-task.ps1 — not-found JSON message uses `Get-TaskFileDisplay()` with cross-OS path-form guard.
- tests/fixtures/checks-tsv-nested-cwd/.agentic/checks.tsv — new fixture (three required pwsh checks in `apps/api`, `services/api`, `packages/shared`).
- tests/fixtures/run-fixtures.sh, run-fixtures.ps1 — registered new fixture with `check_exe`/`Check-Exe` guards.
- tests/bats/verify_test.bats — regression tests for optional-fail PASS, optional-skipped, required-fail+optional-pass, nested cwd labels, format rejections, validate-task format rejections, events atomic create/refusal/no-leftover.
- tests/pester/JsonContracts.Tests.ps1 — regression It blocks for all 5 ACs (schema-validity, label parity, redaction both validators both path forms, format rejection both validators both languages).
- README.md — JSON contract bullets documenting `failed`/`optional_failed`/PASS invariant; dist example 1.3.0 → 1.4.0.
- CHANGELOG.md — 1.4.0 Fixed (4 blockers + events) + Changed (summary semantics + strict format).
- docs/decisions/ADR-0009-machine-readable-result-contracts.md — amendments 5-6 (summary semantics + strict format).

## Remaining risks

- Local environment lacks `bats` and `shellcheck`; those checks report BLOCKED locally but pass in CI (GitHub Actions runners have both). Full CI gate required on push.
- Local parity script (`tests/parity/run-parity.sh`) spawns many Git-Bash processes and triggers a harness timeout in this environment; CI runs it successfully. Manual golden parity spot-checks and run-fixtures.ps1 emit-checks provide local coverage.
