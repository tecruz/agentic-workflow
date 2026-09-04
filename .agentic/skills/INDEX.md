# Skills Index

> Portable, on-demand procedure registry parallel to context modules. Each
> directory holds one skill following the shared contract in `SKILL.md`.
> Inspect this index during **PLAN**, invoke every skill whose *Invoked when*
> triggers match the task, and record each invocation in the task file under
> `## Skills`. Do not load skill contents into every session: load only what
> the task invokes, before the corresponding work begins.
>
> Invocation line format (one bullet per skill, recorded in the task file):
>
>     - <skill-id> v<version> invoked — <invocation rationale>
>
> Work that invokes no procedure records the sentinel:
>
>     - None required — <why no skill applies>

## Registry

| ID | Version | Minimum risk profile | Invoked when (summary) |
| --- | --- | --- | --- |
| task-decomposition | 1 | standard | Breaking a request into atomic, verifiable steps before planning |
| verification-triage | 1 | standard | Diagnosing a check failure, forming a root-cause hypothesis, repairing |
| release-verification | 1 | standard | Confirming VERSION/CHANGELOG/tag agreement, bundle and archive integrity |

## Rules

- An invoked skill must exist in this registry; unknown IDs are rejected by
  `.agentic/scripts/validate-skills.sh` / `validate-skills.ps1`.
- The declared version must match the skill's current version.
- A skill's minimum risk profile is a floor: a task may always escalate, but
  it must not run at a lower profile than any invoked skill requires.
- Duplicate invocations of the same skill are rejected.
- A completed task may not carry unresolved placeholders in its invocations.
