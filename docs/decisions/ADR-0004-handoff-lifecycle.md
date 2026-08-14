# ADR-0004 — Handoff lifecycle with bounded self-healing

- **Date**: 2026-08-13
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback.md`

## Context

The original lifecycle ended with "Verification" and had no defined handoff,
letting agents stop after an unverified change or loop forever on a failing
test. Review feedback (§5 "handoff", §7 "bounded self-healing and test
integrity") required explicit closure and limits on repair cycles.

## Decision

- Lifecycle: `DISCOVER → PLAN → IMPLEMENT → VERIFY → HANDOFF`. Handoff is a
  first-class phase reporting files changed, verification commands run with
  exit codes and results, pre-existing failures, environment blockers,
  remaining risks, and commit status.
- Bounded self-healing: at most three evidence-based repair cycles; after that
  stop, preserve the latest useful state, and report the blocker. Never weaken
  a failing test merely to go green.
- Honest verification reporting: distinguish baseline/pre-existing failures
  from regressions caused by the change; never report success based on skipped
  or blocked checks (see ADR-0002).
- Commits happen only when explicitly requested or permitted by documented
  project policy; otherwise a clean working-tree diff is left for review.

## Consequences

- Agents always close the loop with a verifiable statement of what ran and
  what is blocked; reviewers know what to trust.
- The three-cycle cap prevents infinite repair loops while preserving the
  latest useful state for the next agent.
- Handoff templates and rules (`03-testing-verification.md`,
  `04-git-conventions.md`) encode the behavior so all tools act alike.