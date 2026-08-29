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
