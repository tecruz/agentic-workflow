# ADR-0011 — Isolated Multi-Agent Task Coordination

## Status

Accepted (v1.5.0) — prototype stub
Amended (v1.6.0) — full orchestration realized

## Context

Running multiple autonomous agents without isolation or coordination leads to conflicting edits, race conditions, and unobservable side effects ("vibe coding at scale"). Orchestration must build upon established harness observability (PR #9) and behavioral evaluation frameworks (PR #10).

## Decision

1. **Isolated Worktrees**:
   - Each task worker runs in a dedicated isolated worktree or sandbox under `.agentic/orchestration/`.
2. **Worker Handoff & Aggregation**:
   - Workers communicate via versioned JSON result contracts and emit observable JSONL events.
3. **Approval Controls**:
   - Spawning workers and performing remote writes require explicit human approval gates.

## Current scope (v1.5.0)

This change ships only the registry stub: `.agentic/orchestration/README.md` (principles) and `coordinator.sh` (placeholder that prints readiness). No worktree creation, worker spawning, event aggregation, or approval enforcement is implemented yet; those remain follow-up work tracked against this ADR.

## Amendment (v1.6.0) — full orchestration realized

Decision items 1–3 are now implemented; the stub is replaced by a complete coordinator with Bash+PowerShell parity:

1. **Isolated Worktrees (implemented)**:
   - Each task worker runs in a dedicated `git worktree` under `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>`.
   - A per-task lock file (`.agentic/orchestration/worktrees/<task-id>.lock`) enforces explicit ownership and prevents concurrent conflicting mutations; stale locks are detected via PID liveness.
   - `git worktree list` determines reuse; a `--cleanup` flag removes the worktree after completion. Worktree paths are lexically and physically confined to the project root.

2. **Worker Handoff & Aggregation (implemented)**:
   - A generic runner executes `AGENTIC_WORKER_CMD` or `--worker <cmd>` inside the worktree (any agent CLI may be supplied; the coordinator never logs command text).
   - Workers emit a versioned JSONL stream (`orchestration-events-v1.schema.json`: `orchestration_started` → `worker_started` → `worker_completed` → `orchestration_completed` terminal last) and a versioned aggregated result (`orchestration-result-v1.schema.json` with `result↔exit_code` pairing invariants). Working directories are project-relative redacted; no command lines, args, env, or absolute user paths leak into events or results.
   - `protocol_version` moves to `"1.6.0"` in both new schemas and in all emitters; `orchestration_started`/`worker_started` carry only `event`/`worker_id`/`working_directory` (no extra PII).

3. **Approval Controls (implemented)**:
   - Spawning workers requires both a checked `AG-N` gate in the task file and the explicit `--approve` flag (`-Approve` in PowerShell); remote writes require `--push` (`-Push`) in addition.
   - When no gate is required (`None identified` in `## Approval gates`), the flag alone suffices. A malformed gate block or any unchecked `AG-N` causes a structured `BLOCKED` diagnostic and the coordinator creates no worktree and performs no remote write.
   - `--push` without `--approve` is rejected. The task-file gate check mirrors `validate-task` authority rules (fenced code, HTML comments, and blockquotes are dropped).

4. **Cross-language parity and registration**:
   - `coordinator.sh` and `coordinator.ps1` are held to identical observable behavior by shared fixtures; both plus the two new schemas are managed files (installers, bundle) and are validated by `checks.tsv`/`ps-syntax` and bundle-leak gates.

5. **Operational guards**:
   - `git` is required; outside a worktree or without `git` the coordinator surfaces `BLOCKED` / `TOOLING_UNAVAILABLE`.
   - Events and JSON stdout are mutually exclusive (like `verify.sh`/`verify.ps1`); `--events` destinations are confined to `.agentic/runs/` and are promoted atomically (scratch + hard-link/`mv -Force` with `EventsForce`).

## Consequences

- Multi-agent workflows are safely coordinated and fully observable without risking repository corruption (once follow-up work lands).
- Adopters receive the orchestration directory as managed files; the stub has no runtime effect and requires no migration.
- Adopters upgrading from v1.5.0 receive the new coordinator and schemas as managed updates; existing worktrees under `.agentic/orchestration/worktrees/` are outside the managed set and are not pruned by the installer. Worktree branches `orchestration/<task-id>` persist unless `--cleanup` is used; concurrent runs for the same task ID are serialized by the lock file.
