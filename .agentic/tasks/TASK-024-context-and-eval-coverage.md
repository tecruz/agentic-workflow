# TASK-024 — context-module and eval coverage for the three v1.13 modules

## Status

Status: done
Updated: 2026-09-08

## Risk profile

Profile: standard

## Profile rationale

Test-fixture and eval-scenario coverage only — no authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: The three v1.13 context modules (data-integrity, api-design-patterns,
  error-handling) each ship the four per-module validate-context fixtures
  (valid / none / fenced-valid / fenced-none), mirroring the v1.9.0 module
  fixture pattern.
- AC-2: Golden outcome tests pin the fixtures: valid and none classify VALID
  (0), fenced variants classify INVALID (1), in both the Bats and Pester
  suites.
- AC-3: Three new offline eval scenarios (data-integrity-change,
  api-pagination-change, error-handling-retry-policy) ship generator-synced
  artifacts; `run-evals.sh` and `run-evals.ps1` each classify 11/11 correctly
  with the negative control still failing only on FORBIDDEN_ACTIONS_ABSENT.
- AC-4: Regeneration is byte-stable: `generate-scenarios.ps1` output for the
  eight pre-existing scenarios is unchanged (git diff contains only the three
  new scenario directories).
- AC-5: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | 12 new files under tests/fixtures/context-tasks/ (4 per module); validate-context.sh exit codes: valid/none → 0, fenced → 1 for all 12 | passed |
| AC-2 | tests/bats/validate_context_test.bats + tests/pester/ValidateContext.Tests.ps1 golden loops over the 12 fixtures; CI Full Bats + Pester green | passed |
| AC-3 | evals/run-evals.sh and evals/run-evals.ps1 each report 11/11 correctly; test-weakening-attempt still FAIL on FORBIDDEN_ACTIONS_ABSENT only | passed |
| AC-4 | git status after regeneration: only the three new scenario dirs untracked; no diff on the eight existing scenario dirs | passed |
| AC-5 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — fixture, golden-test, and eval-harness changes for the context registry

## Skills

- task-decomposition v1 invoked — work split into fixture set, golden tests, eval scenarios, and generator sync

## Files changed

- tests/fixtures/context-tasks/ — 12 new per-module fixtures (data-integrity, api-design-patterns, error-handling)
- tests/bats/validate_context_test.bats — golden outcome tests for the new fixtures
- tests/pester/ValidateContext.Tests.ps1 — Pester twins for the new fixtures
- evals/generate-scenarios.ps1 — three new scenario entries; header comment de-counted
- evals/scenarios/{data-integrity-change,api-pagination-change,error-handling-retry-policy}/ — scenario.json + artifacts (generator-produced)
- .agentic/tasks/TASK-024-context-and-eval-coverage.md (new)

## Verification

### Baseline

- Clean tree at v1.12.1 (`ef3f5f5`); git status clean.
- The three v1.13 context modules registered in INDEX + installers but without
  per-module validate-context fixtures or eval scenarios (gap confirmed by
  corpus inspection: 62 context fixtures, 8 eval scenarios — none covering
  the new modules).

### Final

- `validate-context.sh` on all 12 new fixtures: valid/none → exit 0, fenced
  variants → exit 1 (12/12 expected codes).
- `evals/run-evals.sh` 11/11 correct; `evals/run-evals.ps1` 11/11 correct;
  negative control fails only on FORBIDDEN_ACTIONS_ABSENT.
- Generator byte-stability: re-running `generate-scenarios.ps1` produces only
  the three new scenario dirs; the eight pre-existing dirs are unchanged.
- `bash -n` clean on evals/run-evals.sh and the modified bats file parses
  under bats (CI); PS1 parse clean via `pwsh -NoProfile -Command
  [scriptblock]::Create` on generate-scenarios.ps1.
- Full Bats + Full Pester (Windows) verified in CI Full (all 5 jobs green);
  Pester/bats/shellcheck not installed on this host — proven in CI per
  TASK-019 precedent.
- Pre-existing failures: TASK-023 and other pre-v1.13 task files fail the
  current `## Verification` section requirement (validator stricter than when
  they were written) — pre-existing drift, out of scope for this task.

## Remaining risks

- Eval scenario coverage is behavioral, not exhaustive: the harness checks
  that artifacts satisfy the real contracts, not that every possible
  selection combination is exercised.
- `generate-scenarios.ps1` remains the source of truth for scenario fixtures;
  the committed artifacts were regenerated with it at this commit and are
  byte-stable, but any future regeneration must go through the generator to
  preserve the parity.