# Decisions

This directory holds **Architecture Decision Records (ADRs)**. Each ADR is an
immutable record of one decision; once accepted, do not rewrite history in an
existing file — record follow-ups in a new ADR.

## File convention

```
ADR-NNNN-short-description.md
```

Number decisions sequentially (ADR-0001, ADR-0002, ...).

## Template

```markdown
# ADR-NNNN — <title>

- **Date**: [date]
- **Status**: Proposed | Accepted | Deprecated
- **Deciders**: [people or agents]

## Context
[What prompted the decision, and what constraints or alternatives exist.]

## Decision
[What was decided, concretely.]

## Consequences
[Trade-offs, follow-ups, and what this enables or blocks.]
```

## Guidance

- Keep ADRs immutable after acceptance; supersede, never edit, an old record.
- Write enough context that the decision stands alone for future readers.
