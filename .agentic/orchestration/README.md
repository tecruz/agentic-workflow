# Multi-Agent Task Coordination

Provides optional, isolated multi-agent task orchestration built on top of the observability (ADR-0009) and behavioral evaluation (ADR-0010) foundations, implemented in `coordinator.sh` / `coordinator.ps1` (Bash+PowerShell twins, `protocol_version` 1.6.0).

## Principles

1. **Sandbox Isolation**: Each task worker operates in an isolated `git worktree` under `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>`.
2. **Explicit Ownership**: A per-task lock file (`.agentic/orchestration/worktrees/<task-id>.lock`) prevents concurrent conflicting mutations.
3. **Observable Handoffs**: Workers emit ADR-0009-compatible JSONL event streams (`orchestration-events-v1.schema.json`) and an aggregated `orchestration-result-v1` document with `result↔exit_code` pairing invariants.
4. **Controlled Writes**: Remote writes and spawning require explicit approval gates.

## Usage

```bash
# Dry check: worktree creation without a worker
bash .agentic/orchestration/coordinator.sh --approve .agentic/tasks/TASK-009.md

# Generic worker (any agent CLI) inside the isolated worktree
AGENTIC_WORKER_CMD="my-agent --task task.md" bash .agentic/orchestration/coordinator.sh --approve .agentic/tasks/TASK-009.md
bash .agentic/orchestration/coordinator.sh --approve --worker "bash -c 'echo hi'" .agentic/tasks/TASK-009.md

# Events + JSON (mutually exclusive)
bash .agentic/orchestration/coordinator.sh --approve --worker "make test" --events .agentic/runs/coord.jsonl .agentic/tasks/TASK-009.md
bash .agentic/orchestration/coordinator.sh --approve --worker "make test" --format json .agentic/tasks/TASK-009.md

# Remote write (push branch) and cleanup
bash .agentic/orchestration/coordinator.sh --approve --push --cleanup --worker "make test" .agentic/tasks/TASK-009.md
```

PowerShell:

```powershell
pwsh -File .agentic/orchestration/coordinator.ps1 -Approve -Worker "npm test" .agentic/tasks/TASK-009.md
```

Approval gates are read from the task file's `## Approval gates` section. A checked `AG-N` gate plus `--approve` (or `-Approve`) is required to spawn; `--push` (`-Push`) is additionally required for remote writes. When `None identified` is declared, the flag alone suffices. Unchecked or malformed gates block with exit 2 and create no worktree.

Events and JSON results never contain raw command lines, arguments, environment, or absolute user-home paths; working directories are project-relative (or basename outside the project).

## Files

- `coordinator.sh` / `coordinator.ps1` — twins, managed.
- `.agentic/schemas/orchestration-result-v1.schema.json` — aggregated result contract.
- `.agentic/schemas/orchestration-events-v1.schema.json` — JSONL event stream contract.

## Stale Worktree GC Policy

Worktrees and branches created by the coordinator can accumulate over time. This
policy governs their cleanup:

### Automatic Cleanup

- **`--cleanup` flag**: When supplied, the coordinator removes the worktree and
  its branch after successful completion (exit 0). Use this for CI pipelines.
- **Lock file expiry**: Lock files (`.agentic/orchestration/worktrees/<id>.lock`)
  contain the owning PID. On startup, the coordinator removes stale locks where
  the PID no longer exists.

### Manual Cleanup

Run the GC command to remove orphaned worktrees and branches:

```bash
# List worktrees
git worktree list | grep 'orchestration/'

# Remove specific worktree
bash .agentic/orchestration/coordinator.sh --approve --cleanup .agentic/tasks/TASK-ID.md

# Bulk cleanup (manual)
git worktree prune
git branch -D $(git branch --list 'orchestration/*' | sed 's/^..//')
```

### Retention Policy

| Scenario | Retention |
| :--- | :--- |
| Successful task with `--cleanup` | Immediate removal |
| Failed/blocked task | Preserved until manual review |
| Stale lock (PID gone) | Removed on next coordinator run |
| Unreferenced branch (no worktree) | `git worktree prune` removes |

> **Recommendation**: Configure CI pipelines with `--cleanup`. For local
> development, run `git worktree prune` periodically. Do not rely on
> automatic cleanup for failed tasks — preserve worktrees for debugging.
