# Multi-Agent Task Coordination

Provides optional, isolated multi-agent task orchestration built on top of the observability (ADR-0009) and behavioral evaluation (ADR-0010) foundations, implemented in `coordinator.sh` / `coordinator.ps1` (Bash+PowerShell twins, `protocol_version` 1.6.0).

## Principles

1. **Sandbox Isolation**: Each task worker operates in an isolated `git worktree` under `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>`.
2. **Explicit Ownership**: A per-task lock file (`.agentic/orchestration/worktrees/<task-id>.lock`) prevents concurrent conflicting mutations.
3. **Observable Handoffs**: Workers emit ADR-0009-compatible JSONL event streams (`orchestration-events-v1.schema.json`) and an aggregated `orchestration-result-v1` document with `result↔exit_code` pairing invariants.
4. **Controlled Writes**: Remote writes and spawning require explicit approval gates.

## How It Works

The orchestration flow follows a deterministic pipeline:

1. **Task file parse**: The coordinator reads the task file (`.agentic/tasks/TASK-XXX.md`), extracts its ID, validates required approval gates, and checks for an existing lock file.
2. **Worktree creation**: A `git worktree` is created at `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>`. If the worktree already exists (from a previous run), the coordinator reuses it. A lock file is written with the current PID.
3. **Worker spawn**: The coordinator forks a subprocess running the command specified by `--worker` (or `AGENTIC_WORKER_CMD`). The worker inherits the worktree as its working directory and receives the task file path as its context.
4. **Event stream**: While the worker runs, stdout/stderr are captured. On completion, the coordinator emits a JSONL event stream (`orchestration-events-v1`) with `task_start`, `task_complete`, and `task_error` events, plus an aggregated `orchestration-result-v1` document pairing the exit code with the outcome.
5. **Cleanup**: If `--cleanup` is passed and the worker exits successfully (code 0), the worktree and branch are removed. On failure, the worktree is preserved for inspection. The lock file is always removed on exit.

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

## Common Patterns

### 1. CI-Driven Task Completion

Run a task end-to-end in a CI pipeline with automatic cleanup:

```bash
bash .agentic/orchestration/coordinator.sh \
  --approve --push --cleanup \
  --worker "make test" \
  .agentic/tasks/TASK-012.md
```

The branch is pushed to remote for review; the local worktree is removed. If the worker fails, the worktree is preserved so the CI log can reference it for debugging.

### 2. Local Developer Task Execution

A developer runs a task locally without pushing, preserving the worktree for iteration:

```bash
bash .agentic/orchestration/coordinator.sh \
  --approve \
  --worker "opencode --task .agentic/tasks/TASK-005.md" \
  .agentic/tasks/TASK-005.md
```

After the worker finishes, inspect the worktree at `.agentic/orchestration/worktrees/TASK-005/`. Push manually when ready, or clean up with `--cleanup`.

### 3. Multi-Agent Parallel Work

Multiple agents work on different tasks concurrently, each in its own worktree:

```bash
# Agent A
bash .agentic/orchestration/coordinator.sh --approve --worker "agent-a --task TASK-010.md" .agentic/tasks/TASK-010.md &

# Agent B
bash .agentic/orchestration/coordinator.sh --approve --worker "agent-b --task TASK-011.md" .agentic/tasks/TASK-011.md &
```

Each task gets its own worktree and lock file. The lock prevents the same task from being started twice; different tasks run in fully isolated directories on separate branches.

## Failure Modes

| Failure | Behavior | Resolution |
| :--- | :--- | :--- |
| **Worker crash (exit non-0)** | Coordinator emits `task_error` event, preserves the worktree, exits with the worker's exit code. | Inspect worktree at `.agentic/orchestration/worktrees/<id>/`. Fix the issue and re-run, or remove the worktree manually. |
| **Lock contention (concurrent tasks)** | If two coordinator processes attempt the same task ID, the second sees an existing lock file and exits with code 2 (BLOCKED). | Wait for the first process to finish. The lock is per-task-ID, not global — different tasks do not contend. |
| **Stale worktree (PID gone)** | On startup, the coordinator detects a lock file whose PID no longer exists, removes the stale lock, and proceeds. | No action needed; the coordinator self-heals. If the worktree itself is orphaned, run `git worktree prune`. |
| **Approval gate blocking** | A task file has unchecked or missing gates. The coordinator refuses to spawn and exits with code 2. | Edit the task file, check the required `AG-N` gate, and re-run. |

## Troubleshooting

| Error | Cause | Fix |
| :--- | :--- | :--- |
| `worktree already exists` | A previous run created the worktree but did not clean up (e.g. `--cleanup` not used, or task failed). | Remove with `git worktree remove .agentic/orchestration/worktrees/<id>` or reuse with a new run. |
| `lock file exists, PID <N> still running` | Another coordinator is actively running this task. | Wait for the other process to finish. Check with `ps -p <N>`. |
| `approval gate <N> not checked` | The task file's `## Approval gates` section does not have `[x]` for the required gate. | Open the task file, check the gate, save, and re-run. |
| `branch orchestration/<id> already exists` | A branch from a previous run was not deleted. | `git branch -D orchestration/<id>` or let the coordinator reuse it on the next run. |
| `worker command not found` | The `--worker` command or `AGENTIC_WORKER_CMD` references a binary not on PATH. | Ensure the tool is installed and on PATH inside the worktree environment. |
| `exit code 3 (UNSUPPORTED)` | No recognized project or check configuration found. | Verify the worktree contains a supported project root (package.json, Cargo.toml, etc.) or pass an explicit worker command. |

## Files

- `coordinator.sh` / `coordinator.ps1` — twins, managed.
- `.agentic/schemas/orchestration-result-v1.schema.json` — aggregated result contract.
- `.agentic/schemas/orchestration-events-v1.schema.json` — JSONL event stream contract.

## Stale Worktree GC Policy

Worktrees and branches created by the coordinator can accumulate over time. This policy governs their cleanup:

### Automatic Cleanup

- **`--cleanup` flag**: When supplied, the coordinator removes the worktree and its branch after successful completion (exit 0). Use this for CI pipelines.
- **Lock file expiry**: Lock files (`.agentic/orchestration/worktrees/<id>.lock`) contain the owning PID. On startup, the coordinator removes stale locks where the PID no longer exists.

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

> **Recommendation**: Configure CI pipelines with `--cleanup`. For local development, run `git worktree prune` periodically. Do not rely on automatic cleanup for failed tasks — preserve worktrees for debugging.
