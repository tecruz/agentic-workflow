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

- **Risk profile** - the `Profile: prototype` declaration.
- **Profile rationale** - why this level applies.
- **Task goal** - what the experiment or spike is trying to learn.
- **Smoke verification** - the basic smoke check that the prototype runs.
- **Known limitations** - what the prototype does not cover.
- **Handoff** - outcome, smoke verification result, known limitations, and
  both declarations below.

A prototype must declare, in its `## Handoff` section:

```text
Production readiness: not established
No production deployment or irreversible operation: confirmed
```

The validator rejects a prototype task that omits either declaration.

## Forbidden

- Production deployment or irreversible operations.
- Claiming production readiness.
- Bypassing guarded actions that still require approval (see `AGENTS.md`
  Approval Gates) - a lower profile never overrides mandatory safety or
  approval constraints.

## Handoff

Mark the task `done` under `## Status` and run the validator with
`--handoff` (Bash) / `-Handoff` (PowerShell) as the final gate before
handing off. The handoff must carry both prototype declarations above.