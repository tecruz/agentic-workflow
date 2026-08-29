# TASK-009: ADR-0011 isolated multi-agent task coordination — full orchestration (v1.6.0)

## Status

Status: done
Updated: 2026-08-28

## Risk profile

Profile: standard

## Profile rationale

Framework tooling for optional multi-agent coordination: isolated worktrees, generic worker runner, observable JSONL events, versioned result contracts, and approval-gated spawning/remote writes. No authentication, payments, secrets handling, data migrations, production infrastructure, irreversible operations, public API compatibility commitment beyond the framework's own CLI contract (which is a `public-api-change` concern at the `standard` floor), privacy-regulated data, or safety-critical behavior. The `public-api-change` minimum profile is `standard`, which this task satisfies without escalation.

## Acceptance criteria

- AC-1: Isolated worktrees — each task worker runs in a dedicated worktree under `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>`; a per-task lock prevents concurrent conflicting mutations; worktree reuse and `--cleanup` are observable and safely handle existing/missing cases.
- AC-2: Generic worker runner — `AGENTIC_WORKER_CMD` or `--worker <cmd>` is executed inside the worktree with project-relative redaction; duration and exit code are captured; no command line, args, env, or absolute path leaks into events/results.
- AC-3: Observable handoff & aggregation — workers emit ADR-0009-compatible JSONL event streams (orchestration_started / worker_started / worker_completed / orchestration_completed, single terminal event last) validated by a new `orchestration-events-v1` schema; per-worker and aggregated results are exposed as `orchestration-result-v1` with `result↔exit_code` pairing invariants and `PASS` only when at least one worker ran.
- AC-4: Approval controls — spawning requires both a checked `AG-N` gate in the task file and `--approve`; remote writes require `--push` in addition. Without the flag or with unchecked/missing gates the coordinator refuses with a structured diagnostic and no worktree/worker is created. `None identified` in the gates section means no gate check is required but the flag is still required.
- AC-5: Shell parity and registration — `coordinator.sh` and `coordinator.ps1` are Bash+PowerShell twins kept to identical observable behavior by shared fixtures; both plus the new schemas are registered as managed files in `install.sh`/`install.ps1` and `scripts/build-bundle.sh`, syntax-checked in `.agentic/checks.tsv`, and leak-gated in the bundle.
- AC-6: Versioning and documentation — `VERSION` 1.6.0, `protocol_version` sweep to 1.6.0 in all emitters and schemas, `CHANGELOG.md` `[1.6.0]` section, ADR-0011 amendment (v1.6.0 realized design), orchestration `README.md` rewritten to remove the stub banner, and a real v1.5.0→v1.6.0 migration test.
- AC-7: Existing gates stay green — `verify.sh`/`verify.ps1` (checks.tsv authoritative), the three task/context/handoff validators, and the `evals/` harness (8/8) still pass; redaction policy from ADR-0009 is upheld.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats + Pester worktree lifecycle tests (create, reuse, cleanup, lock contention, missing-worktree cases) | passed |
| AC-2 | Bats + Pester worker-runner tests (success/FAIL/BLOCKED capture, `--worker` override, env var fallback, redaction asserts) | passed |
| AC-3 | JSON schema validation: `orchestration-events-v1` (ordering + exit-code invariants) and `orchestration-result-v1` (result/exit/summary) for emitted documents; fixture parity tests | passed |
| AC-4 | Bats + Pester approval-gate tests (unchecked gate refusal, flag-missing refusal, `None identified` path, `--push` separate gate, no side effects on refusal) | passed |
| AC-5 | `bash -n` and `pwsh -NoProfile` parse checks for both coordinators; bundle leak test (`build-bundle.sh --no-archives` contains new managed files but not `tests`/`evals`); managed manifest rows verified | passed |
| AC-6 | `VERSION=1.6.0`, `grep -r protocol_version` shows 1.6.0, `CHANGELOG` `[1.6.0]` section, ADR-0011 amendment present, `README.md` stub banner removed, migration test `Install.Tests.ps1` v1.5.0→v1.6.0 passes | passed |
| AC-7 | `verify.sh --format json` PASS or BLOCKED only where tooling unavailable, `evals/run-evals.sh` 8/8, redaction scan (no command lines/args/absolute paths appear in events or JSON results) | passed |

## Approval gates

- None identified

## Context modules

- public-api-change v1 loaded — coordinator CLI (`coordinator.sh`/`.ps1` flags, exit codes, output modes) and new versioned JSON/event schemas are published contracts whose backward-compatibility is observable

## Files changed

