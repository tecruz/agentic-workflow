# TASK-027 — negative-control eval scenario for REQUIRED_MODULES_SELECTED

## Status

Status: done
Updated: 2026-09-08

## Risk profile

Profile: standard

## Profile rationale

Eval-scenario and harness-test addition only — no authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: A second offline negative-control scenario (`wrong-module-selected`)
  ships with generator-synced artifacts; it selects `database-migrations`
  where `security-review` is required, failing exactly
  `REQUIRED_MODULES_SELECTED` and nothing else.
- AC-2: Both eval twins classify 12/12 correctly; the new control reports
  `observed=FAIL expected=FAIL harness=PASS` with the only failed check pinned
  to `REQUIRED_MODULES_SELECTED`.
- AC-3: `generate-scenarios.ps1` output is byte-stable — regeneration adds
  only the new scenario directory.
- AC-4: JsonContracts Pester suite updated: document/dir counts to 12, the
  positive-scenario filter excludes all `FAIL`-expected scenarios, and a new
  test asserts the wrong-module control's single failing check.
- AC-5: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | evals/scenarios/wrong-module-selected/{scenario.json,artifacts/*} generated; scenario.json `fixture_expected_result=FAIL`, `expected_failed_checks=[REQUIRED_MODULES_SELECTED]`, required_modules=[security-review] | passed |
| AC-2 | evals/run-evals.sh and run-evals.ps1 each: 12/12; wrong-module-selected failed only REQUIRED_MODULES_SELECTED[missing: security-review] | passed |
| AC-3 | git status after regeneration: only evals/scenarios/wrong-module-selected/ untracked; the eleven pre-existing dirs unchanged | passed |
| AC-4 | JsonContracts.Tests.ps1 (doc 11→12, dir 11→12, positive filter by expected_result, new negative-control It); PS1 parse clean | passed |
| AC-5 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — eval-harness scenario and contract test changes

## Skills

- verification-triage v1 invoked — negative-control detection was triaged to ensure exactly one check fails

## Files changed

- evals/generate-scenarios.ps1 — `wrong-module-selected` scenario entry
- evals/scenarios/wrong-module-selected/ — scenario.json + artifacts (generator-produced)
- tests/pester/JsonContracts.Tests.ps1 — counts, positive filter, new negative-control assertion
- .agentic/tasks/TASK-027-wrong-module-negative-control.md (new)

## Verification

### Baseline

- Only `FORBIDDEN_ACTIONS_ABSENT` had a negative-control scenario; every other
  contract leg (including `REQUIRED_MODULES_SELECTED`) was exercised
  positively only, so a runner regression that always-passed module selection
  would be invisible. 11 scenarios, 10 positive.

### Final

- `run-evals.sh` 12/12; `run-evals.ps1` 12/12; wrong-module-selected:
  `observed=FAIL expected=FAIL harness=PASS` with `failed=REQUIRED_MODULES_SELECTED[missing: security-review]`, single failed check.
- `generate-scenarios.ps1` regenerates byte-stably (only the new dir).
- JsonContracts.Tests.ps1 parse-clean via Parser::ParseInput; full Pester run
  left to CI (bats/shellcheck not on this host — TASK-019 precedent).

## Remaining risks

- The two negative controls pin `FORBIDDEN_ACTIONS_ABSENT` and
  `REQUIRED_MODULES_SELECTED`; the remaining legs still lack negative
  controls but are unlikely to regress silently given they gate artifact
  validity (TASK_CONTRACT_VALID / *_SCHEMA_VALID) which the positive corpus
  already exercises.
- Eval runs are full-corpus and thus slow; the local Pester verification is
  limited to the runner twins plus a parse check, with the full suite proven
  in CI Full.