# ADR-0011 — Isolated Multi-Agent Task Coordination

## Status

Accepted (v1.6.0)

## Context

Running multiple autonomous agents without isolation or coordination leads to conflicting edits, race conditions, and unobservable side effects ("vibe coding at scale"). Orchestration must build upon established harness observability (PR #9) and behavioral evaluation frameworks (PR #10).

## Decision

1. **Isolated Worktrees**:
   - Each task worker runs in a dedicated isolated worktree or sandbox under `.agentic/orchestration/`.
2. **Worker Handoff & Aggregation**:
   - Workers communicate via versioned JSON result contracts and emit observable JSONL events.
3. **Approval Controls**:
   - Spawning workers and performing remote writes require explicit human approval gates.

## Consequences

- Multi-agent workflows are safely coordinated and fully observable without risking repository corruption.
