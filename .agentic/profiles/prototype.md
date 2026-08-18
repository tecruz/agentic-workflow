# Prototype Profile

For experiments, spikes, disposable prototypes, and internal demonstrations.
The goal is fast learning, not production quality.

## When to use

Use `prototype` only when **all** of these hold:

- The user explicitly requests an experiment, spike, or disposable prototype.
- No production or persistent system is affected.
- The handoff clearly states that production readiness was **not** established.

## Required evidence

```text
profile: prototype
required_evidence:
  - task_goal
  - prototype_designation
  - smoke_verification
  - known_limitations
  - no_production_deployment
  - readiness_not_established
```

## Required task sections

A prototype task file must include:

- **Task goal** — what the experiment or spike is trying to learn.
- **Known limitations** — what the prototype does not cover.
- **Smoke verification** — the basic smoke check that the prototype runs.
- **Handoff** — outcome, smoke verification result, known limitations, and the
  statement `Production readiness: not established`.

A prototype must declare that no production deployment or irreversible
operation was performed.

## Forbidden

- Production deployment or irreversible operations.
- Claiming production readiness.
- Bypassing guarded actions that still require approval (see `AGENTS.md`
  Approval Gates) — a lower profile never overrides mandatory safety or
  approval constraints.

## Handoff

```text
Profile: prototype
Outcome:
Smoke verification:
Known limitations:
Production readiness: not established
```