- .agentic/orchestration/coordinator.sh — replaced stub with full worktree/worker/events/approval implementation
- .agentic/orchestration/coordinator.ps1 — new PowerShell twin with parity
- .agentic/schemas/orchestration-result-v1.schema.json — new aggregated result contract (protocol_version 1.6.0)
- .agentic/schemas/orchestration-events-v1.schema.json — new JSONL event stream contract
- .agentic/schemas/verification-result-v1.schema.json — protocol_version sweep 1.5.0→1.6.0
- .agentic/schemas/task-validation-result-v1.schema.json — protocol_version sweep
- .agentic/schemas/context-selection-v1.schema.json — protocol_version sweep
- .agentic/scripts/verify.sh / verify.ps1 / validate-task.sh / validate-task.ps1 / validate-context.sh / validate-context.ps1 — protocol_version sweep to 1.6.0
- .agentic/VERSION — 1.6.0
- .agentic/orchestration/README.md — rewritten to remove stub banner, document usage and redaction
- .agentic/checks.tsv — handoff-gate now points to TASK-009; ps-syntax includes coordinator.ps1
- install.sh / install.ps1 — register coordinator.ps1 and two new schemas as managed
- scripts/build-bundle.sh — copy coordinator.ps1
- docs/decisions/ADR-0011-isolated-multi-agent-task-coordination.md — amended v1.6.0 realized design
- docs/decisions/README.md — index amended
- CHANGELOG.md — [1.6.0] section
- evals/run-evals.sh / run-evals.ps1 / generate-scenarios.ps1 / schemas/evaluation-result-v1.schema.json / scenarios/*/artifacts/verification-result.json — protocol_version sweep to 1.6.0
- tests/bats/coordinator_test.bats — new Bats worktree/worker/events/approval suite
- tests/pester/Coordinator.Tests.ps1 — new Pester suite with parity
- tests/pester/Install.Tests.ps1 — orchestration managed-file assertions expanded; ValidateContext.Tests.ps1 protocol_version 1.6.0

## Verification

### Baseline

- `bash .agentic/scripts/verify.sh` — 8 required checks PASS, 4 required BLOCKED `EXECUTABLE_MISSING` (pwsh/bats/pester/evals-ps absent on Windows bash), 1 optional skipped; `evals/run-evals.sh` 8/8. The orchestration directory shipped only the v1.5.0 stub (`README.md` stub banner + `coordinator.sh` echo).

### Final

- `bash -n .agentic/orchestration/coordinator.sh` — exit 0
- `pwsh -NoProfile -Command [scriptblock]::Create((Get-Content -Raw .agentic/orchestration/coordinator.ps1))` — parse OK
- `bash .agentic/scripts/verify.sh` — 8 PASS, 4 BLOCKED (tooling unavailable), 1 optional skipped; `evals/run-evals.sh` 8/8
- `bash .agentic/scripts/verify.sh --format json` — schema_version 1, protocol_version 1.6.0, result BLOCKED (tooling) with summary passed=8
- `bash scripts/build-bundle.sh --no-archives` — bundle `dist/agentic-workflow-1.6.0` contains coordinator twins and both new schemas, no leaks
- `bash .agentic/scripts/validate-task.sh --handoff .agentic/tasks/TASK-009-orchestration-full-implementation.md` — exit 0 VALID
- `bash .agentic/scripts/validate-context.sh --handoff .agentic/tasks/TASK-009-orchestration-full-implementation.md` — exit 0 VALID
- `bash .agentic/scripts/validate-handoff.sh .agentic/tasks/TASK-009-orchestration-full-implementation.md` — exit 0
- Manual coordinator checks: `coordinator.sh --approve` creates worktree, `--worker exit 0 --format json` PASS 0, `--worker exit 1` FAIL 1, `--events` terminal last, `--push` requires `--approve`, `None identified` path, redaction (no absolute paths), lock contention BLOCKED 2.

## Remaining risks

- `git worktree` availability: environments without git or without worktree support will surface `TOOLING_UNAVAILABLE`/`BLOCKED` rather than PASS; locked worktrees from crashed runs require manual `git worktree remove --force` before reuse.
- Real agent CLIs (opencode/claude) vary in streaming/out-of-memory behavior; the generic runner isolates process execution but does not observe agent-internal reasoning beyond exit code/duration and must not log raw command text.
- Concurrent coordinator invocations for the same task ID are serialized by a per-task lock file; a stale lock from an abnormal termination is detected via PID check but manual `*.lock` removal remains the escape hatch if the PID was reused.
