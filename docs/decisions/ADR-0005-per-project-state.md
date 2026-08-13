# ADR-0005 — Per-project state: tasks, decisions, STATUS

- **Date**: 2026-08-13
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback.md`

## Context

The framework previously shipped `Memory/PROJECT_STATE.md` and
`Memory/DECISION_LOG.md`, which implied persistent agent memory that the
framework cannot actually provide, and conflated mutable state with immutable
decisions. Review feedback (§3 "task state", §8 "state restructure") required
explicit, per-task state files and a clear separation of decisions.

## Decision

- `.agentic/STATUS.md` — one index of current project state, seeded once and
  project-owned.
- `.agentic/tasks/` — one file per task following `tasks/README.md` guidance
  and the task templates; the lifecycle plan/step maps onto these files.
- `.agentic/decisions/` — immutable Architecture Decision Records (ADRs) per
  `decisions/README.md`; ADRs are never edited after acceptance, only
  superseded.
- The framework's own decision history lives in `docs/decisions/` at this
  repository root; `.agentic/` copies installed into adopting projects are the
  adopting project's ADRs.
- `Memory/` was removed; no file claims to be a persistent memory store.

## Consequences

- State and decisions are explicit, discoverable, and tool-agnostic.
- The installer can safely update `.agentic/` scaffolding without touching
  project ADRs, tasks, or status (managed vs. seed split, ADR-0003).
- Contributors must create one file per task/decision instead of accumulating
  a single mutable log.