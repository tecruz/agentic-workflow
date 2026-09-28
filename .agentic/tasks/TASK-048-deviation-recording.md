# TASK-048: Explicit deviation recording (phase route, waived gates, completion protocol)

## Status

Status: done
Updated: 2026-09-28

## Risk profile

Profile: standard

## Profile rationale

Additive, backward-compatible extensions to the task-file contract and its
validators; every new section stays optional so existing task files remain
valid. No escalation signals beyond public-contract stewardship, which is
covered by loading `public-api-change`: no authentication, payments, secrets,
data migrations, production infrastructure, irreversible operations, or
privacy behavior. Precedent: TASK-017 and TASK-042 (validator and contract
additions) ran at `standard`.

## Acceptance criteria

- AC-1: Both task validators (`validate-task.sh` / `validate-task.ps1`)
  validate an optional `## Phase route` section: only canonical entries
  `- <PHASE>: EXECUTED` / `- <PHASE>: SKIPPED - <rationale>` (dash separators
  ` - `, ` – `, ` — ` accepted), all six phases (DISCOVER, CLASSIFY RISK,
  PLAN, IMPLEMENT, VERIFY, HANDOFF) exactly once, unknown/duplicate/missing
  phases and missing skip rationale rejected as `PHASE_ROUTE_INVALID`.
- AC-2: `## Phase route` forbids skipping HANDOFF on every profile and forbids
  skipping VERIFY on `standard`/`high-assurance` tasks; violations fail as
  `PHASE_SKIP_FORBIDDEN`.
- AC-3: Both task validators validate an optional `## Waived gates` section:
  canonical rows `- WG-N: <what was waived> - waived by <approver> on
  YYYY-MM-DD - <rationale>` with unique ids, meaningful non-placeholder
  approver, valid ISO date, and substantive rationale, all as
  `WAIVER_INVALID`; a high-assurance task with any waiver row fails as
  `WAIVER_FORBIDDEN`.
- AC-4: `task-validation-result-v1.schema.json` admits the four new diagnostic
  codes so JSON results carrying them stay schema-valid; byte-identical exit
  codes and first-line messages across both twins (parity golden rows).
- AC-5: `.agentic/rules/06-completion-messages.md` defines the standardized
  two-option completion protocol and the no-emergent-deviation rule; the file
  is registered as managed in both installers and referenced from `AGENTS.md`
  §5 and `.agentic/WORKFLOW.md`.
- AC-6: Docs and template updated (`.agentic/templates/task.md`,
  `.agentic/profiles/README.md`, `.agentic/WORKFLOW.md` handoff reporting of
  recorded deviations); new fixtures plus Bats/Pester/parity rows are green in
  both suites.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `validate_task_test.bats` phase-route rows and `ValidateTask.Tests.ps1` twins (suites 183/183 and 179/179) cover valid, duplicate, missing, malformed, and missing-rationale fixtures | passed |
| AC-2 | `phase-route-handoff-skip-forbidden` and `phase-route-verify-skip-standard-forbidden` fixtures assert exit 1 in both suites; `phase-route-verify-skip-prototype-valid` passes | passed |
| AC-3 | `waived-gates-*` fixtures (valid, malformed, duplicate, bad approver, bad date, empty, high-assurance-forbidden) pass mirrored in both suites | passed |
| AC-4 | `task-validation-result-v1.schema.json` enum carries `PHASE_ROUTE_INVALID`, `PHASE_SKIP_FORBIDDEN`, `WAIVER_INVALID`, `WAIVER_FORBIDDEN`; golden parity 180/180 rows byte-identical across legs (bash 180/180, pwsh 180/180 with 0 mismatches) | passed |
| AC-5 | `rules/06-completion-messages.md` present and listed in both installers' managed files; Pester Install 89 passed / 0 failed / 2 skipped; install Bats 109 ok / 4 pre-existing not ok | passed |
| AC-6 | Docs/template updated; `verify.ps1` green on every runnable check (Pester 464/0/24, evals-sh 19/19, evals-ps 19/19; the `bats` check reports tooling unavailable on Windows), full WSL Bats 472 ok / 477 with only the five pre-existing failures | passed |

## Approval gates

- None identified

## Context modules

- public-api-change v1 loaded — task extends the task-file structural contract and the validator diagnostic-code set consumed by adopters' CI; backward compatibility is the core constraint
- testing-infrastructure v1 loaded — task adds validator fixtures, Bats/Pester rows, and parity golden expectations in both test suites

## Skills

- task-decomposition v1 invoked — three related features (phase route, waived gates, completion protocol) decomposed into validator blocks, schema, rules doc, docs, and mirrored tests

## Files changed

- .agentic/scripts/validate-task.sh
- .agentic/scripts/validate-task.ps1
- .agentic/schemas/task-validation-result-v1.schema.json
- .agentic/templates/task.md
- .agentic/profiles/README.md
- .agentic/rules/06-completion-messages.md (new)
- .agentic/WORKFLOW.md
- AGENTS.md
- install.sh
- install.ps1
- tests/fixtures/tasks/phase-route-*.md, waived-gates-*.md (new)
- tests/bats/validate_task_test.bats
- tests/pester/ValidateTask.Tests.ps1
- tests/parity/task-expectations.tsv
- CHANGELOG.md
- .agentic/STATUS.md
- docs/decisions/ADR-0017-explicit-deviation-recording.md (new)
- docs/decisions/README.md
- .agentic/tasks/TASK-048-deviation-recording.md (this file)

## Verification

### Baseline

- Clean `master` `verify.ps1` run (archived `baseline-verify-run1.log`): the
  eight `sh-syntax-*` checks, `handoff-gate`, and `ps-syntax` pass; Pester
  441 passed / 0 failed / 24 skipped; `evals-sh` was interrupted by a host
  sleep; the `bats` check reports tooling unavailable (bats only in WSL).
- Rerun 2026-09-28 on the clean worktree: Pester again 441 passed / 0 failed
  / 24 skipped; baseline full Bats stopped early under contention at 196
  tests (186 ok / 10 not ok — the five pre-existing environment failures
  plus five worktree git-state tag tests).
- No `## Phase route` / `## Waived gates` handling existed: both validators
  accepted such sections silently without validation, and
  `rules/06-completion-messages.md` did not exist.

### Final

- `verify.ps1` (2026-09-28): eight `sh-syntax-*` checks, `handoff-gate`,
  `ps-syntax` green; Pester 464 passed / 0 failed / 24 skipped;
  `evals-sh` 19/19; `evals-ps` 19/19; `shellcheck` optional skip; overall
  BLOCKED exit 2 solely because `bats` is unavailable on Windows.
- Full Bats via WSL: 477 tests, 472 ok, 5 not ok — all five pre-existing
  environment failures (health-report cross-language parity and four
  `zip`-dependent bundle tests), unchanged from baseline.
- Task suites: `validate_task_test.bats` 183/183;
  `ValidateTask.Tests.ps1` 179/179; golden parity 180/180 rows byte-identical
  in both legs; standalone `evals/run-evals.sh` and `evals/run-evals.ps1`
  19/19 exit 0; Pester Install 89/0/2; install Bats 109 ok / 4 pre-existing
  not ok.

## Remaining risks

- Behavioural (prompt-shape) norm in `rules/06-completion-messages.md` is not
  machine-enforced, matching the precedent of rules 01-05; the offline eval
  harness checks artifact contracts, not message text.
