# TASK-049: Walking-skeleton checkpoint for orchestration

## Status

Status: done
Updated: 2026-09-28

## Risk profile

Profile: standard

## Profile rationale

Adds one opt-in coordinator flag and one optional task-file section; no change
to existing flows when `--skeleton` is not used. No escalation signals: no
authentication, payments, secrets, destructive data operations, production
infrastructure changes, or irreversible operations. Precedent: TASK-009 (the
coordinator itself) ran at `standard`.

## Acceptance criteria

- AC-1: `coordinator.sh --skeleton` requires a canonical `## Walking skeleton`
  section in the task file (`- Slice:`, `- Integrated check:`, `- Skeleton
  approval: pending | approved by <approver> on YYYY-MM-DD`); a missing or
  malformed section is BLOCKED (exit 2).
- AC-2: A `pending` skeleton approval refuses `--push` and `--cleanup` with
  BLOCKED (exit 2, `SKELETON_APPROVAL_PENDING`) before any worker runs.
- AC-3: After a passing worker and review stage, `--skeleton` runs the
  integrated check inside the worktree; a failing check fails the run (exit 1,
  `SKELETON_CHECK_FAILED`), a passing check emits a `skeleton_checkpoint`
  event and allows push/cleanup when approval is recorded.
- AC-4: `coordinator.ps1 -Skeleton` mirrors the bash twin's exit codes and
  messages; `orchestration-events-v1` and `orchestration-result-v1` schemas
  admit `skeleton_checkpoint` and `SKELETON_CHECK_FAILED`.
- AC-5: Docs updated (`.agentic/orchestration/README.md`, main `README.md`
  orchestration section, `.agentic/templates/task.md` comment block); Bats and
  Pester coordinator suites cover the new paths and stay green.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats `coordinator_test.bats` and Pester `Coordinator.Tests.ps1` skeleton rows: missing and malformed `## Walking skeleton` sections exit 2 with the canonical message in both twins (suites 26/26 and 17/17) | passed |
| AC-2 | `pending` approval plus `--push`/`-Push` and `pending` plus `--cleanup`/`-Cleanup` exit 2 `SKELETON_APPROVAL_PENDING` before lock, worktree, or worker in both twins (Bats, Pester, and manual smoke) | passed |
| AC-3 | Failing integrated check exits 1 `SKELETON_CHECK_FAILED` with no `skeleton_checkpoint` event; passing check emits `skeleton_checkpoint` before `worker_completed`; Bats test 24 jsonschema-validates the emitted stream | passed |
| AC-4 | Cross-language exit-code/message parity pinned by mirrored Bats/Pester rows; `orchestration-events-v1` (five definitions, `check_exit_code` const 0) and `orchestration-result-v1` admit the new code; JsonContracts suite green within Pester 464/0/24 | passed |
| AC-5 | Orchestration README, root README, and task template updated; coordinator suites 26/26 Bats and 17/17 Pester; `verify.ps1` Pester 464/0/24 with evals 19/19 on both legs (`bats` check tooling-unavailable on Windows; full WSL Bats 472/477 ok with only the five pre-existing failures) | passed |

## Approval gates

- None identified

## Context modules

- public-api-change v1 loaded — task adds a coordinator flag and a new JSONL event type to the versioned orchestration contracts adopters consume
- testing-infrastructure v1 loaded — task adds coordinator regression tests in the Bats and Pester suites

## Skills

- task-decomposition v1 invoked — coordinator flag, gate semantics, schema events, docs, and mirrored tests decomposed into single-purpose edits

## Files changed

- .agentic/orchestration/coordinator.sh
- .agentic/orchestration/coordinator.ps1
- .agentic/schemas/orchestration-events-v1.schema.json
- .agentic/schemas/orchestration-result-v1.schema.json
- .agentic/orchestration/README.md
- .agentic/templates/task.md
- README.md
- tests/bats/coordinator_test.bats
- tests/pester/Coordinator.Tests.ps1
- CHANGELOG.md
- .agentic/STATUS.md
- docs/decisions/ADR-0018-walking-skeleton-checkpoint.md (new)
- docs/decisions/README.md
- .agentic/tasks/TASK-049-walking-skeleton-checkpoint.md (this file)

## Verification

### Baseline

- Clean `master` worktree `verify.ps1` (archived `baseline-verify-run1.log`):
  sh-syntax, `handoff-gate`, and `ps-syntax` checks green; Pester
  441 passed / 0 failed / 24 skipped (rerun 2026-09-28 identical); baseline
  coordinator coverage 19 Bats / 10 Pester tests, green in the partial
  baseline Bats run (186 ok before it was stopped for contention).
- No skeleton handling existed: both coordinator twins rejected the flag as
  an unknown option, no `skeleton_checkpoint` event or
  `SKELETON_CHECK_FAILED` code existed in either schema, and no integrated
  check ran after review.

### Final

- Twin smoke tests (2026-09-28), mirrored across `coordinator.sh` and
  `coordinator.ps1`: missing/malformed section, pending+push, and
  pending+cleanup all BLOCKED exit 2 with the canonical messages;
  approved + passing check exits 0 with `skeleton_checkpoint` before
  `worker_completed`; approved + failing check exits 1
  `SKELETON_CHECK_FAILED` without a checkpoint event; `-Format Json` with a
  gate violation stays BLOCKED with no JSON; runs without the flag are
  byte-identical to the previous contract.
- `coordinator_test.bats` 26/26 and `Coordinator.Tests.ps1` 17/17.
- `verify.ps1` (2026-09-28): sh-syntax ×8, `handoff-gate`, `ps-syntax`
  green; Pester 464 passed / 0 failed / 24 skipped; `evals-sh` 19/19;
  `evals-ps` 19/19; overall BLOCKED exit 2 only for the Windows-unavailable
  `bats` check.
- Full Bats via WSL: 477 tests, 472 ok, 5 not ok — the five pre-existing
  environment failures, unchanged from baseline.

## Remaining risks

- The integrated check honors `--sandbox` like the worker does; a host without
  the container runtime stays BLOCKED exactly as for the worker.
- Multi-unit sequencing remains per-invocation (one coordinator run per task);
  the skeleton checkpoint gates only push/cleanup, not fan-out order.
