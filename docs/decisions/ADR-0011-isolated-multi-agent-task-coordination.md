# ADR-0011 — Isolated Multi-Agent Task Coordination

## Status

Accepted (v1.5.0) — prototype stub

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

## Consequences

- Multi-agent workflows are safely coordinated and fully observable without risking repository corruption (once follow-up work lands).
- Adopters receive the orchestration directory as managed files; the stub has no runtime effect and requires no migration.
