# TASK-NNN: Title

## Status

Status: planned
Updated: 2026-08-18

> Copy this template into `.agentic/tasks/` when planning a task. Every task
> declares a risk profile, status, the required evidence for that profile, and its
> approval gates. Choose the profile per `.agentic/profiles/README.md`; the
> default is `standard`.

## Risk profile

Profile: standard

## Profile rationale

[Explain why this level applies and identify any escalation signals.]

## Acceptance criteria

- AC-1: [observable, testable condition]
- AC-2: [observable, testable condition]

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test | Pending |
| AC-2 | Integration test | Pending |

## Approval gates

- None identified

<!-- When approval is required:
- [ ] AG-1: Approval required from Security
- [x] AG-1: Approved by Alice Example on 2026-08-18
-->

## Context modules

- None selected

<!-- Inspect .agentic/context/INDEX.md during DISCOVER. For each module whose
"Load when" triggers match this task, record one bullet BEFORE planning:

- security-review v1 loaded — task changes session/authorization behavior

The line must carry: known module ID, recognized version (v<N> matching the
module), the loaded confirmation token, and a real rationale. Duplicate
modules are rejected. The task's profile must satisfy every selected module's
minimum risk profile. When no module applies use exactly:

- None selected — <optional: why no module applies>
-->

## Files changed

- [paths]

## Verification

### Baseline

[Command and result before changes began.]

### Final

[Command and result after the final modification.]

## Remaining risks

- [Known risks, blockers, or open questions]