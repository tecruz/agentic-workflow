# Multi-Agent Task Coordination

Provides optional, isolated multi-agent task orchestration built on top of the observability (PR #9) and behavioral evaluation (PR #10) foundations.

## Principles
1. **Sandbox Isolation**: Each task worker operates in an isolated worktree or microVM sandbox.
2. **Explicit Ownership**: Unique task ownership prevents concurrent conflicting mutations.
3. **Observable Handoffs**: Workers emit PR #9-compatible JSONL event streams.
4. **Controlled Writes**: Remote writes and spawning require explicit approval gates.
