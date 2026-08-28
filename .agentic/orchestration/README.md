# Multi-Agent Task Coordination

> **Stub (ADR-0011)** — This directory currently ships a placeholder only. `coordinator.sh` prints a stub message and exits 0; no worktree creation, worker spawning, or approval enforcement is implemented yet. The principles below describe the intended design.

Provides optional, isolated multi-agent task orchestration built on top of the observability (ADR-0009) and behavioral evaluation (ADR-0010) foundations.

> Do not invoke `coordinator.sh` expecting coordination — it is a no-op stub that always succeeds.

## Principles
1. **Sandbox Isolation**: Each task worker operates in an isolated worktree or microVM sandbox.
2. **Explicit Ownership**: Unique task ownership prevents concurrent conflicting mutations.
3. **Observable Handoffs**: Workers emit ADR-0009-compatible JSONL event streams.
4. **Controlled Writes**: Remote writes and spawning require explicit approval gates.
