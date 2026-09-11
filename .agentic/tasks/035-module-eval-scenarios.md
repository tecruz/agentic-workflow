# TASK-035: Module eval scenarios

## Status

Status: done
Updated: 2026-09-10

## Risk profile

Profile: standard

## Profile rationale

Standard profile for test harness extension. No production code changes.

## Approval gates

- [x] AG-1: Approved by maintainers on 2026-09-10

## Acceptance criteria

- AC-1: 5 new eval scenarios cover the 5 previously uncovered standard context modules.
- AC-2: Each scenario's AC count matches its evidence row count (no TASK_CONTRACT_VALID failures).
- AC-3: JsonContracts.Tests.ps1 counts updated to reflect 17 scenarios (12→17 docs, 10→15 positive).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | scenario-coverage: 5 new scenarios (performance-hot-path, accessibility-contrast, i18n-string-extraction, mobile-responsive-breakpoint, testing-ci-config) | passed |
| AC-2 | ac-evidence-parity: each scenario's AC count matches evidence count | passed |
| AC-3 | json-contracts-counts: 17 docs, 15 positive, 17 dirs all passing | passed |

## Context modules

- None selected — eval harness extension is a testing-only change.

## Skills

- None required — generator pattern is established from TASK-024.

## Verification

### Baseline

- 12 scenarios, 5 standard context modules uncovered (performance, accessibility, i18n, mobile-adaptive, testing-infrastructure).

### Final

- 17 scenarios, 17/17 passing in both bash and pwsh. All 13 context modules now have eval coverage.

## Files changed

- `evals/generate-scenarios.ps1`
- `evals/scenarios/` (5 new dirs: accessibility-contrast, i18n-string-extraction, mobile-responsive-breakpoint, performance-hot-path, testing-ci-config)
- `tests/pester/JsonContracts.Tests.ps1`

## Remaining risks

- None identified.
